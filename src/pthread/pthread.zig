//! POSIX pthreads implementation (Phase 3).
//!
//! Provides mutex (Drepper 3-state futex), condition variables,
//! thread create/join/exit, thread-specific data (keys), and once.
//!
//! Futex operations use TerranoxOS-specific syscalls:
//!   GEN_SYS_TRX_FUTEX_WAIT (0x0117)
//!   GEN_SYS_TRX_FUTEX_WAKE (0x0118)
//!
//! Thread lifecycle uses:
//!   GEN_SYS_TRX_THREAD_CREATE (0x0110)
//!   GEN_SYS_TRX_THREAD_EXIT   (0x0111)
//!   GEN_SYS_TRX_THREAD_JOIN   (0x0112)
//!   GEN_SYS_YIELD              (0x0005)

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");
const malloc_mod = @import("../malloc/malloc.zig");

// ---------------------------------------------------------------------------
// TRX syscall numbers (available in genesis_syscall.h)
// ---------------------------------------------------------------------------

const SYS_TRX_THREAD_CREATE: usize = 0x0110;
const SYS_TRX_THREAD_EXIT: usize = 0x0111;
const SYS_TRX_THREAD_JOIN: usize = 0x0112;
const SYS_TRX_FUTEX_WAIT: usize = 0x0117;
const SYS_TRX_FUTEX_WAKE: usize = 0x0118;
const SYS_YIELD: usize = 0x0005;
const SYS_MMAP: usize = 0x0003;
const SYS_MUNMAP: usize = 0x0004;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const pthread_t = u64;

pub const pthread_mutex_t = extern struct {
    state: u32 = 0, // 0=unlocked, 1=locked-no-waiters, 2=locked-has-waiters
    _pad: [28]u8 = [_]u8{0} ** 28, // pad to 32 bytes for ABI compat
};

pub const pthread_cond_t = extern struct {
    seq: u32 = 0, // sequence counter
    _pad: [28]u8 = [_]u8{0} ** 28,
};

pub const pthread_attr_t = extern struct {
    stack_size: usize = 2 * 1024 * 1024, // 2MB default
    detach_state: c_int = 0,
    _pad: [48]u8 = [_]u8{0} ** 48,
};

pub const pthread_key_t = u32;
pub const PTHREAD_KEYS_MAX: usize = 128;

pub const pthread_once_t = u32;
const ONCE_UNINIT: u32 = 0;
const ONCE_RUNNING: u32 = 1;
const ONCE_COMPLETE: u32 = 2;

// ---------------------------------------------------------------------------
// Futex helpers (real syscalls in freestanding, stubs in test)
// ---------------------------------------------------------------------------

fn futex_wait_real(addr: *const u32, expected: u32) void {
    _ = syscall.syscall3(
        SYS_TRX_FUTEX_WAIT,
        @intFromPtr(addr),
        @as(usize, expected),
        0, // no timeout
    );
}

fn futex_wake_real(addr: *const u32, count: u32) void {
    _ = syscall.syscall2(
        SYS_TRX_FUTEX_WAKE,
        @intFromPtr(addr),
        @as(usize, count),
    );
}

// Test stubs: no-ops (single-threaded tests only exercise state machine)
fn futex_wait_test(_: *const u32, _: u32) void {}
fn futex_wake_test(_: *const u32, _: u32) void {}

const futex_wait = if (is_test) futex_wait_test else futex_wait_real;
const futex_wake = if (is_test) futex_wake_test else futex_wake_real;

fn spinLoopHint() void {
    if (is_test) {
        @import("std").atomic.spinLoopHint();
    } else {
        asm volatile ("pause" ::: "memory");
    }
}

// ---------------------------------------------------------------------------
// Mutex (Drepper 3-state futex algorithm)
//
// State 0: unlocked
// State 1: locked, no waiters
// State 2: locked, has waiters
// ---------------------------------------------------------------------------

pub export fn pthread_mutex_init(mutex: *pthread_mutex_t, attr: ?*const anyopaque) c_int {
    _ = attr;
    mutex.state = 0;
    mutex._pad = [_]u8{0} ** 28;
    return 0;
}

