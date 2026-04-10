//! POSIX <stdio.h> function implementations.
//!
//! Buffered I/O layer built on top of the raw syscall interface.
//! Provides FILE-based stream operations, standard streams (stdin/stdout/stderr),
//! and a printf formatting engine.
//!
//! Phase 1f: only static streams (stdin/stdout/stderr) are usable.
//! fopen/fclose require heap allocation and are deferred to Phase 2.

const builtin = @import("builtin");
const is_test = builtin.is_test;
const std = @import("std");

/// VaList is only available on x86_64 in Zig 0.14 (aarch64 disabled due to miscompilations).
const has_c_va_list = builtin.cpu.arch == .x86_64;
const VaList = if (has_c_va_list) std.builtin.VaList else void;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const BUFSIZ: usize = 4096;
pub const EOF: c_int = -1;

// FILE mode flags
const F_READ: u32 = 1;
const F_WRITE: u32 = 2;
const F_APPEND: u32 = 4;
const F_UNBUF: u32 = 8;
const F_LINEBUF: u32 = 16;

// ---------------------------------------------------------------------------
// FILE structure
// ---------------------------------------------------------------------------

pub const FILE = extern struct {
    fd: c_int,
    buf: [BUFSIZ]u8 = undefined,
    buf_pos: usize = 0,
    buf_len: usize = 0,
    buf_size: usize = BUFSIZ,
    flags: u32 = 0,
    error_flag: bool = false,
    eof_flag: bool = false,
};

// ---------------------------------------------------------------------------
// Standard streams (static)
// ---------------------------------------------------------------------------

var stdin_file = FILE{ .fd = 0, .flags = F_READ };
var stdout_file = FILE{ .fd = 1, .flags = F_WRITE | F_LINEBUF };
var stderr_file = FILE{ .fd = 2, .flags = F_WRITE | F_UNBUF };

// Export as pointers visible to C.
export var stdin: *FILE = &stdin_file;
export var stdout: *FILE = &stdout_file;
export var stderr: *FILE = &stderr_file;

// ---------------------------------------------------------------------------
// Low-level write helper (calls syscall or test hook)
// ---------------------------------------------------------------------------

/// In test mode we cannot issue real syscalls, so we use stubs.
/// In freestanding mode these call the real syscalls.
fn raw_write_test(_: c_int, _: [*]const u8, count: usize) isize {
    return @intCast(count);
}

fn raw_write_real(fd: c_int, buf: [*]const u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.WRITE, @intCast(fd), @intFromPtr(buf), count),
    );
}

const raw_write = if (is_test) raw_write_test else raw_write_real;

fn raw_read_test(_: c_int, _: [*]u8, _: usize) isize {
    return 0; // simulate EOF
}

fn raw_read_real(fd: c_int, buf: [*]u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.READ, @intCast(fd), @intFromPtr(buf), count),
    );
}

const raw_read = if (is_test) raw_read_test else raw_read_real;

// ---------------------------------------------------------------------------
// Core I/O: fflush
// ---------------------------------------------------------------------------

fn flush_impl(stream: *FILE) c_int {
    if (stream.flags & F_WRITE == 0) return 0;
    if (stream.buf_pos == 0) return 0;

    var written: usize = 0;
    while (written < stream.buf_pos) {
        const ret = raw_write(stream.fd, stream.buf[written..].ptr, stream.buf_pos - written);
        if (ret < 0) {
            stream.error_flag = true;
            return EOF;
        }
        written += @intCast(ret);
    }
    stream.buf_pos = 0;
    return 0;
}

pub export fn fflush(stream: ?*FILE) c_int {
    if (stream) |s| {
        return flush_impl(s);
    }
    // NULL: flush all standard streams
    var ret: c_int = 0;
    if (flush_impl(&stdout_file) != 0) ret = EOF;
    if (flush_impl(&stderr_file) != 0) ret = EOF;
    return ret;
}

// ---------------------------------------------------------------------------
// Core I/O: fputc / fgetc
// ---------------------------------------------------------------------------

fn fputc_impl(c: c_int, stream: *FILE) c_int {
    const byte: u8 = @truncate(@as(c_uint, @bitCast(c)));

    // Unbuffered: write immediately
    if (stream.flags & F_UNBUF != 0) {
        const ret = raw_write(stream.fd, @ptrCast(&byte), 1);
        if (ret < 0) {
            stream.error_flag = true;
            return EOF;
        }
        return @as(c_int, byte);
    }

    // Buffered: add to buffer
    stream.buf[stream.buf_pos] = byte;
    stream.buf_pos += 1;

    // Flush if buffer full or line-buffered and newline
    const should_flush = (stream.buf_pos >= stream.buf_size) or
        (stream.flags & F_LINEBUF != 0 and byte == '\n');

    if (should_flush) {
        if (flush_impl(stream) != 0) return EOF;
    }

    return @as(c_int, byte);
}

pub export fn fputc(c: c_int, stream: *FILE) c_int {
    return fputc_impl(c, stream);
}

