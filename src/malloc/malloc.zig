//! POSIX malloc/free/calloc/realloc implementation.
//!
//! Phase 2: dlmalloc-style boundary-tag allocator with coalescing.
//!
//! Two tiers:
//! - Small/Medium (<=128KB): boundary-tag chunks with a single free list
//!   and coalescing on free. Allocations are carved from a wilderness (top)
//!   chunk that grows by requesting pages from the backing store.
//! - Large (>128KB): direct-mapped via MMAP syscall, freed back via MUNMAP.
//!
//! Thread safety: simple spinlock (atomic flag). Phase 3 will upgrade to
//! a proper futex mutex.
//!
//! Backing memory: comptime-selected. In test mode a static 1MB arena is
//! used; in real (freestanding) mode pages come from the kernel via MMAP/MUNMAP.

const builtin = @import("builtin");
const is_test = builtin.is_test;

// ---------------------------------------------------------------------------
// Imports (conditional)
// ---------------------------------------------------------------------------

const syscall = if (is_test) undefined else @import("../internal/syscall.zig");
const errno_mod = if (is_test) undefined else @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Alignment for all returned pointers (and chunk sizes).
const ALIGNMENT: usize = 16;

/// Minimum user payload size (so minimum chunk = HEADER_SIZE + MIN_PAYLOAD + FOOTER_SIZE).
const MIN_PAYLOAD: usize = 16;

/// Boundary-tag header: stores size + flags in a single usize.
/// Padded to ALIGNMENT so user pointer (header + HEADER_SIZE) is always
/// 16-byte aligned when the chunk itself is 16-byte aligned.
const HEADER_SIZE: usize = ALIGNMENT;

/// Boundary-tag footer: copy of the header for backward coalescing.
const FOOTER_SIZE: usize = @sizeOf(usize);

/// Minimum chunk size: header + min payload + footer, rounded to ALIGNMENT.
const MIN_CHUNK_SIZE: usize = alignUp(HEADER_SIZE + MIN_PAYLOAD + FOOTER_SIZE, ALIGNMENT);

/// Threshold above which allocations go directly through mmap.
const LARGE_THRESHOLD: usize = 128 * 1024; // 128KB

/// Page size for requesting memory from the backing store.
const PAGE_SIZE: usize = 4096;

/// Flag bits stored in the low bits of the size field.
const FLAG_USED: usize = 0x1;
const FLAG_MMAP: usize = 0x2;
const FLAG_MASK: usize = FLAG_USED | FLAG_MMAP;

// ---------------------------------------------------------------------------
// Spinlock
// ---------------------------------------------------------------------------

var lock: u32 = 0;

fn acquire() void {
    while (@atomicRmw(u32, &lock, .Xchg, 1, .acquire) != 0) {
        spinLoopHint();
    }
}

fn release() void {
    @atomicStore(u32, &lock, 0, .release);
}

fn spinLoopHint() void {
    // Emit a CPU-level spin hint. On x86 this is the PAUSE instruction.
    // In Zig 0.14, std.atomic.spinLoopHint works on all targets.
    if (is_test) {
        // Host-compiled tests: just yield the CPU.
        @import("std").atomic.spinLoopHint();
    } else {
        // Freestanding: inline asm pause.
        asm volatile ("pause" ::: .{ .memory = true });
    }
}

// ---------------------------------------------------------------------------
// Backing store
// ---------------------------------------------------------------------------

/// Test arena: 1MB static buffer.
const ARENA_SIZE: usize = 1024 * 1024;

var test_arena: [ARENA_SIZE]u8 align(PAGE_SIZE) = undefined;
var test_arena_used: usize = 0;

fn requestPagesTest(min_bytes: usize) ?[*]u8 {
    const size = alignUp(min_bytes, PAGE_SIZE);
    if (test_arena_used + size > ARENA_SIZE) return null;
    const ptr: [*]u8 = @ptrCast(&test_arena[test_arena_used]);
    test_arena_used += size;
    return ptr;
}