pub export fn pthread_mutex_lock(mutex: *pthread_mutex_t) c_int {
    // Fast path: CAS 0 -> 1 (uncontended acquisition)
    if (@cmpxchgStrong(u32, &mutex.state, 0, 1, .acquire, .monotonic) == null) {
        return 0;
    }

    // Slow path: set state to 2 (has waiters) and wait
    while (true) {
        // If state was already non-zero, exchange to 2 to indicate waiters
        const prev = @atomicRmw(u32, &mutex.state, .Xchg, 2, .acquire);
        if (prev == 0) {
            // We acquired the lock (was unlocked between our CAS and exchange)
            return 0;
        }

        // Wait until state might change
        futex_wait(&mutex.state, 2);
    }
}

pub export fn pthread_mutex_trylock(mutex: *pthread_mutex_t) c_int {
    // Try CAS 0 -> 1
    if (@cmpxchgStrong(u32, &mutex.state, 0, 1, .acquire, .monotonic) == null) {
        return 0;
    }
    // Lock is held — return EBUSY
    return errno_mod.EBUSY;
}

pub export fn pthread_mutex_unlock(mutex: *pthread_mutex_t) c_int {
    // Atomic exchange to 0 and check previous value
    const prev = @atomicRmw(u32, &mutex.state, .Xchg, 0, .release);

    // If there were waiters (state was 2), wake one
    if (prev == 2) {
        futex_wake(&mutex.state, 1);
    }

    return 0;
}

pub export fn pthread_mutex_destroy(mutex: *pthread_mutex_t) c_int {
    mutex.state = 0;
    return 0;
}

// ---------------------------------------------------------------------------
// Condition variable
//
// Simple sequence-counter approach:
// - cond_wait: save seq, unlock mutex, futex_wait on seq, re-lock mutex
// - cond_signal: increment seq, wake 1
// - cond_broadcast: increment seq, wake all
// ---------------------------------------------------------------------------

pub export fn pthread_cond_init(cond: *pthread_cond_t, attr: ?*const anyopaque) c_int {
    _ = attr;
    cond.seq = 0;
    cond._pad = [_]u8{0} ** 28;
    return 0;
}

pub export fn pthread_cond_wait(cond: *pthread_cond_t, mutex: *pthread_mutex_t) c_int {
    const saved_seq = @atomicLoad(u32, &cond.seq, .acquire);

    // Release mutex
    _ = pthread_mutex_unlock(mutex);

    // Wait for signal (seq change)
    futex_wait(&cond.seq, saved_seq);

    // Re-acquire mutex
    _ = pthread_mutex_lock(mutex);

    return 0;
}

pub export fn pthread_cond_signal(cond: *pthread_cond_t) c_int {
    _ = @atomicRmw(u32, &cond.seq, .Add, 1, .release);
    futex_wake(&cond.seq, 1);
    return 0;
}

pub export fn pthread_cond_broadcast(cond: *pthread_cond_t) c_int {
    _ = @atomicRmw(u32, &cond.seq, .Add, 1, .release);
    futex_wake(&cond.seq, 0x7FFFFFFF); // wake all waiters
    return 0;
}

pub export fn pthread_cond_destroy(cond: *pthread_cond_t) c_int {
    cond.seq = 0;
    return 0;
}

// ---------------------------------------------------------------------------
// Thread create / join / exit / self / yield
// ---------------------------------------------------------------------------