fn fgetc_impl(stream: *FILE) c_int {
    if (stream.eof_flag) return EOF;

    // If buffer has data, return next byte
    if (stream.buf_pos < stream.buf_len) {
        const byte = stream.buf[stream.buf_pos];
        stream.buf_pos += 1;
        return @as(c_int, byte);
    }

    // Refill buffer
    const ret = raw_read(stream.fd, &stream.buf, stream.buf_size);
    if (ret < 0) {
        stream.error_flag = true;
        return EOF;
    }
    if (ret == 0) {
        stream.eof_flag = true;
        return EOF;
    }

    stream.buf_len = @intCast(ret);
    stream.buf_pos = 1;
    return @as(c_int, stream.buf[0]);
}

pub export fn fgetc(stream: *FILE) c_int {
    return fgetc_impl(stream);
}

// ---------------------------------------------------------------------------
// Core I/O: fwrite / fread
// ---------------------------------------------------------------------------

pub export fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: *FILE) usize {
    const total = size *| nmemb; // saturating multiply to avoid overflow
    if (total == 0) return 0;

    // Check for overflow
    if (size != 0 and total / size != nmemb) return 0;

    var written: usize = 0;
    while (written < total) {
        if (fputc_impl(@as(c_int, ptr[written]), stream) == EOF) {
            return written / size;
        }
        written += 1;
    }
    return nmemb;
}

pub export fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *FILE) usize {
    const total = size *| nmemb;
    if (total == 0) return 0;

    if (size != 0 and total / size != nmemb) return 0;

    var read_count: usize = 0;
    while (read_count < total) {
        const c = fgetc_impl(stream);
        if (c == EOF) {
            return read_count / size;
        }
        ptr[read_count] = @truncate(@as(c_uint, @bitCast(c)));
        read_count += 1;
    }
    return nmemb;
}

// ---------------------------------------------------------------------------
// Core I/O: fputs / puts / putchar
// ---------------------------------------------------------------------------

pub export fn fputs(s: [*:0]const u8, stream: *FILE) c_int {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        if (fputc_impl(@as(c_int, s[i]), stream) == EOF) return EOF;
    }
    return 0;
}

pub export fn puts(s: [*:0]const u8) c_int {
    if (fputs(s, &stdout_file) == EOF) return EOF;
    if (fputc_impl('\n', &stdout_file) == EOF) return EOF;
    return 0;
}

pub export fn putchar(c: c_int) c_int {
    return fputc_impl(c, &stdout_file);
}

// ---------------------------------------------------------------------------
// Error / EOF
// ---------------------------------------------------------------------------

pub export fn ferror(stream: *FILE) c_int {
    return if (stream.error_flag) @as(c_int, 1) else @as(c_int, 0);
}

pub export fn feof(stream: *FILE) c_int {
    return if (stream.eof_flag) @as(c_int, 1) else @as(c_int, 0);
}

pub export fn clearerr(stream: *FILE) void {
    stream.error_flag = false;
    stream.eof_flag = false;
}

// ---------------------------------------------------------------------------
// fopen / fclose / fseek / ftell (Phase 2 - requires malloc)
// ---------------------------------------------------------------------------

const fcntl_mod = @import("../fcntl/fcntl.zig");
const unistd_mod = @import("../unistd/unistd.zig");

// In test mode we use the internal malloc implementation directly.
// In freestanding mode it is also available via the same import.
const malloc_mod = @import("../malloc/malloc.zig");

// SEEK constants (matching POSIX / unistd.h)
const SEEK_SET: c_int = 0;
const SEEK_CUR: c_int = 1;
const SEEK_END: c_int = 2;

/// Parse a POSIX fopen mode string and return (O_flags, FILE_flags).
/// Returns null if the mode string is invalid.
fn parse_mode(mode: [*:0]const u8) ?struct { oflags: c_int, fflags: u32 } {
    if (mode[0] == 0) return null;

    const c0 = mode[0];
    const c1 = mode[1];

    // Check for '+' (read+write) — may be at position 1 or after 'b'
    var plus = false;
    if (c1 == '+') {
        plus = true;
    } else if (c1 == 'b' and mode[2] == '+') {
        plus = true;
    } else if (c1 != 0 and c1 != 'b') {
        return null; // invalid character after base mode
    }

    switch (c0) {
        'r' => {
            if (plus) {
                return .{
                    .oflags = fcntl_mod.O_RDWR,
                    .fflags = F_READ | F_WRITE,
                };
            }
            return .{
                .oflags = fcntl_mod.O_RDONLY,
                .fflags = F_READ,
            };
        },
        'w' => {
            if (plus) {
                return .{
                    .oflags = fcntl_mod.O_RDWR | fcntl_mod.O_CREAT | fcntl_mod.O_TRUNC,
                    .fflags = F_READ | F_WRITE,
                };
            }
            return .{
                .oflags = fcntl_mod.O_WRONLY | fcntl_mod.O_CREAT | fcntl_mod.O_TRUNC,
                .fflags = F_WRITE,
            };
        },
        'a' => {
            if (plus) {
                return .{
                    .oflags = fcntl_mod.O_RDWR | fcntl_mod.O_CREAT | fcntl_mod.O_APPEND,
                    .fflags = F_READ | F_WRITE | F_APPEND,
                };
            }
            return .{
                .oflags = fcntl_mod.O_WRONLY | fcntl_mod.O_CREAT | fcntl_mod.O_APPEND,
                .fflags = F_WRITE | F_APPEND,
            };
        },
        else => return null,
    }
}