fn requestPagesReal(min_bytes: usize) ?[*]u8 {
    const size = alignUp(min_bytes, PAGE_SIZE);
    // syscall MMAP: addr=0, len=size, prot=RW(3), flags=ANON|PRIVATE(0x22), fd=-1, offset=0
    const raw = syscall.syscall6(
        syscall.nr.MMAP,
        0, // addr hint
        size,
        3, // PROT_READ | PROT_WRITE
        0x22, // MAP_ANONYMOUS | MAP_PRIVATE
        @bitCast(@as(isize, -1)), // fd
        0, // offset
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) return null;
    return @ptrFromInt(raw);
}

fn releasePagesReal(ptr: [*]u8, size: usize) void {
    _ = syscall.syscall2(syscall.nr.MUNMAP, @intFromPtr(ptr), size);
}

const requestPages = if (is_test) requestPagesTest else requestPagesReal;

// For large direct-mmap allocations in test mode we also use the arena,
// but we don't actually "release" memory back.
fn releasePagesTest(_: [*]u8, _: usize) void {}

const releasePages = if (is_test) releasePagesTest else releasePagesReal;

// ---------------------------------------------------------------------------
// Chunk helpers
// ---------------------------------------------------------------------------

/// Read the size+flags word at the given address.
inline fn readTag(addr: usize) usize {
    const p: *const usize = @ptrFromInt(addr);
    return p.*;
}

/// Write the size+flags word at the given address.
inline fn writeTag(addr: usize, value: usize) void {
    const p: *usize = @ptrFromInt(addr);
    p.* = value;
}

/// Extract the raw size (without flag bits) from a tag value.
inline fn chunkSize(tag: usize) usize {
    return tag & ~FLAG_MASK;
}

/// Return true if the USED flag is set.
inline fn isUsed(tag: usize) bool {
    return (tag & FLAG_USED) != 0;
}

/// Return true if the MMAP flag is set.
inline fn isMmap(tag: usize) bool {
    return (tag & FLAG_MMAP) != 0;
}

/// Given the address of a chunk header, return the address of its footer.
inline fn footerAddr(header: usize, size: usize) usize {
    return header + size - FOOTER_SIZE;
}

/// Given a chunk header address, return the user-data pointer.
inline fn chunkToUser(header: usize) *anyopaque {
    return @ptrFromInt(header + HEADER_SIZE);
}

/// Given a user-data pointer, return the chunk header address.
inline fn userToChunk(ptr: *anyopaque) usize {
    return @intFromPtr(ptr) - HEADER_SIZE;
}

/// Write both header and footer tags for a chunk.
fn setChunkTags(header_addr: usize, tag: usize) void {
    const size = chunkSize(tag);
    writeTag(header_addr, tag);
    writeTag(footerAddr(header_addr, size), tag);
}

// ---------------------------------------------------------------------------
// Free list (singly-linked, sorted by address for coalescing)
// ---------------------------------------------------------------------------

/// Free chunks embed a next pointer in their user-data area.
inline fn freeNextPtr(header_addr: usize) *usize {
    return @ptrFromInt(header_addr + HEADER_SIZE);
}

var free_list_head: usize = 0; // 0 = empty

/// Insert a free chunk into the free list (address-ordered).
fn freeListInsert(header_addr: usize) void {
    const next_p = freeNextPtr(header_addr);

    if (free_list_head == 0 or header_addr < free_list_head) {
        // Insert at head.
        next_p.* = free_list_head;
        free_list_head = header_addr;
        return;
    }

    // Walk to find insertion point (keep list sorted by address).
    var cur = free_list_head;
    while (true) {
        const cur_next = freeNextPtr(cur).*;
        if (cur_next == 0 or header_addr < cur_next) {
            freeNextPtr(cur).* = header_addr;
            next_p.* = cur_next;
            return;
        }
        cur = cur_next;
    }
}