fn thread_create_real(thread: *pthread_t, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.C) ?*anyopaque, arg: ?*anyopaque) c_int {
    const stack_sz = if (attr) |a| a.stack_size else 2 * 1024 * 1024;

    // Allocate stack via mmap (anonymous, read-write)
    // Add one page for guard page
    const guard_sz: usize = 4096;
    const total_sz = stack_sz + guard_sz;

    const raw = syscall.syscall6(
        SYS_MMAP,
        0, // addr hint
        total_sz,
        3, // PROT_READ | PROT_WRITE
        0x22, // MAP_ANONYMOUS | MAP_PRIVATE
        @bitCast(@as(isize, -1)), // fd
        0, // offset
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return errno_mod.ENOMEM;
    }

    // Stack grows downward: stack_ptr = base + total_sz
    const stack_top = raw + total_sz;

    // Call trx_thread_create syscall
    const ret_raw = syscall.syscall4(
        SYS_TRX_THREAD_CREATE,
        @intFromPtr(start_routine),
        stack_top,
        stack_sz,
        @intFromPtr(arg),
    );
    const ret_signed: isize = @bitCast(ret_raw);
    if (ret_signed < 0 and ret_signed > -4096) {
        // Clean up the stack
        _ = syscall.syscall2(SYS_MUNMAP, raw, total_sz);
        errno_mod.errno = @intCast(-ret_signed);
        return @intCast(-ret_signed);
    }

    thread.* = @intCast(ret_raw);
    return 0;
}

fn thread_join_real(thread: pthread_t, retval: ?*?*anyopaque) c_int {
    const raw = syscall.syscall2(
        SYS_TRX_THREAD_JOIN,
        @intCast(thread),
        if (retval) |r| @intFromPtr(r) else 0,
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return @intCast(-signed);
    }
    return 0;
}

fn thread_exit_real(retval: ?*anyopaque) noreturn {
    _ = syscall.syscall1(SYS_TRX_THREAD_EXIT, @intFromPtr(retval));
    unreachable;
}

fn thread_self_real() pthread_t {
    // Use getpid as a fallback for thread ID in single-threaded contexts.
    // A real implementation would use a TLS field set by thread_create.
    const raw = syscall.syscall0(0x0006); // GEN_SYS_GETPID
    return @intCast(raw);
}

fn thread_yield_real() c_int {
    _ = syscall.syscall0(SYS_YIELD);
    return 0;
}

// Test stubs
fn thread_create_test(thread: *pthread_t, _: ?*const pthread_attr_t, _: *const fn (?*anyopaque) callconv(.C) ?*anyopaque, _: ?*anyopaque) c_int {
    thread.* = 42; // fake thread ID
    return 0;
}

fn thread_join_test(_: pthread_t, _: ?*?*anyopaque) c_int {
    return 0;
}

fn thread_exit_test(_: ?*anyopaque) noreturn {
    // In tests, we can't actually exit. This should never be called in tests.
    unreachable;
}

fn thread_self_test() pthread_t {
    return 1; // fake self ID
}

fn thread_yield_test() c_int {
    return 0;
}

const thread_create_impl = if (is_test) thread_create_test else thread_create_real;
const thread_join_impl = if (is_test) thread_join_test else thread_join_real;
const thread_exit_impl = if (is_test) thread_exit_test else thread_exit_real;
const thread_self_impl = if (is_test) thread_self_test else thread_self_real;
const thread_yield_impl = if (is_test) thread_yield_test else thread_yield_real;

pub export fn pthread_create(thread: *pthread_t, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.C) ?*anyopaque, arg: ?*anyopaque) c_int {
    return thread_create_impl(thread, attr, start_routine, arg);
}

pub export fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int {
    return thread_join_impl(thread, retval);
}

pub export fn pthread_exit(retval: ?*anyopaque) noreturn {
    thread_exit_impl(retval);
}

pub export fn pthread_self() pthread_t {
    return thread_self_impl();
}

pub export fn pthread_yield() c_int {
    return thread_yield_impl();
}

// ---------------------------------------------------------------------------
// Thread-specific data (pthread_key)
//
// Simple static array of PTHREAD_KEYS_MAX slots.
// Each slot has a value pointer and optional destructor.
// ---------------------------------------------------------------------------

const KeySlot = struct {
    in_use: bool = false,
    value: ?*anyopaque = null,
    destructor: ?*const fn (?*anyopaque) callconv(.C) void = null,
};

var tsd_slots: [PTHREAD_KEYS_MAX]KeySlot = [_]KeySlot{.{}} ** PTHREAD_KEYS_MAX;
var tsd_next_key: u32 = 0;