/// Test-mode stubs for open/close/lseek — real syscalls are not available.
fn raw_open_test(_: [*:0]const u8, _: c_int, _: c_uint) c_int {
    return 3; // fake fd
}

fn raw_close_test(_: c_int) c_int {
    return 0;
}

fn raw_lseek_test(_: c_int, _: i64, _: c_int) i64 {
    return 0;
}

const raw_open = if (is_test) raw_open_test else fcntl_mod.open;
const raw_close = if (is_test) raw_close_test else unistd_mod.close;
const raw_lseek = if (is_test) raw_lseek_test else unistd_mod.lseek;

pub export fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE {
    const parsed = parse_mode(mode) orelse return null;

    // Open the file via syscall
    const fd = raw_open(path, parsed.oflags, 0o666);
    if (fd < 0) return null;

    // Allocate a FILE struct via malloc
    const raw_ptr = malloc_mod.malloc(@sizeOf(FILE)) orelse {
        _ = raw_close(fd);
        return null;
    };
    const file: *FILE = @ptrCast(@alignCast(raw_ptr));

    // Initialize the FILE struct
    file.* = FILE{
        .fd = fd,
        .flags = parsed.fflags,
    };

    return file;
}

pub export fn fclose(stream: *FILE) c_int {
    // Flush any pending buffered data
    var result: c_int = 0;
    if (flush_impl(stream) != 0) {
        result = EOF;
    }

    // Close the underlying file descriptor
    if (raw_close(stream.fd) < 0) {
        result = EOF;
    }

    // Free the FILE struct
    malloc_mod.free(@ptrCast(stream));

    return result;
}

pub export fn fseek(stream: *FILE, offset: c_long, whence: c_int) c_int {
    // Flush any pending writes before seeking
    if (stream.flags & F_WRITE != 0) {
        if (flush_impl(stream) != 0) return -1;
    }

    // For read streams, discard the buffer
    if (stream.flags & F_READ != 0) {
        stream.buf_pos = 0;
        stream.buf_len = 0;
    }

    const ret = raw_lseek(stream.fd, @as(i64, offset), whence);
    if (ret < 0) return -1;

    // Clear EOF flag on successful seek
    stream.eof_flag = false;

    return 0;
}

pub export fn ftell(stream: *FILE) c_long {
    // Get current position from kernel
    const pos = raw_lseek(stream.fd, 0, SEEK_CUR);
    if (pos < 0) return -1;

    // Adjust for buffered data:
    // If we have a read buffer, subtract unread bytes
    if (stream.flags & F_READ != 0 and stream.buf_len > 0) {
        const unread = stream.buf_len - stream.buf_pos;
        return @intCast(pos - @as(i64, @intCast(unread)));
    }

    // If we have a write buffer, add pending bytes
    if (stream.flags & F_WRITE != 0 and stream.buf_pos > 0) {
        return @intCast(pos + @as(i64, @intCast(stream.buf_pos)));
    }

    return @intCast(pos);
}

// ---------------------------------------------------------------------------
// printf formatting engine
// ---------------------------------------------------------------------------

/// Internal: write a single byte via a FILE stream, returning the count
/// of bytes written (0 on error, 1 on success).
fn emit_char(stream: *FILE, c: u8) usize {
    if (fputc_impl(@as(c_int, c), stream) == EOF) return 0;
    return 1;
}

/// Internal: write a null-terminated string to a FILE stream.
/// Returns the number of bytes written.
fn emit_string(stream: *FILE, s: [*:0]const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        count += emit_char(stream, s[i]);
    }
    return count;
}

/// Internal: render an unsigned integer into a buffer (right-to-left).
/// Returns the start offset into the buffer.
fn render_unsigned(value: u64, base: u8, uppercase: bool, buf: *[20]u8) usize {
    const digits_lower = "0123456789abcdef";
    const digits_upper = "0123456789ABCDEF";
    const digits: [*]const u8 = if (uppercase) digits_upper else digits_lower;

    var pos: usize = 20;
    var v = value;

    if (v == 0) {
        pos -= 1;
        buf[pos] = '0';
        return pos;
    }

    while (v != 0) {
        pos -= 1;
        buf[pos] = digits[@intCast(v % base)];
        v /= base;
    }

    return pos;
}