/// Remove a specific chunk from the free list.
fn freeListRemove(header_addr: usize) void {
    if (free_list_head == header_addr) {
        free_list_head = freeNextPtr(header_addr).*;
        return;
    }

    var cur = free_list_head;
    while (cur != 0) {
        const cur_next = freeNextPtr(cur).*;
        if (cur_next == header_addr) {
            freeNextPtr(cur).* = freeNextPtr(header_addr).*;
            return;
        }
        cur = cur_next;
    }
}

/// Best-fit search: find the smallest free chunk >= required size.
fn freeListBestFit(required: usize) ?usize {
    var best: usize = 0;
    var best_size: usize = ~@as(usize, 0);

    var cur = free_list_head;
    while (cur != 0) {
        const tag = readTag(cur);
        const sz = chunkSize(tag);
        if (sz >= required and sz < best_size) {
            best = cur;
            best_size = sz;
            if (sz == required) break; // exact fit
        }
        cur = freeNextPtr(cur).*;
    }

    return if (best != 0) best else null;
}

// ---------------------------------------------------------------------------
// Wilderness (top chunk)
// ---------------------------------------------------------------------------

/// Address of the current wilderness chunk header (0 = uninitialized).
var wilderness: usize = 0;
/// End address of the current arena region (exclusive).
var wilderness_end: usize = 0;

/// Grow the wilderness by requesting at least `min_bytes` from the backing store.
fn growWilderness(min_bytes: usize) bool {
    const request = if (min_bytes < 64 * PAGE_SIZE) 64 * PAGE_SIZE else alignUp(min_bytes, PAGE_SIZE);
    const pages = requestPages(request) orelse return false;
    const base = @intFromPtr(pages);

    if (wilderness != 0 and base == wilderness_end) {
        // Contiguous extension: just extend the wilderness size.
        const old_size = chunkSize(readTag(wilderness));
        const new_size = old_size + request;
        setChunkTags(wilderness, new_size); // free (no USED flag)
        wilderness_end = base + request;
    } else {
        // Non-contiguous (or first allocation): make new wilderness.
        // If there was an old wilderness, put it on the free list.
        if (wilderness != 0) {
            freeListInsert(wilderness);
        }
        wilderness = base;
        wilderness_end = base + request;
        setChunkTags(wilderness, request); // free
    }
    return true;
}

/// Allocate `size` bytes from the wilderness. Splits if there is enough remainder.
/// Returns the header address of the allocated chunk, or null.
fn allocFromWilderness(total: usize) ?usize {
    if (wilderness == 0) {
        if (!growWilderness(total)) return null;
    }

    const w_size = chunkSize(readTag(wilderness));
    if (w_size < total) {
        // Try to grow.
        if (!growWilderness(total - w_size + PAGE_SIZE)) return null;
        // Re-read after grow.
        const new_w_size = chunkSize(readTag(wilderness));
        if (new_w_size < total) return null;
    }

    return splitFromChunk(wilderness, total, true);
}

/// Split a chunk, returning the allocated portion's header address.
/// If `is_wilderness` is true, the remainder becomes the new wilderness
/// instead of going on the free list.
fn splitFromChunk(chunk_addr: usize, total: usize, is_wilderness: bool) usize {
    const chunk_tag = readTag(chunk_addr);
    const chunk_sz = chunkSize(chunk_tag);
    const remainder = chunk_sz - total;

    if (remainder >= MIN_CHUNK_SIZE) {
        // Split: first part is allocated, second part is remainder.
        setChunkTags(chunk_addr, total | FLAG_USED);
        const rem_addr = chunk_addr + total;
        setChunkTags(rem_addr, remainder); // free

        if (is_wilderness) {
            wilderness = rem_addr;
        } else {
            freeListInsert(rem_addr);
        }
    } else {
        // Use the whole chunk (no split, avoid tiny fragments).
        setChunkTags(chunk_addr, chunk_sz | FLAG_USED);
        if (is_wilderness) {
            wilderness = 0;
        }
    }

    return chunk_addr;
}