pub export fn pthread_key_create(key: *pthread_key_t, destructor: ?*const fn (?*anyopaque) callconv(.C) void) c_int {
    // Find a free slot
    var i: u32 = 0;
    while (i < PTHREAD_KEYS_MAX) : (i += 1) {
        const idx = (tsd_next_key + i) % @as(u32, @intCast(PTHREAD_KEYS_MAX));
        if (!tsd_slots[idx].in_use) {
            tsd_slots[idx] = .{
                .in_use = true,
                .value = null,
                .destructor = destructor,
            };
            key.* = idx;
            tsd_next_key = (idx + 1) % @as(u32, @intCast(PTHREAD_KEYS_MAX));
            return 0;
        }
    }
    return errno_mod.EAGAIN; // no free keys
}

pub export fn pthread_key_delete(key: pthread_key_t) c_int {
    if (key >= PTHREAD_KEYS_MAX) return errno_mod.EINVAL;
    if (!tsd_slots[key].in_use) return errno_mod.EINVAL;

    tsd_slots[key] = .{};
    return 0;
}

pub export fn pthread_setspecific(key: pthread_key_t, value: ?*const anyopaque) c_int {
    if (key >= PTHREAD_KEYS_MAX) return errno_mod.EINVAL;
    if (!tsd_slots[key].in_use) return errno_mod.EINVAL;

    tsd_slots[key].value = @constCast(value);
    return 0;
}

pub export fn pthread_getspecific(key: pthread_key_t) ?*anyopaque {
    if (key >= PTHREAD_KEYS_MAX) return null;
    if (!tsd_slots[key].in_use) return null;

    return tsd_slots[key].value;
}

// ---------------------------------------------------------------------------
// Once
// ---------------------------------------------------------------------------

pub export fn pthread_once(once: *pthread_once_t, init_routine: *const fn () callconv(.C) void) c_int {
    // Fast path: already complete
    if (@atomicLoad(u32, once, .acquire) == ONCE_COMPLETE) {
        return 0;
    }

    // Try to win the race: CAS UNINIT -> RUNNING
    if (@cmpxchgStrong(u32, once, ONCE_UNINIT, ONCE_RUNNING, .acquire, .monotonic) == null) {
        // We won — run the init routine
        init_routine();
        @atomicStore(u32, once, ONCE_COMPLETE, .release);
        // Wake any waiters
        futex_wake(once, 0x7FFFFFFF);
        return 0;
    }

    // Someone else is running or has completed. Spin until complete.
    while (@atomicLoad(u32, once, .acquire) != ONCE_COMPLETE) {
        // If state is RUNNING, futex_wait for change
        futex_wait(once, ONCE_RUNNING);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// Reset state (test helper)
// ---------------------------------------------------------------------------

fn resetTsdState() void {
    tsd_slots = [_]KeySlot{.{}} ** PTHREAD_KEYS_MAX;
    tsd_next_key = 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "pthread_mutex_t size is 32 bytes" {
    try testing.expectEqual(@as(usize, 32), @sizeOf(pthread_mutex_t));
}

test "pthread_cond_t size is 32 bytes" {
    try testing.expectEqual(@as(usize, 32), @sizeOf(pthread_cond_t));
}

test "pthread_attr_t has expected layout" {
    const attr = pthread_attr_t{};
    try testing.expectEqual(@as(usize, 2 * 1024 * 1024), attr.stack_size);
    try testing.expectEqual(@as(c_int, 0), attr.detach_state);
}

test "pthread_once_t is u32" {
    try testing.expectEqual(@as(usize, 4), @sizeOf(pthread_once_t));
}

test "mutex init sets state to unlocked" {
    var mutex: pthread_mutex_t = .{};
    const ret = pthread_mutex_init(&mutex, null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), mutex.state);
}

test "mutex lock sets state to 1 (uncontended)" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);

    const ret = pthread_mutex_lock(&mutex);
    try testing.expectEqual(@as(c_int, 0), ret);
    // State should be 1 (locked, no waiters) or 2 (locked, has waiters)
    try testing.expect(mutex.state >= 1);
}