/// Core vfprintf engine: format string with va_list.
fn vfprintf_impl(stream: *FILE, fmt: [*:0]const u8, ap: *VaList) callconv(.c) c_int {
    var count: usize = 0;
    var i: usize = 0;

    while (fmt[i] != 0) {
        if (fmt[i] != '%') {
            count += emit_char(stream, fmt[i]);
            i += 1;
            continue;
        }

        i += 1; // skip '%'
        if (fmt[i] == 0) break;

        // Parse flags
        var zero_pad: bool = false;
        if (fmt[i] == '0') {
            zero_pad = true;
            i += 1;
        }

        // Parse width
        var width: usize = 0;
        while (fmt[i] >= '0' and fmt[i] <= '9') {
            width = width * 10 + (fmt[i] - '0');
            i += 1;
        }

        // Parse length modifiers
        var long_count: u8 = 0;
        while (fmt[i] == 'l') {
            long_count += 1;
            i += 1;
        }

        if (fmt[i] == 0) break;

        const spec = fmt[i];
        i += 1;

        switch (spec) {
            '%' => {
                count += emit_char(stream, '%');
            },
            'c' => {
                const ch = @cVaArg(ap, c_int);
                count += emit_char(stream, @truncate(@as(c_uint, @bitCast(ch))));
            },
            's' => {
                const s = @cVaArg(ap, [*:0]const u8);
                count += emit_string(stream, s);
            },
            'd', 'i' => {
                const val: i64 = if (long_count >= 2)
                    @cVaArg(ap, c_longlong)
                else if (long_count == 1)
                    @cVaArg(ap, c_long)
                else
                    @cVaArg(ap, c_int);

                var num_buf: [20]u8 = undefined;
                var is_negative = false;
                var abs_val: u64 = undefined;

                if (val < 0) {
                    is_negative = true;
                    // Handle minimum value edge case
                    if (val == std.math.minInt(i64)) {
                        abs_val = @as(u64, @intCast(std.math.maxInt(i64))) + 1;
                    } else {
                        abs_val = @intCast(-val);
                    }
                } else {
                    abs_val = @intCast(val);
                }

                const start = render_unsigned(abs_val, 10, false, &num_buf);
                const num_len = 20 - start;
                const total_len = num_len + @as(usize, if (is_negative) 1 else 0);

                if (zero_pad and is_negative) {
                    count += emit_char(stream, '-');
                }

                if (width > total_len) {
                    const pad_char: u8 = if (zero_pad) '0' else ' ';
                    var pad = width - total_len;
                    while (pad > 0) : (pad -= 1) {
                        count += emit_char(stream, pad_char);
                    }
                }

                if (!zero_pad and is_negative) {
                    count += emit_char(stream, '-');
                }

                for (num_buf[start..20]) |byte| {
                    count += emit_char(stream, byte);
                }
            },
            'u' => {
                const val: u64 = if (long_count >= 2)
                    @as(u64, @bitCast(@cVaArg(ap, c_ulonglong)))
                else if (long_count == 1)
                    @as(u64, @cVaArg(ap, c_ulong))
                else
                    @as(u64, @bitCast(@as(i64, @cVaArg(ap, c_uint))));

                var num_buf: [20]u8 = undefined;
                const start = render_unsigned(val, 10, false, &num_buf);
                const num_len = 20 - start;

                if (width > num_len) {
                    const pad_char: u8 = if (zero_pad) '0' else ' ';
                    var pad = width - num_len;
                    while (pad > 0) : (pad -= 1) {
                        count += emit_char(stream, pad_char);
                    }
                }

                for (num_buf[start..20]) |byte| {
                    count += emit_char(stream, byte);
                }
            },
            'x', 'X' => {
                const val: u64 = if (long_count >= 2)
                    @as(u64, @bitCast(@cVaArg(ap, c_ulonglong)))
                else if (long_count == 1)
                    @as(u64, @cVaArg(ap, c_ulong))
                else
                    @as(u64, @bitCast(@as(i64, @cVaArg(ap, c_uint))));

                const uppercase = (spec == 'X');
                var num_buf: [20]u8 = undefined;
                const start = render_unsigned(val, 16, uppercase, &num_buf);
                const num_len = 20 - start;

                if (width > num_len) {
                    const pad_char: u8 = if (zero_pad) '0' else ' ';
                    var pad = width - num_len;
                    while (pad > 0) : (pad -= 1) {
                        count += emit_char(stream, pad_char);
                    }
                }

                for (num_buf[start..20]) |byte| {
                    count += emit_char(stream, byte);
                }
            },
            'p' => {
                const val = @cVaArg(ap, usize);
                count += emit_char(stream, '0');
                count += emit_char(stream, 'x');

                var num_buf: [20]u8 = undefined;
                const start = render_unsigned(@as(u64, val), 16, false, &num_buf);

                for (num_buf[start..20]) |byte| {
                    count += emit_char(stream, byte);
                }
            },
            else => {
                // Unknown specifier: emit as-is
                count += emit_char(stream, '%');
                count += emit_char(stream, spec);
            },
        }
    }

    return @intCast(count);
}

pub export fn vfprintf(stream: *FILE, fmt: [*:0]const u8, ap: *VaList) c_int {
    if (comptime !has_c_va_list) return -1;
    return vfprintf_impl(stream, fmt, ap);
}

pub export fn fprintf(stream: *FILE, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    if (comptime !has_c_va_list) return -1;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_impl(stream, fmt, &ap);
}

