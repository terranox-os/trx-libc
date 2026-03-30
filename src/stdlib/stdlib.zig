//! POSIX <stdlib.h> function implementations.
//!
//! Utility functions: numeric conversion, pseudo-random numbers,
//! sorting and searching. Exported with C ABI.

// ---------------------------------------------------------------------------
// atoi / abs / labs
// ---------------------------------------------------------------------------

export fn atoi(s: [*:0]const u8) c_int {
    var i: usize = 0;

    // Skip leading whitespace
    while (s[i] == ' ' or s[i] == '\t' or s[i] == '\n' or
        s[i] == '\r' or s[i] == 0x0b or s[i] == 0x0c) : (i += 1)
    {}

    // Optional sign
    var negative: bool = false;
    if (s[i] == '-') {
        negative = true;
        i += 1;
    } else if (s[i] == '+') {
        i += 1;
    }

    // Parse digits
    var result: c_int = 0;
    while (s[i] >= '0' and s[i] <= '9') : (i += 1) {
        result = result *% 10 +% @as(c_int, s[i] - '0');
    }

    return if (negative) -%result else result;
}

export fn abs(x: c_int) c_int {
    return if (x < 0) -%x else x;
}

export fn labs(x: c_long) c_long {
    return if (x < 0) -%x else x;
}

// ---------------------------------------------------------------------------
// rand / srand -- xorshift64 PRNG
// ---------------------------------------------------------------------------

const RAND_MAX: c_int = 0x7FFFFFFF; // 2^31 - 1

var prng_state: u64 = 1;

export fn srand(seed: c_uint) void {
    prng_state = if (seed == 0) 1 else @as(u64, seed);
}

export fn rand() c_int {
    var s = prng_state;
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    prng_state = s;
    return @intCast(s & @as(u64, @intCast(RAND_MAX)));
}

// ---------------------------------------------------------------------------
// bsearch
// ---------------------------------------------------------------------------