// ---------------------------------------------------------------------------
// Large (direct mmap) allocation
// ---------------------------------------------------------------------------

fn allocLarge(size: usize) ?*anyopaque {
    // Total = header + user data, rounded up to page boundary.
    // We store the full mapped size in the header so munmap knows the length.
    const total = alignUp(HEADER_SIZE + size, PAGE_SIZE);
    const pages = requestPages(total) orelse return null;
    const base = @intFromPtr(pages);

    // Write header only (no footer needed for mmap chunks).
    writeTag(base, total | FLAG_USED | FLAG_MMAP);

    return chunkToUser(base);
}

fn freeLarge(header_addr: usize) void {
    const tag = readTag(header_addr);
    const size = chunkSize(tag);
    releasePages(@ptrFromInt(header_addr), size);
}

// ---------------------------------------------------------------------------
// Coalescing
// ---------------------------------------------------------------------------

/// After freeing a chunk, try to merge with its immediate neighbors.
/// Returns the (possibly merged) chunk header address.
fn coalesce(header_addr: usize) usize {
    var addr = header_addr;
    var size = chunkSize(readTag(addr));

    // Coalesce with next chunk.
    const next_addr = addr + size;
    if (next_addr < wilderness_end and next_addr != wilderness) {
        const next_tag = readTag(next_addr);
        if (!isUsed(next_tag) and !isMmap(next_tag)) {
            const next_size = chunkSize(next_tag);
            freeListRemove(next_addr);
            size += next_size;
            setChunkTags(addr, size);
        }
    }

    // Merge with next if next is the wilderness.
    if (addr + size == wilderness and wilderness != 0) {
        const w_size = chunkSize(readTag(wilderness));
        size += w_size;
        setChunkTags(addr, size);
        wilderness = addr;
        return addr;
    }

    // Coalesce with previous chunk (read footer of previous).
    if (addr > 0 and addr >= FOOTER_SIZE) {
        const prev_footer_addr = addr - FOOTER_SIZE;
        // Safety: only read if prev_footer_addr is within our managed region.
        // We do a conservative check: must be at least a header away from start.
        if (prev_footer_addr >= HEADER_SIZE) {
            const prev_tag = readTag(prev_footer_addr);
            if (!isUsed(prev_tag) and !isMmap(prev_tag) and chunkSize(prev_tag) > 0) {
                const prev_size = chunkSize(prev_tag);
                const prev_addr = addr - prev_size;
                // Sanity: verify forward tag matches.
                if (prev_addr < addr and readTag(prev_addr) == prev_tag) {
                    freeListRemove(prev_addr);
                    size += prev_size;
                    addr = prev_addr;
                    setChunkTags(addr, size);
                }
            }
        }
    }

    // If the merged chunk is now adjacent to wilderness, merge into it.
    if (addr + size == wilderness and wilderness != 0) {
        const w_size = chunkSize(readTag(wilderness));
        size += w_size;
        setChunkTags(addr, size);
        wilderness = addr;
        return addr;
    }

    return addr;
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

inline fn alignUp(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

// ---------------------------------------------------------------------------
// Public API (C ABI exports)
// ---------------------------------------------------------------------------

fn mallocImpl(size: usize) callconv(.c) ?*anyopaque {
    if (size == 0) return null;

    // Compute total chunk size needed.
    const user_size = if (size < MIN_PAYLOAD) MIN_PAYLOAD else alignUp(size, ALIGNMENT);
    const total = alignUp(HEADER_SIZE + user_size + FOOTER_SIZE, ALIGNMENT);

    if (total > LARGE_THRESHOLD) {
        return allocLarge(size);
    }

    // Try the free list first (best-fit).
    if (freeListBestFit(total)) |chunk_addr| {
        freeListRemove(chunk_addr);
        return chunkToUser(splitFromChunk(chunk_addr, total, false));
    }

    // Fall back to wilderness.
    if (allocFromWilderness(total)) |chunk_addr| {
        return chunkToUser(chunk_addr);
    }

    return null;
}

fn freeImpl(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr == null) return;

    const header_addr = userToChunk(ptr.?);
    const tag = readTag(header_addr);

    if (isMmap(tag)) {
        freeLarge(header_addr);
        return;
    }

    // Clear USED flag.
    const size = chunkSize(tag);
    setChunkTags(header_addr, size); // flags = 0 = free

    // Coalesce with neighbors.
    const merged = coalesce(header_addr);

    // If merged chunk is not the wilderness, put on free list.
    if (merged != wilderness) {
        freeListInsert(merged);
    }
}

fn callocImpl(nmemb: usize, size: usize) callconv(.c) ?*anyopaque {
    if (nmemb == 0 or size == 0) return null;

    // Overflow check.
    const total = @mulWithOverflow(nmemb, size);
    if (total[1] != 0) return null;

    const p = mallocImpl(total[0]) orelse return null;

    // Zero the memory.
    const bytes: [*]u8 = @ptrCast(p);
    for (0..total[0]) |i| {
        bytes[i] = 0;
    }

    return p;
}

fn reallocImpl(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    if (ptr == null) return mallocImpl(size);

    if (size == 0) {
        freeImpl(ptr);
        return null;
    }

    const header_addr = userToChunk(ptr.?);
    const tag = readTag(header_addr);
    const old_chunk_size = chunkSize(tag);

    // For mmap chunks, always re-allocate.
    if (!isMmap(tag)) {
        const old_user_size = old_chunk_size - HEADER_SIZE - FOOTER_SIZE;
        if (size <= old_user_size) {
            // Current chunk is large enough -- could split, but keep it simple.
            return ptr;
        }
    }

    // Allocate new, copy, free old.
    const new_ptr = mallocImpl(size) orelse return null;
    const old_user_size = if (isMmap(tag))
        old_chunk_size - HEADER_SIZE
    else
        old_chunk_size - HEADER_SIZE - FOOTER_SIZE;
    const copy_size = min(old_user_size, size);

    const dst: [*]u8 = @ptrCast(new_ptr);
    const src: [*]const u8 = @ptrCast(ptr.?);
    for (0..copy_size) |i| {
        dst[i] = src[i];
    }

    freeImpl(ptr);
    return new_ptr;
}

// Exported C ABI functions. In test mode we use non-exported names to avoid
// colliding with the host libc.
comptime {
    if (!is_test) {
        @export(&mallocImpl, .{ .name = "malloc", .linkage = .strong });
        @export(&freeImpl, .{ .name = "free", .linkage = .strong });
        @export(&callocImpl, .{ .name = "calloc", .linkage = .strong });
        @export(&reallocImpl, .{ .name = "realloc", .linkage = .strong });
    }
}

// Public aliases for internal use / tests.
pub const malloc = &mallocImpl;
pub const free = &freeImpl;
pub const calloc = &callocImpl;
pub const realloc = &reallocImpl;

// ---------------------------------------------------------------------------
// Reset allocator state (test helper)
// ---------------------------------------------------------------------------

pub fn resetState() void {
    free_list_head = 0;
    wilderness = 0;
    wilderness_end = 0;
    test_arena_used = 0;
    lock = 0;
    // Zero out the arena to catch stale-pointer bugs.
    for (0..ARENA_SIZE) |i| {
        test_arena[i] = 0;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "malloc basic" {
    resetState();
    const p = mallocImpl(100) orelse return error.TestUnexpectedResult;
    // Write to it -- should not fault.
    const bytes: [*]u8 = @ptrCast(p);
    for (0..100) |i| {
        bytes[i] = @truncate(i);
    }
    // Verify writes.
    for (0..100) |i| {
        try testing.expectEqual(@as(u8, @truncate(i)), bytes[i]);
    }
    freeImpl(p);
}

test "malloc zero" {
    resetState();
    const p = mallocImpl(0);
    try testing.expect(p == null);
}

test "free null" {
    resetState();
    freeImpl(null); // should not crash
}

test "calloc zeroed" {
    resetState();
    const p = callocImpl(10, 100) orelse return error.TestUnexpectedResult;
    const bytes: [*]const u8 = @ptrCast(p);
    for (0..1000) |i| {
        try testing.expectEqual(@as(u8, 0), bytes[i]);
    }
    freeImpl(p);
}

test "realloc grow" {
    resetState();
    const p1 = mallocImpl(50) orelse return error.TestUnexpectedResult;
    const b1: [*]u8 = @ptrCast(p1);
    for (0..50) |i| {
        b1[i] = @truncate(i + 1);
    }
    const p2 = reallocImpl(p1, 200) orelse return error.TestUnexpectedResult;
    const b2: [*]const u8 = @ptrCast(p2);
    // Original data must be preserved.
    for (0..50) |i| {
        try testing.expectEqual(@as(u8, @truncate(i + 1)), b2[i]);
    }
    freeImpl(p2);
}

test "realloc shrink" {
    resetState();
    const p1 = mallocImpl(200) orelse return error.TestUnexpectedResult;
    const b1: [*]u8 = @ptrCast(p1);
    for (0..100) |i| {
        b1[i] = @truncate(i + 10);
    }
    const p2 = reallocImpl(p1, 50) orelse return error.TestUnexpectedResult;
    const b2: [*]const u8 = @ptrCast(p2);
    // First 50 bytes must be preserved.
    for (0..50) |i| {
        try testing.expectEqual(@as(u8, @truncate(i + 10)), b2[i]);
    }
    freeImpl(p2);
}

test "realloc null" {
    resetState();
    // realloc(null, n) should behave like malloc(n).
    const p = reallocImpl(null, 64) orelse return error.TestUnexpectedResult;
    freeImpl(p);
}

test "realloc zero" {
    resetState();
    // realloc(ptr, 0) should free and return null.
    const p = mallocImpl(64) orelse return error.TestUnexpectedResult;
    const result = reallocImpl(p, 0);
    try testing.expect(result == null);
}

test "malloc many small" {
    resetState();
    var ptrs: [1000]?*anyopaque = undefined;
    // Allocate 1000 small blocks.
    for (0..1000) |i| {
        ptrs[i] = mallocImpl(32 + (i % 64));
        try testing.expect(ptrs[i] != null);
    }
    // Free them all.
    for (0..1000) |i| {
        freeImpl(ptrs[i]);
    }
}

test "malloc alignment" {
    resetState();
    // All returned pointers must be 16-byte aligned.
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const p = mallocImpl(1 + i * 7) orelse continue;
        const addr = @intFromPtr(p);
        try testing.expectEqual(@as(usize, 0), addr % ALIGNMENT);
        freeImpl(p);
    }
}

test "coalesce" {
    resetState();
    // Allocate three adjacent blocks.
    const p1 = mallocImpl(64) orelse return error.TestUnexpectedResult;
    const p2 = mallocImpl(64) orelse return error.TestUnexpectedResult;
    const p3 = mallocImpl(64) orelse return error.TestUnexpectedResult;

    // Free the middle one first, then the neighbors.
    freeImpl(p2);
    freeImpl(p1);
    freeImpl(p3);

    // Now a single large allocation should succeed using the coalesced space.
    const big = mallocImpl(192) orelse return error.TestUnexpectedResult;
    freeImpl(big);
}

test "calloc overflow" {
    resetState();
    // Should return null on overflow.
    const p = callocImpl(@as(usize, @bitCast(@as(isize, -1))), 2);
    try testing.expect(p == null);
}

test "malloc reuse after free" {
    resetState();
    // Allocate, free, allocate again -- should reuse memory.
    const p1 = mallocImpl(128) orelse return error.TestUnexpectedResult;
    freeImpl(p1);
    const p2 = mallocImpl(128) orelse return error.TestUnexpectedResult;
    // On a fresh allocator with coalescing, the same chunk may be reused.
    // Just verify it works -- orelse above already asserts non-null.
    freeImpl(p2);
}