pub export fn printf(fmt: [*:0]const u8, ...) callconv(.c) c_int {
    if (comptime !has_c_va_list) return -1;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf_impl(&stdout_file, fmt, &ap);
}

/// vsnprintf engine: formats into a fixed buffer.
fn vsnprintf_impl(buf: [*]u8, size: usize, fmt: [*:0]const u8, ap: *VaList) callconv(.c) c_int {
    // We build a "fake" FILE that writes into the user buffer.
    // To keep it simple and avoid modifying FILE, we do character-by-character
    // formatting with a closure-like approach using a position counter.
    var pos: usize = 0;
    var total: usize = 0; // total characters that would be written
    var i: usize = 0;

    const Writer = struct {
        fn put(p: *usize, t: *usize, b: [*]u8, s: usize, c: u8) void {
            t.* += 1;
            if (p.* + 1 < s) { // leave room for null terminator
                b[p.*] = c;
                p.* += 1;
            }
        }

        fn put_str(p: *usize, t: *usize, b: [*]u8, s_size: usize, str: [*:0]const u8) void {
            var idx: usize = 0;
            while (str[idx] != 0) : (idx += 1) {
                put(p, t, b, s_size, str[idx]);
            }
        }

        fn put_unsigned(p: *usize, t: *usize, b: [*]u8, s_size: usize, value: u64, base: u8, uppercase: bool, width: usize, zero_pad: bool) void {
            var num_buf: [20]u8 = undefined;
            const start = render_unsigned(value, base, uppercase, &num_buf);
            const num_len = 20 - start;

            if (width > num_len) {
                const pad_char: u8 = if (zero_pad) '0' else ' ';
                var pad = width - num_len;
                while (pad > 0) : (pad -= 1) {
                    put(p, t, b, s_size, pad_char);
                }
            }

            for (num_buf[start..20]) |byte| {
                put(p, t, b, s_size, byte);
            }
        }
    };

    while (fmt[i] != 0) {
        if (fmt[i] != '%') {
            Writer.put(&pos, &total, buf, size, fmt[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (fmt[i] == 0) break;

        var zero_pad: bool = false;
        if (fmt[i] == '0') {
            zero_pad = true;
            i += 1;
        }

        var width: usize = 0;
        while (fmt[i] >= '0' and fmt[i] <= '9') {
            width = width * 10 + (fmt[i] - '0');
            i += 1;
        }

        var long_count: u8 = 0;
        while (fmt[i] == 'l') {
            long_count += 1;
            i += 1;
        }

        if (fmt[i] == 0) break;

        const spec = fmt[i];
        i += 1;

        switch (spec) {
            '%' => Writer.put(&pos, &total, buf, size, '%'),
            'c' => {
                const ch = @cVaArg(ap, c_int);
                Writer.put(&pos, &total, buf, size, @truncate(@as(c_uint, @bitCast(ch))));
            },
            's' => {
                const s = @cVaArg(ap, [*:0]const u8);
                Writer.put_str(&pos, &total, buf, size, s);
            },
            'd', 'i' => {
                const val: i64 = if (long_count >= 2)
                    @cVaArg(ap, c_longlong)
                else if (long_count == 1)
                    @cVaArg(ap, c_long)
                else
                    @cVaArg(ap, c_int);

                var is_negative = false;
                var abs_val: u64 = undefined;
                if (val < 0) {
                    is_negative = true;
                    if (val == std.math.minInt(i64)) {
                        abs_val = @as(u64, @intCast(std.math.maxInt(i64))) + 1;
                    } else {
                        abs_val = @intCast(-val);
                    }
                } else {
                    abs_val = @intCast(val);
                }

                const num_len = blk: {
                    var tmp_buf: [20]u8 = undefined;
                    const s = render_unsigned(abs_val, 10, false, &tmp_buf);
                    break :blk 20 - s;
                };
                const total_len = num_len + @as(usize, if (is_negative) 1 else 0);

                if (zero_pad and is_negative) {
                    Writer.put(&pos, &total, buf, size, '-');
                }
                if (width > total_len) {
                    const pad_char: u8 = if (zero_pad) '0' else ' ';
                    var pad = width - total_len;
                    while (pad > 0) : (pad -= 1) {
                        Writer.put(&pos, &total, buf, size, pad_char);
                    }
                }
                if (!zero_pad and is_negative) {
                    Writer.put(&pos, &total, buf, size, '-');
                }

                var num_buf: [20]u8 = undefined;
                const start = render_unsigned(abs_val, 10, false, &num_buf);
                for (num_buf[start..20]) |byte| {
                    Writer.put(&pos, &total, buf, size, byte);
                }
            },
            'u' => {
                const val: u64 = if (long_count >= 2)
                    @as(u64, @bitCast(@cVaArg(ap, c_ulonglong)))
                else if (long_count == 1)
                    @as(u64, @cVaArg(ap, c_ulong))
                else
                    @as(u64, @bitCast(@as(i64, @cVaArg(ap, c_uint))));

                Writer.put_unsigned(&pos, &total, buf, size, val, 10, false, width, zero_pad);
            },
            'x', 'X' => {
                const val: u64 = if (long_count >= 2)
                    @as(u64, @bitCast(@cVaArg(ap, c_ulonglong)))
                else if (long_count == 1)
                    @as(u64, @cVaArg(ap, c_ulong))
                else
                    @as(u64, @bitCast(@as(i64, @cVaArg(ap, c_uint))));

                Writer.put_unsigned(&pos, &total, buf, size, val, 16, spec == 'X', width, zero_pad);
            },
            'p' => {
                const val = @cVaArg(ap, usize);
                Writer.put(&pos, &total, buf, size, '0');
                Writer.put(&pos, &total, buf, size, 'x');
                Writer.put_unsigned(&pos, &total, buf, size, @as(u64, val), 16, false, 0, false);
            },
            else => {
                Writer.put(&pos, &total, buf, size, '%');
                Writer.put(&pos, &total, buf, size, spec);
            },
        }
    }

    // Null-terminate
    if (size > 0) {
        buf[pos] = 0;
    }

    return @intCast(total);
}

pub export fn vsnprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ap: *VaList) c_int {
    if (comptime !has_c_va_list) return -1;
    return vsnprintf_impl(buf, size, fmt, ap);
}

pub export fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    if (comptime !has_c_va_list) return -1;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsnprintf_impl(buf, size, fmt, &ap);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "FILE struct default initialization" {
    var f = FILE{ .fd = 42, .flags = F_WRITE };
    try testing.expectEqual(@as(c_int, 42), f.fd);
    try testing.expectEqual(@as(usize, 0), f.buf_pos);
    try testing.expectEqual(@as(usize, 0), f.buf_len);
    try testing.expectEqual(@as(usize, BUFSIZ), f.buf_size);
    try testing.expectEqual(false, f.error_flag);
    try testing.expectEqual(false, f.eof_flag);
    _ = &f;
}

test "standard streams initialized correctly" {
    try testing.expectEqual(@as(c_int, 0), stdin_file.fd);
    try testing.expectEqual(F_READ, stdin_file.flags);

    try testing.expectEqual(@as(c_int, 1), stdout_file.fd);
    try testing.expectEqual(F_WRITE | F_LINEBUF, stdout_file.flags);

    try testing.expectEqual(@as(c_int, 2), stderr_file.fd);
    try testing.expectEqual(F_WRITE | F_UNBUF, stderr_file.flags);
}

test "fputc buffers data in write stream" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    // fputc should buffer without flushing (buffer is large)
    const ret = fputc_impl('A', &f);
    try testing.expectEqual(@as(c_int, 'A'), ret);
    try testing.expectEqual(@as(usize, 1), f.buf_pos);
    try testing.expectEqual(@as(u8, 'A'), f.buf[0]);
}

test "fputc multiple bytes accumulate in buffer" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    _ = fputc_impl('H', &f);
    _ = fputc_impl('i', &f);
    _ = fputc_impl('!', &f);
    try testing.expectEqual(@as(usize, 3), f.buf_pos);
    try testing.expectEqual(@as(u8, 'H'), f.buf[0]);
    try testing.expectEqual(@as(u8, 'i'), f.buf[1]);
    try testing.expectEqual(@as(u8, '!'), f.buf[2]);
}