export fn bsearch(
    key: *const anyopaque,
    base: *const anyopaque,
    nmemb: usize,
    size: usize,
    compar: *const fn (*const anyopaque, *const anyopaque) callconv(.C) c_int,
) ?*const anyopaque {
    const base_addr: usize = @intFromPtr(base);
    var lo: usize = 0;
    var hi: usize = nmemb;

    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const elem: *const anyopaque = @ptrFromInt(base_addr + mid * size);
        const cmp = compar(key, elem);
        if (cmp == 0) {
            return elem;
        } else if (cmp < 0) {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// qsort -- insertion sort (simple, correct)
// ---------------------------------------------------------------------------

export fn qsort(
    base: *anyopaque,
    nmemb: usize,
    size: usize,
    compar: *const fn (*const anyopaque, *const anyopaque) callconv(.C) c_int,
) void {
    if (nmemb <= 1 or size == 0) return;

    const base_bytes: [*]u8 = @ptrCast(base);

    // Temporary buffer on the stack for swapping (up to 256 bytes inline)
    var tmp_buf: [256]u8 = undefined;

    var i: usize = 1;
    while (i < nmemb) : (i += 1) {
        var j: usize = i;
        while (j > 0) {
            const curr: *const anyopaque = @ptrFromInt(@intFromPtr(base_bytes) + j * size);
            const prev: *const anyopaque = @ptrFromInt(@intFromPtr(base_bytes) + (j - 1) * size);
            if (compar(curr, prev) < 0) {
                // Swap elements at j and j-1
                swapBytes(base_bytes + j * size, base_bytes + (j - 1) * size, size, &tmp_buf);
                j -= 1;
            } else {
                break;
            }
        }
    }
}

fn swapBytes(a: [*]u8, b: [*]u8, size: usize, tmp: *[256]u8) void {
    if (size <= 256) {
        @memcpy(tmp[0..size], a[0..size]);
        @memcpy(a[0..size], b[0..size]);
        @memcpy(b[0..size], tmp[0..size]);
    } else {
        // Byte-at-a-time fallback for large elements
        for (0..size) |i| {
            const t = a[i];
            a[i] = b[i];
            b[i] = t;
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "atoi positive" {
    try testing.expectEqual(@as(c_int, 42), atoi("42"));
    try testing.expectEqual(@as(c_int, 0), atoi("0"));
    try testing.expectEqual(@as(c_int, 123), atoi("123abc"));
}

test "atoi negative" {
    try testing.expectEqual(@as(c_int, -42), atoi("-42"));
    try testing.expectEqual(@as(c_int, -1), atoi("-1"));
}

test "atoi whitespace" {
    try testing.expectEqual(@as(c_int, 42), atoi("  42"));
    try testing.expectEqual(@as(c_int, 42), atoi("\t42"));
    try testing.expectEqual(@as(c_int, -7), atoi("  -7"));
}

test "atoi overflow wraps" {
    // C atoi has undefined behavior on overflow; our wrapping arithmetic
    // just produces a deterministic (wrapped) result.
    const val = atoi("99999999999");
    _ = val; // No crash is the test
}

test "atoi empty / non-digit" {
    try testing.expectEqual(@as(c_int, 0), atoi(""));
    try testing.expectEqual(@as(c_int, 0), atoi("abc"));
    try testing.expectEqual(@as(c_int, 0), atoi("+"));
}

test "abs" {
    try testing.expectEqual(@as(c_int, 5), abs(5));
    try testing.expectEqual(@as(c_int, 5), abs(-5));
    try testing.expectEqual(@as(c_int, 0), abs(0));
}

test "rand reproducibility" {
    srand(12345);
    const a = rand();
    const b = rand();
    // Same seed produces same sequence
    srand(12345);
    try testing.expectEqual(a, rand());
    try testing.expectEqual(b, rand());
}

test "rand range" {
    srand(42);
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const val = rand();
        try testing.expect(val >= 0);
        try testing.expect(val <= RAND_MAX);
    }
}

fn intCompareFn(a_ptr: *const anyopaque, b_ptr: *const anyopaque) callconv(.C) c_int {
    const a: *const c_int = @ptrCast(@alignCast(a_ptr));
    const b: *const c_int = @ptrCast(@alignCast(b_ptr));
    if (a.* < b.*) return -1;
    if (a.* > b.*) return 1;
    return 0;
}

test "qsort int array" {
    var arr = [_]c_int{ 5, 3, 8, 1, 9, 2, 7, 4, 6, 0 };
    qsort(&arr, arr.len, @sizeOf(c_int), &intCompareFn);
    const expected = [_]c_int{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    try testing.expectEqualSlices(c_int, &expected, &arr);
}

test "qsort empty and single" {
    var empty = [_]c_int{};
    qsort(&empty, 0, @sizeOf(c_int), &intCompareFn);

    var single = [_]c_int{42};
    qsort(&single, 1, @sizeOf(c_int), &intCompareFn);
    try testing.expectEqual(@as(c_int, 42), single[0]);
}

test "bsearch hit" {
    const arr = [_]c_int{ 1, 3, 5, 7, 9, 11 };
    const key: c_int = 7;
    const result = bsearch(
        @ptrCast(&key),
        @ptrCast(&arr),
        arr.len,
        @sizeOf(c_int),
        &intCompareFn,
    );
    try testing.expect(result != null);
    const found: *const c_int = @ptrCast(@alignCast(result.?));
    try testing.expectEqual(@as(c_int, 7), found.*);
}

test "bsearch miss" {
    const arr = [_]c_int{ 1, 3, 5, 7, 9, 11 };
    const key: c_int = 4;
    const result = bsearch(
        @ptrCast(&key),
        @ptrCast(&arr),
        arr.len,
        @sizeOf(c_int),
        &intCompareFn,
    );
    try testing.expect(result == null);
}

test "bsearch first and last" {
    const arr = [_]c_int{ 10, 20, 30 };
    const key_first: c_int = 10;
    try testing.expect(bsearch(
        @ptrCast(&key_first),
        @ptrCast(&arr),
        arr.len,
        @sizeOf(c_int),
        &intCompareFn,
    ) != null);

    const key_last: c_int = 30;
    try testing.expect(bsearch(
        @ptrCast(&key_last),
        @ptrCast(&arr),
        arr.len,
        @sizeOf(c_int),
        &intCompareFn,
    ) != null);
}

test "labs" {
    try testing.expectEqual(@as(c_long, 5), labs(5));
    try testing.expectEqual(@as(c_long, 5), labs(-5));
    try testing.expectEqual(@as(c_long, 0), labs(0));
}
