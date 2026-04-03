//! POSIX <string.h> function implementations.
//!
//! Memory and string operations exported with C ABI for use by
//! TerranoxOS userspace programs.

const builtin = @import("builtin");
const is_test = builtin.is_test;
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Memory operations
//
// In freestanding builds these are exported as C ABI symbols. During host
// testing we must not collide with the libc symbols the test runner links,
// so we keep them as normal Zig functions and test through the wrappers.
// ---------------------------------------------------------------------------

fn memcpy_impl(dest: [*]u8, src: [*]const u8, n: usize) callconv(.C) [*]u8 {
    for (0..n) |i| {
        dest[i] = src[i];
    }
    return dest;
}

fn memmove_impl(dest: [*]u8, src: [*]const u8, n: usize) callconv(.C) [*]u8 {
    if (n == 0) return dest;

    const d: usize = @intFromPtr(dest);
    const s: usize = @intFromPtr(src);

    if (d < s) {
        for (0..n) |i| {
            dest[i] = src[i];
        }
    } else {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            dest[i] = src[i];
        }
    }
    return dest;
}

fn memset_impl(dest: [*]u8, c: c_int, n: usize) callconv(.C) [*]u8 {
    const byte: u8 = @truncate(@as(c_uint, @bitCast(c)));
    for (0..n) |i| {
        dest[i] = byte;
    }
    return dest;
}

fn memcmp_impl(s1: [*]const u8, s2: [*]const u8, n: usize) callconv(.C) c_int {
    for (0..n) |i| {
        if (s1[i] != s2[i]) {
            return @as(c_int, s1[i]) - @as(c_int, s2[i]);
        }
    }
    return 0;
}

// Export C ABI symbols only in non-test (freestanding) builds.
comptime {
    if (!is_test) {
        @export(&memcpy_impl, .{ .name = "memcpy", .linkage = .strong });
        @export(&memmove_impl, .{ .name = "memmove", .linkage = .strong });
        @export(&memset_impl, .{ .name = "memset", .linkage = .strong });
        @export(&memcmp_impl, .{ .name = "memcmp", .linkage = .strong });
    }
}

// Public aliases for tests and internal use.
pub const memcpy = &memcpy_impl;
pub const memmove = &memmove_impl;
pub const memset = &memset_impl;
pub const memcmp = &memcmp_impl;

// ---------------------------------------------------------------------------
// String operations
// ---------------------------------------------------------------------------

pub export fn strlen(s: [*:0]const u8) usize {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    return len;
}

pub export fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8 {
    var i: usize = 0;
    while (src[i] != 0) : (i += 1) {
        dest[i] = src[i];
    }
    dest[i] = 0;
    return dest;
}

pub export fn strncpy(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n and src[i] != 0) : (i += 1) {
        dest[i] = src[i];
    }
    while (i < n) : (i += 1) {
        dest[i] = 0;
    }
    return dest;
}

pub export fn strcat(dest: [*]u8, src: [*:0]const u8) [*]u8 {
    var i: usize = 0;
    while (dest[i] != 0) : (i += 1) {}

    var j: usize = 0;
    while (src[j] != 0) : (j += 1) {
        dest[i + j] = src[j];
    }
    dest[i + j] = 0;
    return dest;
}

pub export fn strncat(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (dest[i] != 0) : (i += 1) {}

    var j: usize = 0;
    while (j < n and src[j] != 0) : (j += 1) {
        dest[i + j] = src[j];
    }
    dest[i + j] = 0;
    return dest;
}

pub export fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int {
    var i: usize = 0;
    while (s1[i] != 0 and s1[i] == s2[i]) : (i += 1) {}
    return @as(c_int, s1[i]) - @as(c_int, s2[i]);
}

pub export fn strncmp(s1: [*]const u8, s2: [*]const u8, n: usize) c_int {
    for (0..n) |i| {
        if (s1[i] != s2[i] or s1[i] == 0) {
            return @as(c_int, s1[i]) - @as(c_int, s2[i]);
        }
    }
    return 0;
}