test "fputc unbuffered writes immediately (test stub consumes)" {
    var f = FILE{ .fd = 99, .flags = F_WRITE | F_UNBUF };
    const ret = fputc_impl('Z', &f);
    try testing.expectEqual(@as(c_int, 'Z'), ret);
    // Unbuffered: buf_pos stays 0 (written directly)
    try testing.expectEqual(@as(usize, 0), f.buf_pos);
}

test "fputc line-buffered flushes on newline" {
    var f = FILE{ .fd = 99, .flags = F_WRITE | F_LINEBUF };
    _ = fputc_impl('A', &f);
    try testing.expectEqual(@as(usize, 1), f.buf_pos);

    // Newline should trigger flush (test stub succeeds)
    _ = fputc_impl('\n', &f);
    try testing.expectEqual(@as(usize, 0), f.buf_pos); // flushed
}

test "fputs writes string to buffer" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    const ret = fputs("hello", &f);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(usize, 5), f.buf_pos);
    try testing.expectEqualSlices(u8, "hello", f.buf[0..5]);
}

test "puts writes to stdout with newline" {
    // Reset stdout for test
    stdout_file.buf_pos = 0;
    stdout_file.error_flag = false;
    stdout_file.eof_flag = false;

    const ret = puts("test");
    try testing.expectEqual(@as(c_int, 0), ret);
    // In test mode with line buffering: "test\n" is written,
    // newline triggers flush, so buf_pos should be 0 after flush.
    try testing.expectEqual(@as(usize, 0), stdout_file.buf_pos);
}

test "putchar writes single char to stdout" {
    stdout_file.buf_pos = 0;
    stdout_file.error_flag = false;

    const ret = putchar('X');
    try testing.expectEqual(@as(c_int, 'X'), ret);
}

test "fgetc returns EOF on empty read stream (test stub)" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    // Test stub returns 0 bytes (EOF)
    const ret = fgetc_impl(&f);
    try testing.expectEqual(EOF, ret);
    try testing.expect(f.eof_flag);
}