test "mutex trylock succeeds when unlocked" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);

    const ret = pthread_mutex_trylock(&mutex);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expect(mutex.state >= 1);
}

test "mutex trylock fails when locked" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);

    // Lock it
    _ = pthread_mutex_lock(&mutex);

    // Trylock should fail with EBUSY
    const ret = pthread_mutex_trylock(&mutex);
    try testing.expectEqual(errno_mod.EBUSY, ret);

    // Clean up
    _ = pthread_mutex_unlock(&mutex);
}

test "mutex unlock sets state to 0" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);

    _ = pthread_mutex_lock(&mutex);
    const ret = pthread_mutex_unlock(&mutex);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), mutex.state);
}

test "mutex lock-unlock-trylock cycle" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);

    // Lock
    try testing.expectEqual(@as(c_int, 0), pthread_mutex_lock(&mutex));
    // Trylock should fail
    try testing.expectEqual(errno_mod.EBUSY, pthread_mutex_trylock(&mutex));
    // Unlock
    try testing.expectEqual(@as(c_int, 0), pthread_mutex_unlock(&mutex));
    // Trylock should now succeed
    try testing.expectEqual(@as(c_int, 0), pthread_mutex_trylock(&mutex));
    // Cleanup
    try testing.expectEqual(@as(c_int, 0), pthread_mutex_unlock(&mutex));

    _ = pthread_mutex_destroy(&mutex);
}

test "mutex destroy resets state" {
    var mutex = pthread_mutex_t{};
    _ = pthread_mutex_init(&mutex, null);
    _ = pthread_mutex_lock(&mutex);
    _ = pthread_mutex_unlock(&mutex);
    const ret = pthread_mutex_destroy(&mutex);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), mutex.state);
}

test "cond init sets seq to 0" {
    var cond = pthread_cond_t{};
    const ret = pthread_cond_init(&cond, null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), cond.seq);
}

test "cond signal increments seq" {
    var cond = pthread_cond_t{};
    _ = pthread_cond_init(&cond, null);

    try testing.expectEqual(@as(u32, 0), cond.seq);
    _ = pthread_cond_signal(&cond);
    try testing.expectEqual(@as(u32, 1), @atomicLoad(u32, &cond.seq, .acquire));
    _ = pthread_cond_signal(&cond);
    try testing.expectEqual(@as(u32, 2), @atomicLoad(u32, &cond.seq, .acquire));
}

test "cond broadcast increments seq" {
    var cond = pthread_cond_t{};
    _ = pthread_cond_init(&cond, null);

    _ = pthread_cond_broadcast(&cond);
    try testing.expectEqual(@as(u32, 1), @atomicLoad(u32, &cond.seq, .acquire));
}

test "cond destroy resets seq" {
    var cond = pthread_cond_t{};
    _ = pthread_cond_init(&cond, null);
    _ = pthread_cond_signal(&cond);
    _ = pthread_cond_destroy(&cond);
    try testing.expectEqual(@as(u32, 0), cond.seq);
}

test "once runs routine exactly once" {
    var once_ctrl: pthread_once_t = ONCE_UNINIT;
    var call_count: u32 = 0;

    // We need a C-calling-convention function for the callback
    const Ctx = struct {
        var count: *u32 = undefined;
        fn init() callconv(.C) void {
            count.* += 1;
        }
    };
    Ctx.count = &call_count;

    // First call: should run
    try testing.expectEqual(@as(c_int, 0), pthread_once(&once_ctrl, &Ctx.init));
    try testing.expectEqual(@as(u32, 1), call_count);

    // Second call: should NOT run again
    try testing.expectEqual(@as(c_int, 0), pthread_once(&once_ctrl, &Ctx.init));
    try testing.expectEqual(@as(u32, 1), call_count);

    // State should be COMPLETE
    try testing.expectEqual(ONCE_COMPLETE, @atomicLoad(u32, &once_ctrl, .acquire));
}