pub export fn strchr(s: [*:0]const u8, c: c_int) ?[*]const u8 {
    const byte: u8 = @truncate(@as(c_uint, @bitCast(c)));
    var i: usize = 0;
    while (true) {
        if (s[i] == byte) return s + i;
        if (s[i] == 0) return null;
        i += 1;
    }
}

pub export fn strrchr(s: [*:0]const u8, c: c_int) ?[*]const u8 {
    const byte: u8 = @truncate(@as(c_uint, @bitCast(c)));
    var last: ?[*]const u8 = null;
    var i: usize = 0;
    while (true) {
        if (s[i] == byte) last = s + i;
        if (s[i] == 0) return last;
        i += 1;
    }
}

pub export fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*]const u8 {
    if (needle[0] == 0) return haystack;

    const needle_len = strlen(needle);

    var i: usize = 0;
    while (haystack[i] != 0) {
        var j: usize = 0;
        while (j < needle_len and haystack[i + j] != 0 and haystack[i + j] == needle[j]) {
            j += 1;
        }
        if (j == needle_len) return haystack + i;
        i += 1;
    }
    return null;
}

pub export fn strerror(errnum: c_int) [*:0]const u8 {
    return switch (errnum) {
        0 => "Success",
        errno_mod.EPERM => "Operation not permitted",
        errno_mod.ENOENT => "No such file or directory",
        errno_mod.ESRCH => "No such process",
        errno_mod.EINTR => "Interrupted system call",
        errno_mod.EIO => "Input/output error",
        errno_mod.EBADF => "Bad file descriptor",
        errno_mod.EAGAIN => "Resource temporarily unavailable",
        errno_mod.ENOMEM => "Cannot allocate memory",
        errno_mod.EACCES => "Permission denied",
        errno_mod.EFAULT => "Bad address",
        errno_mod.EBUSY => "Device or resource busy",
        errno_mod.EEXIST => "File exists",
        errno_mod.EINVAL => "Invalid argument",
        errno_mod.EPIPE => "Broken pipe",
        errno_mod.ENOSYS => "Function not implemented",
        errno_mod.ETIMEDOUT => "Connection timed out",
        else => "Unknown error",
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "strlen" {
    try testing.expectEqual(@as(usize, 0), strlen(""));
    try testing.expectEqual(@as(usize, 5), strlen("hello"));
    try testing.expectEqual(@as(usize, 13), strlen("hello, world!"));
}

test "strcmp" {
    try testing.expect(strcmp("abc", "abc") == 0);
    try testing.expect(strcmp("abc", "abd") < 0);
    try testing.expect(strcmp("abd", "abc") > 0);
    try testing.expect(strcmp("", "") == 0);
    try testing.expect(strcmp("a", "") > 0);
    try testing.expect(strcmp("", "a") < 0);
    try testing.expect(strcmp("abc", "abcd") < 0);
}

test "strcpy" {
    var buf: [32]u8 = undefined;
    _ = strcpy(&buf, "hello");
    try testing.expectEqual(@as(u8, 'h'), buf[0]);
    try testing.expectEqual(@as(u8, 'o'), buf[4]);
    try testing.expectEqual(@as(u8, 0), buf[5]);
}

test "strcat" {
    var buf: [32]u8 = undefined;
    _ = strcpy(&buf, "hello");
    _ = strcat(&buf, " world");
    try testing.expectEqual(@as(u8, ' '), buf[5]);
    try testing.expectEqual(@as(u8, 'w'), buf[6]);
    try testing.expectEqual(@as(u8, 0), buf[11]);
}

test "strchr" {
    const s: [*:0]const u8 = "hello";
    const result = strchr(s, 'l');
    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 'l'), result.?[0]);
    try testing.expectEqual(@intFromPtr(s) + 2, @intFromPtr(result.?));

    try testing.expect(strchr(s, 'z') == null);
    try testing.expect(strchr(s, 0) != null);
}