test "fgetc reads from buffer" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    // Manually fill buffer to simulate data
    f.buf[0] = 'A';
    f.buf[1] = 'B';
    f.buf[2] = 'C';
    f.buf_len = 3;
    f.buf_pos = 0;

    try testing.expectEqual(@as(c_int, 'A'), fgetc_impl(&f));
    try testing.expectEqual(@as(c_int, 'B'), fgetc_impl(&f));
    try testing.expectEqual(@as(c_int, 'C'), fgetc_impl(&f));
    // Next read: buffer exhausted, test stub returns EOF
    try testing.expectEqual(EOF, fgetc_impl(&f));
}

test "fwrite writes bytes to buffer" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    const data = "Hello, World!";
    const ret = fwrite(data.ptr, 1, 13, &f);
    try testing.expectEqual(@as(usize, 13), ret);
    try testing.expectEqual(@as(usize, 13), f.buf_pos);
    try testing.expectEqualSlices(u8, "Hello, World!", f.buf[0..13]);
}

test "fwrite with size > 1" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    const data = [_]u8{ 1, 2, 3, 4, 5, 6 };
    // 3 elements of size 2
    const ret = fwrite(&data, 2, 3, &f);
    try testing.expectEqual(@as(usize, 3), ret);
    try testing.expectEqual(@as(usize, 6), f.buf_pos);
}

test "fwrite zero size returns zero" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    const data = "test";
    try testing.expectEqual(@as(usize, 0), fwrite(data.ptr, 0, 4, &f));
    try testing.expectEqual(@as(usize, 0), fwrite(data.ptr, 1, 0, &f));
}

test "fread reads from pre-filled buffer" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    f.buf[0] = 'X';
    f.buf[1] = 'Y';
    f.buf[2] = 'Z';
    f.buf_len = 3;
    f.buf_pos = 0;

    var out: [3]u8 = undefined;
    const ret = fread(&out, 1, 3, &f);
    try testing.expectEqual(@as(usize, 3), ret);
    try testing.expectEqualSlices(u8, "XYZ", &out);
}

test "fread partial read returns partial count" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    f.buf[0] = 'A';
    f.buf_len = 1;
    f.buf_pos = 0;

    var out: [4]u8 = undefined;
    // Only 1 byte available, test stub returns EOF after that
    const ret = fread(&out, 1, 4, &f);
    try testing.expectEqual(@as(usize, 1), ret);
    try testing.expectEqual(@as(u8, 'A'), out[0]);
}

test "ferror returns error state" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    try testing.expectEqual(@as(c_int, 0), ferror(&f));
    f.error_flag = true;
    try testing.expectEqual(@as(c_int, 1), ferror(&f));
}

test "feof returns eof state" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    try testing.expectEqual(@as(c_int, 0), feof(&f));
    f.eof_flag = true;
    try testing.expectEqual(@as(c_int, 1), feof(&f));
}

test "clearerr clears both flags" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    f.error_flag = true;
    f.eof_flag = true;
    clearerr(&f);
    try testing.expectEqual(@as(c_int, 0), ferror(&f));
    try testing.expectEqual(@as(c_int, 0), feof(&f));
}

test "fflush on empty buffer is no-op" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    try testing.expectEqual(@as(c_int, 0), fflush(&f));
    try testing.expectEqual(@as(usize, 0), f.buf_pos);
}

test "fflush writes buffer contents (test stub)" {
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    _ = fputc_impl('A', &f);
    _ = fputc_impl('B', &f);
    try testing.expectEqual(@as(usize, 2), f.buf_pos);

    const ret = fflush(&f);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(usize, 0), f.buf_pos); // buffer flushed
}

test "fflush null flushes all standard streams" {
    stdout_file.buf_pos = 0;
    stdout_file.error_flag = false;
    stderr_file.buf_pos = 0;
    stderr_file.error_flag = false;

    // Put data into stdout buffer
    _ = fputc_impl('X', &stdout_file);
    try testing.expectEqual(@as(usize, 1), stdout_file.buf_pos);

    const ret = fflush(null);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(usize, 0), stdout_file.buf_pos);
}

test "fputc buffer full triggers flush" {
    // Create a FILE with a tiny buffer size to test flush-on-full
    var f = FILE{ .fd = 99, .flags = F_WRITE };
    f.buf_size = 4; // only 4 bytes

    _ = fputc_impl('A', &f);
    _ = fputc_impl('B', &f);
    _ = fputc_impl('C', &f);
    try testing.expectEqual(@as(usize, 3), f.buf_pos);

    // 4th byte fills buffer, triggers flush (test stub succeeds)
    _ = fputc_impl('D', &f);
    try testing.expectEqual(@as(usize, 0), f.buf_pos); // flushed
}

test "render_unsigned decimal" {
    var buf: [20]u8 = undefined;
    const start = render_unsigned(12345, 10, false, &buf);
    const result = buf[start..20];
    try testing.expectEqualSlices(u8, "12345", result);
}