test "key create and delete" {
    resetTsdState();
    var key: pthread_key_t = undefined;
    const ret = pthread_key_create(&key, null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expect(key < PTHREAD_KEYS_MAX);

    const del_ret = pthread_key_delete(key);
    try testing.expectEqual(@as(c_int, 0), del_ret);
}

test "key set and get specific" {
    resetTsdState();
    var key: pthread_key_t = undefined;
    _ = pthread_key_create(&key, null);

    var data: u32 = 0xDEADBEEF;
    const set_ret = pthread_setspecific(key, @ptrCast(&data));
    try testing.expectEqual(@as(c_int, 0), set_ret);

    const got = pthread_getspecific(key);
    try testing.expect(got != null);
    const val_ptr: *u32 = @ptrCast(@alignCast(got.?));
    try testing.expectEqual(@as(u32, 0xDEADBEEF), val_ptr.*);

    _ = pthread_key_delete(key);
}

test "key getspecific returns null for unset key" {
    resetTsdState();
    var key: pthread_key_t = undefined;
    _ = pthread_key_create(&key, null);

    const got = pthread_getspecific(key);
    try testing.expect(got == null);

    _ = pthread_key_delete(key);
}

test "key getspecific returns null for invalid key" {
    resetTsdState();
    const got = pthread_getspecific(999);
    try testing.expect(got == null);
}

test "key delete makes slot reusable" {
    resetTsdState();
    var key1: pthread_key_t = undefined;
    _ = pthread_key_create(&key1, null);
    const saved_key = key1;
    _ = pthread_key_delete(key1);

    // Creating a new key should reuse the slot (or assign a new one)
    var key2: pthread_key_t = undefined;
    const ret = pthread_key_create(&key2, null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expect(key2 < PTHREAD_KEYS_MAX);
    _ = saved_key;
}

test "key create exhaustion" {
    resetTsdState();
    // Fill all slots
    var keys: [PTHREAD_KEYS_MAX]pthread_key_t = undefined;
    for (0..PTHREAD_KEYS_MAX) |i| {
        const ret = pthread_key_create(&keys[i], null);
        try testing.expectEqual(@as(c_int, 0), ret);
    }

    // Next create should fail
    var extra: pthread_key_t = undefined;
    const ret = pthread_key_create(&extra, null);
    try testing.expectEqual(errno_mod.EAGAIN, ret);

    // Clean up
    for (0..PTHREAD_KEYS_MAX) |i| {
        _ = pthread_key_delete(keys[i]);
    }
}

test "pthread_create test stub" {
    var tid: pthread_t = 0;
    const Dummy = struct {
        fn routine(_: ?*anyopaque) callconv(.C) ?*anyopaque {
            return null;
        }
    };
    const ret = pthread_create(&tid, null, &Dummy.routine, null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(pthread_t, 42), tid); // test stub value
}

test "pthread_join test stub" {
    const ret = pthread_join(42, null);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "pthread_self test stub" {
    const tid = pthread_self();
    try testing.expectEqual(@as(pthread_t, 1), tid);
}

test "pthread_yield test stub" {
    const ret = pthread_yield();
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "multiple keys independent values" {
    resetTsdState();
    var k1: pthread_key_t = undefined;
    var k2: pthread_key_t = undefined;
    _ = pthread_key_create(&k1, null);
    _ = pthread_key_create(&k2, null);

    var val1: u32 = 111;
    var val2: u32 = 222;
    _ = pthread_setspecific(k1, @ptrCast(&val1));
    _ = pthread_setspecific(k2, @ptrCast(&val2));

    const g1: *u32 = @ptrCast(@alignCast(pthread_getspecific(k1).?));
    const g2: *u32 = @ptrCast(@alignCast(pthread_getspecific(k2).?));
    try testing.expectEqual(@as(u32, 111), g1.*);
    try testing.expectEqual(@as(u32, 222), g2.*);

    _ = pthread_key_delete(k1);
    _ = pthread_key_delete(k2);
}