test "strrchr" {
    const s: [*:0]const u8 = "hello";
    const result = strrchr(s, 'l');
    try testing.expect(result != null);
    try testing.expectEqual(@intFromPtr(s) + 3, @intFromPtr(result.?));

    try testing.expect(strrchr(s, 'z') == null);
}

test "memcpy" {
    var dest: [8]u8 = undefined;
    const src = "abcdefgh";
    _ = memcpy_impl(&dest, src, 8);
    try testing.expectEqualSlices(u8, "abcdefgh", &dest);
}

test "memset" {
    var buf: [4]u8 = undefined;
    _ = memset_impl(&buf, 'A', 4);
    try testing.expectEqualSlices(u8, "AAAA", &buf);
}

test "memcmp" {
    try testing.expect(memcmp_impl("abc", "abc", 3) == 0);
    try testing.expect(memcmp_impl("abc", "abd", 3) < 0);
    try testing.expect(memcmp_impl("abd", "abc", 3) > 0);
    try testing.expect(memcmp_impl("abc", "xyz", 0) == 0);
}

test "strerror" {
    const std = @import("std");
    const s_ok = strerror(0);
    try testing.expect(std.mem.eql(u8, std.mem.span(s_ok), "Success"));

    const s_inval = strerror(errno_mod.EINVAL);
    try testing.expect(std.mem.eql(u8, std.mem.span(s_inval), "Invalid argument"));

    const s_unknown = strerror(9999);
    try testing.expect(std.mem.eql(u8, std.mem.span(s_unknown), "Unknown error"));
}

test "strstr" {
    const haystack: [*:0]const u8 = "hello world";
    try testing.expect(strstr(haystack, "world") != null);
    try testing.expectEqual(@intFromPtr(haystack) + 6, @intFromPtr(strstr(haystack, "world").?));
    try testing.expect(strstr(haystack, "") != null);
    try testing.expect(strstr(haystack, "xyz") == null);
}

test "strncmp" {
    try testing.expect(strncmp("abcdef", "abcxyz", 3) == 0);
    try testing.expect(strncmp("abcdef", "abcxyz", 4) != 0);
    try testing.expect(strncmp("abc", "abc", 5) == 0);
}

test "strncpy" {
    var buf: [8]u8 = undefined;
    for (&buf) |*b| b.* = 0xFF;
    _ = strncpy(&buf, "hi", 8);
    try testing.expectEqual(@as(u8, 'h'), buf[0]);
    try testing.expectEqual(@as(u8, 'i'), buf[1]);
    try testing.expectEqual(@as(u8, 0), buf[2]);
    try testing.expectEqual(@as(u8, 0), buf[7]);
}

test "strncat" {
    var buf: [32]u8 = undefined;
    _ = strcpy(&buf, "hello");
    _ = strncat(&buf, " wonderful world", 6);
    // Appends " wonde" (6 chars) then null
    try testing.expectEqual(@as(u8, ' '), buf[5]);
    try testing.expectEqual(@as(u8, 'w'), buf[6]);
    try testing.expectEqual(@as(u8, 'o'), buf[7]);
    try testing.expectEqual(@as(u8, 'n'), buf[8]);
    try testing.expectEqual(@as(u8, 'd'), buf[9]);
    try testing.expectEqual(@as(u8, 'e'), buf[10]);
    try testing.expectEqual(@as(u8, 0), buf[11]);
}

test "memmove overlapping forward" {
    var buf = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    _ = memmove_impl(buf[2..].ptr, buf[0..].ptr, 4);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 1, 2, 3, 4, 7, 8 }, &buf);
}

test "memmove overlapping backward" {
    var buf = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    _ = memmove_impl(buf[0..].ptr, buf[2..].ptr, 4);
    try testing.expectEqualSlices(u8, &[_]u8{ 3, 4, 5, 6, 5, 6, 7, 8 }, &buf);
}