test "render_unsigned hex lowercase" {
    var buf: [20]u8 = undefined;
    const start = render_unsigned(0xDEAD, 16, false, &buf);
    const result = buf[start..20];
    try testing.expectEqualSlices(u8, "dead", result);
}

test "render_unsigned hex uppercase" {
    var buf: [20]u8 = undefined;
    const start = render_unsigned(0xBEEF, 16, true, &buf);
    const result = buf[start..20];
    try testing.expectEqualSlices(u8, "BEEF", result);
}

test "render_unsigned zero" {
    var buf: [20]u8 = undefined;
    const start = render_unsigned(0, 10, false, &buf);
    const result = buf[start..20];
    try testing.expectEqualSlices(u8, "0", result);
}

// ---------------------------------------------------------------------------
// fopen / fclose / fseek / ftell tests
// ---------------------------------------------------------------------------

test "parse_mode r" {
    const m = parse_mode("r") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDONLY, m.oflags);
    try testing.expectEqual(F_READ, m.fflags);
}

test "parse_mode w" {
    const m = parse_mode("w") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_WRONLY | fcntl_mod.O_CREAT | fcntl_mod.O_TRUNC, m.oflags);
    try testing.expectEqual(F_WRITE, m.fflags);
}

test "parse_mode a" {
    const m = parse_mode("a") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_WRONLY | fcntl_mod.O_CREAT | fcntl_mod.O_APPEND, m.oflags);
    try testing.expectEqual(F_WRITE | F_APPEND, m.fflags);
}

test "parse_mode r+" {
    const m = parse_mode("r+") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDWR, m.oflags);
    try testing.expectEqual(F_READ | F_WRITE, m.fflags);
}

test "parse_mode w+" {
    const m = parse_mode("w+") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDWR | fcntl_mod.O_CREAT | fcntl_mod.O_TRUNC, m.oflags);
    try testing.expectEqual(F_READ | F_WRITE, m.fflags);
}

test "parse_mode a+" {
    const m = parse_mode("a+") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDWR | fcntl_mod.O_CREAT | fcntl_mod.O_APPEND, m.oflags);
    try testing.expectEqual(F_READ | F_WRITE | F_APPEND, m.fflags);
}

test "parse_mode rb" {
    // Binary mode should be accepted (treated same as text)
    const m = parse_mode("rb") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDONLY, m.oflags);
    try testing.expectEqual(F_READ, m.fflags);
}

test "parse_mode wb+" {
    const m = parse_mode("wb+") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(fcntl_mod.O_RDWR | fcntl_mod.O_CREAT | fcntl_mod.O_TRUNC, m.oflags);
    try testing.expectEqual(F_READ | F_WRITE, m.fflags);
}

test "parse_mode invalid empty" {
    try testing.expect(parse_mode("") == null);
}

test "parse_mode invalid char" {
    try testing.expect(parse_mode("z") == null);
}

test "fopen allocates and initializes FILE" {
    malloc_mod.resetState();
    const f = fopen("test.txt", "r") orelse return error.TestUnexpectedResult;
    // Verify the FILE was properly initialized
    try testing.expectEqual(@as(c_int, 3), f.fd); // test stub returns fd 3
    try testing.expectEqual(F_READ, f.flags);
    try testing.expectEqual(@as(usize, 0), f.buf_pos);
    try testing.expectEqual(@as(usize, 0), f.buf_len);
    try testing.expectEqual(false, f.error_flag);
    try testing.expectEqual(false, f.eof_flag);

    // Clean up
    const ret = fclose(f);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "fopen invalid mode returns null" {
    malloc_mod.resetState();
    const f = fopen("test.txt", "z");
    try testing.expect(f == null);
}

test "fopen write mode sets correct flags" {
    malloc_mod.resetState();
    const f = fopen("test.txt", "w") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(F_WRITE, f.flags);
    _ = fclose(f);
}

test "fopen append mode sets correct flags" {
    malloc_mod.resetState();
    const f = fopen("test.txt", "a") orelse return error.TestUnexpectedResult;
    try testing.expectEqual(F_WRITE | F_APPEND, f.flags);
    _ = fclose(f);
}

test "fclose flushes and frees" {
    malloc_mod.resetState();
    const f = fopen("test.txt", "w") orelse return error.TestUnexpectedResult;
    // Write some data to the buffer
    _ = fputc_impl('X', f);
    try testing.expectEqual(@as(usize, 1), f.buf_pos);
    // fclose should flush and free
    const ret = fclose(f);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "fseek clears eof flag" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    f.eof_flag = true;
    const ret = fseek(&f, 0, SEEK_SET);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(false, f.eof_flag);
}

test "fseek resets read buffer" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    f.buf_len = 100;
    f.buf_pos = 50;
    const ret = fseek(&f, 0, SEEK_SET);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(usize, 0), f.buf_pos);
    try testing.expectEqual(@as(usize, 0), f.buf_len);
}

test "ftell returns position" {
    var f = FILE{ .fd = 99, .flags = F_READ };
    const pos = ftell(&f);
    try testing.expectEqual(@as(c_long, 0), pos);
}
