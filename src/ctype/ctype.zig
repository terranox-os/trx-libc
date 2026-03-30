//! POSIX <ctype.h> function implementations.
//!
//! Character classification and conversion using a comptime-generated
//! 256-byte lookup table. Exported with C ABI.

const UPPER: u8 = 0x01;
const LOWER: u8 = 0x02;
const DIGIT: u8 = 0x04;
const SPACE: u8 = 0x08;
const PRINT: u8 = 0x10;
const CNTRL: u8 = 0x20;
const XDIGIT: u8 = 0x40;
const PUNCT: u8 = 0x80;

const table: [256]u8 = blk: {
    var t: [256]u8 = [_]u8{0} ** 256;

    // Control characters: 0x00-0x1F and 0x7F
    for (0..32) |i| {
        t[i] = CNTRL;
    }
    t[0x7F] = CNTRL;

    // Space characters: space, \t, \n, \v, \f, \r
    t[' '] |= SPACE | PRINT;
    t['\t'] |= SPACE;
    t['\n'] |= SPACE;
    t[0x0B] |= SPACE; // \v
    t[0x0C] |= SPACE; // \f
    t['\r'] |= SPACE;

    // Digits 0-9
    for ('0'..'9' + 1) |i| {
        t[i] = DIGIT | XDIGIT | PRINT;
    }

    // Uppercase A-Z
    for ('A'..'Z' + 1) |i| {
        t[i] = UPPER | PRINT;
    }

    // Lowercase a-z
    for ('a'..'z' + 1) |i| {
        t[i] = LOWER | PRINT;
    }

    // Hex digits: A-F, a-f (add XDIGIT flag)
    for ('A'..'F' + 1) |i| {
        t[i] |= XDIGIT;
    }
    for ('a'..'f' + 1) |i| {
        t[i] |= XDIGIT;
    }

    // Punctuation: printable non-alphanumeric non-space
    // ASCII 0x21-0x2F, 0x3A-0x40, 0x5B-0x60, 0x7B-0x7E
    for (0x21..0x30) |i| {
        if (t[i] & (UPPER | LOWER | DIGIT) == 0) {
            t[i] = PUNCT | PRINT;
        }
    }
    for (0x3A..0x41) |i| {
        if (t[i] & (UPPER | LOWER | DIGIT) == 0) {
            t[i] = PUNCT | PRINT;
        }
    }
    for (0x5B..0x61) |i| {
        if (t[i] & (UPPER | LOWER | DIGIT) == 0) {
            t[i] = PUNCT | PRINT;
        }
    }
    for (0x7B..0x7F) |i| {
        if (t[i] & (UPPER | LOWER | DIGIT) == 0) {
            t[i] = PUNCT | PRINT;
        }
    }

    break :blk t;
};

// ---------------------------------------------------------------------------
// Classification functions
// ---------------------------------------------------------------------------

fn classify(c: c_int, flag: u8) c_int {
    if (c < 0 or c > 255) return 0;
    return if (table[@intCast(@as(c_uint, @bitCast(c)))] & flag != 0) @as(c_int, 1) else @as(c_int, 0);
}

export fn isalpha(c: c_int) c_int {
    return classify(c, UPPER | LOWER);
}

export fn isupper(c: c_int) c_int {
    return classify(c, UPPER);
}

export fn islower(c: c_int) c_int {
    return classify(c, LOWER);
}

export fn isdigit(c: c_int) c_int {
    return classify(c, DIGIT);
}

export fn isxdigit(c: c_int) c_int {
    return classify(c, XDIGIT);
}

export fn isalnum(c: c_int) c_int {
    return classify(c, UPPER | LOWER | DIGIT);
}

export fn isspace(c: c_int) c_int {
    return classify(c, SPACE);
}

export fn isprint(c: c_int) c_int {
    return classify(c, PRINT);
}

export fn iscntrl(c: c_int) c_int {
    return classify(c, CNTRL);
}

export fn ispunct(c: c_int) c_int {
    return classify(c, PUNCT);
}

// ---------------------------------------------------------------------------
// Conversion functions
// ---------------------------------------------------------------------------

export fn toupper(c: c_int) c_int {
    if (islower(c) != 0) return c - 32;
    return c;
}

export fn tolower(c: c_int) c_int {
    if (isupper(c) != 0) return c + 32;
    return c;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "isalpha" {
    try testing.expect(isalpha('A') != 0);
    try testing.expect(isalpha('z') != 0);
    try testing.expect(isalpha('0') == 0);
    try testing.expect(isalpha(' ') == 0);
    try testing.expect(isalpha(-1) == 0);
}

test "isupper" {
    try testing.expect(isupper('A') != 0);
    try testing.expect(isupper('Z') != 0);
    try testing.expect(isupper('a') == 0);
    try testing.expect(isupper('1') == 0);
}

test "islower" {
    try testing.expect(islower('a') != 0);
    try testing.expect(islower('z') != 0);
    try testing.expect(islower('A') == 0);
}

test "isdigit" {
    try testing.expect(isdigit('0') != 0);
    try testing.expect(isdigit('9') != 0);
    try testing.expect(isdigit('a') == 0);
    try testing.expect(isdigit(' ') == 0);
}

test "isxdigit" {
    try testing.expect(isxdigit('0') != 0);
    try testing.expect(isxdigit('9') != 0);
    try testing.expect(isxdigit('a') != 0);
    try testing.expect(isxdigit('f') != 0);
    try testing.expect(isxdigit('A') != 0);
    try testing.expect(isxdigit('F') != 0);
    try testing.expect(isxdigit('g') == 0);
    try testing.expect(isxdigit('G') == 0);
}

test "isalnum" {
    try testing.expect(isalnum('a') != 0);
    try testing.expect(isalnum('Z') != 0);
    try testing.expect(isalnum('5') != 0);
    try testing.expect(isalnum('!') == 0);
    try testing.expect(isalnum(' ') == 0);
}

test "isspace" {
    try testing.expect(isspace(' ') != 0);
    try testing.expect(isspace('\t') != 0);
    try testing.expect(isspace('\n') != 0);
    try testing.expect(isspace('\r') != 0);
    try testing.expect(isspace('a') == 0);
}

test "isprint" {
    try testing.expect(isprint(' ') != 0);
    try testing.expect(isprint('~') != 0);
    try testing.expect(isprint('A') != 0);
    try testing.expect(isprint(0) == 0); // NUL
    try testing.expect(isprint(0x7F) == 0); // DEL
}

test "iscntrl" {
    try testing.expect(iscntrl(0) != 0);
    try testing.expect(iscntrl(0x1F) != 0);
    try testing.expect(iscntrl(0x7F) != 0);
    try testing.expect(iscntrl(' ') == 0);
    try testing.expect(iscntrl('A') == 0);
}

test "ispunct" {
    try testing.expect(ispunct('!') != 0);
    try testing.expect(ispunct('.') != 0);
    try testing.expect(ispunct('@') != 0);
    try testing.expect(ispunct('[') != 0);
    try testing.expect(ispunct('{') != 0);
    try testing.expect(ispunct('~') != 0);
    try testing.expect(ispunct('A') == 0);
    try testing.expect(ispunct('0') == 0);
    try testing.expect(ispunct(' ') == 0);
}

test "toupper" {
    try testing.expectEqual(@as(c_int, 'A'), toupper('a'));
    try testing.expectEqual(@as(c_int, 'Z'), toupper('z'));
    try testing.expectEqual(@as(c_int, 'A'), toupper('A'));
    try testing.expectEqual(@as(c_int, '1'), toupper('1'));
}

test "tolower" {
    try testing.expectEqual(@as(c_int, 'a'), tolower('A'));
    try testing.expectEqual(@as(c_int, 'z'), tolower('Z'));
    try testing.expectEqual(@as(c_int, 'a'), tolower('a'));
    try testing.expectEqual(@as(c_int, '1'), tolower('1'));
}

test "out of range" {
    try testing.expect(isalpha(-1) == 0);
    try testing.expect(isalpha(256) == 0);
    try testing.expect(isdigit(300) == 0);
}
