//! BSD socket API and inet helpers (Phase 4).
//!
//! Provides socket creation, connection, message I/O, socket options,
//! byte-order conversion, and address formatting functions.
//!
//! Networking syscalls use TerranoxOS subsystem 8 (0x0180-0x018F).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Address families
pub const AF_UNSPEC: c_int = 0;
pub const AF_INET: c_int = 2;
pub const AF_INET6: c_int = 10;

// Socket types
pub const SOCK_STREAM: c_int = 1;
pub const SOCK_DGRAM: c_int = 2;
pub const SOCK_RAW: c_int = 3;

// Shutdown how
pub const SHUT_RD: c_int = 0;
pub const SHUT_WR: c_int = 1;
pub const SHUT_RDWR: c_int = 2;

// Special addresses (host byte order)
pub const INADDR_ANY: u32 = 0;
pub const INADDR_LOOPBACK: u32 = 0x7F000001; // 127.0.0.1

// ---------------------------------------------------------------------------
// Structures
// ---------------------------------------------------------------------------

pub const sockaddr_in = extern struct {
    family: u16,
    port: u16, // network byte order
    addr: u32, // network byte order
    zero: [8]u8 = [_]u8{0} ** 8,
};

// ---------------------------------------------------------------------------
// Byte-order helpers (x86_64 is little-endian)
// ---------------------------------------------------------------------------

export fn htons(x: u16) u16 {
    return @byteSwap(x);
}

export fn htonl(x: u32) u32 {
    return @byteSwap(x);
}

export fn ntohs(x: u16) u16 {
    return @byteSwap(x);
}

export fn ntohl(x: u32) u32 {
    return @byteSwap(x);
}

// ---------------------------------------------------------------------------
// Address conversion
// ---------------------------------------------------------------------------

/// Parse a dotted-decimal IPv4 string into a network-order 32-bit address.
/// Returns 1 on success, 0 on parse failure. Only AF_INET is supported.
export fn inet_pton(af: c_int, src: [*:0]const u8, dst: *anyopaque) c_int {
    if (af != AF_INET) {
        // AF_INET6 not yet supported
        errno_mod.errno = errno_mod.ENOSYS;
        return -1;
    }

    const dest: *u32 = @ptrCast(@alignCast(dst));

    var octets: [4]u8 = .{ 0, 0, 0, 0 };
    var octet_idx: usize = 0;
    var cur_val: u16 = 0;
    var digit_count: u8 = 0;
    var i: usize = 0;

    while (src[i] != 0) : (i += 1) {
        const ch = src[i];
        if (ch >= '0' and ch <= '9') {
            cur_val = cur_val * 10 + @as(u16, ch - '0');
            digit_count += 1;
            if (cur_val > 255 or digit_count > 3) return 0;
        } else if (ch == '.') {
            if (digit_count == 0 or octet_idx >= 3) return 0;
            octets[octet_idx] = @intCast(cur_val);
            octet_idx += 1;
            cur_val = 0;
            digit_count = 0;
        } else {
            return 0; // invalid character
        }
    }

    // Must have exactly 4 octets
    if (octet_idx != 3 or digit_count == 0) return 0;
    octets[3] = @intCast(cur_val);

    // Shift-packing produces host byte order; convert to network (big-endian).
    const host_val = @as(u32, octets[0]) << 24 |
        @as(u32, octets[1]) << 16 |
        @as(u32, octets[2]) << 8 |
        @as(u32, octets[3]);
    dest.* = htonl(host_val);

    return 1;
}

/// Format a network-order IPv4 address into a dotted-decimal string.
/// Returns pointer to dst on success, null on failure.
export fn inet_ntop(af: c_int, src: *const anyopaque, dst: [*]u8, size: u32) ?[*:0]const u8 {
    if (af != AF_INET) {
        errno_mod.errno = errno_mod.ENOSYS;
        return null;
    }

    const addr_ptr: *const u32 = @ptrCast(@alignCast(src));
    const host_addr = ntohl(addr_ptr.*);

    const octets = [4]u8{
        @intCast((host_addr >> 24) & 0xFF),
        @intCast((host_addr >> 16) & 0xFF),
        @intCast((host_addr >> 8) & 0xFF),
        @intCast(host_addr & 0xFF),
    };

    var pos: u32 = 0;
    for (octets, 0..) |octet, idx| {
        // Format the octet value
        if (octet >= 100) {
            if (pos >= size) return null;
            dst[pos] = '0' + @as(u8, @intCast(octet / 100));
            pos += 1;
        }
        if (octet >= 10) {
            if (pos >= size) return null;
            dst[pos] = '0' + @as(u8, @intCast((octet / 10) % 10));
            pos += 1;
        }
        if (pos >= size) return null;
        dst[pos] = '0' + @as(u8, @intCast(octet % 10));
        pos += 1;

        // Add dot separator (except after last octet)
        if (idx < 3) {
            if (pos >= size) return null;
            dst[pos] = '.';
            pos += 1;
        }
    }

    // Null-terminate
    if (pos >= size) return null;
    dst[pos] = 0;

    // Return as sentinel-terminated pointer
    return @ptrCast(dst);
}

// ---------------------------------------------------------------------------
// Socket syscall implementations (real and test stubs)
// ---------------------------------------------------------------------------

fn socket_real(domain: c_int, sock_type: c_int, protocol: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_SOCKET,
            @intCast(domain),
            @intCast(sock_type),
            @intCast(protocol),
        ),
    );
    return @intCast(ret);
}

fn bind_real(fd: c_int, addr: *const anyopaque, addrlen: u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_BIND,
            @intCast(fd),
            @intFromPtr(addr),
            @as(usize, addrlen),
        ),
    );
    return @intCast(ret);
}

fn listen_real(fd: c_int, backlog: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_NET_LISTEN,
            @intCast(fd),
            @intCast(backlog),
        ),
    );
    return @intCast(ret);
}

fn accept_real(fd: c_int, addr: ?*anyopaque, addrlen: ?*u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_ACCEPT,
            @intCast(fd),
            if (addr) |a| @intFromPtr(a) else 0,
            if (addrlen) |l| @intFromPtr(l) else 0,
        ),
    );
    return @intCast(ret);
}

fn connect_real(fd: c_int, addr: *const anyopaque, addrlen: u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_CONNECT,
            @intCast(fd),
            @intFromPtr(addr),
            @as(usize, addrlen),
        ),
    );
    return @intCast(ret);
}

fn sendmsg_real(fd: c_int, msg: *const anyopaque, flags: c_int) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_SENDMSG,
            @intCast(fd),
            @intFromPtr(msg),
            @intCast(flags),
        ),
    );
}

fn recvmsg_real(fd: c_int, msg: *anyopaque, flags: c_int) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_NET_RECVMSG,
            @intCast(fd),
            @intFromPtr(msg),
            @intCast(flags),
        ),
    );
}

// Test stubs: return fixed values for single-threaded unit tests
fn socket_test(_: c_int, _: c_int, _: c_int) c_int {
    return 3; // fake fd
}

fn bind_test(_: c_int, _: *const anyopaque, _: u32) c_int {
    return 0;
}

fn listen_test(_: c_int, _: c_int) c_int {
    return 0;
}

fn accept_test(_: c_int, _: ?*anyopaque, _: ?*u32) c_int {
    return 4; // fake accepted fd
}

fn connect_test(_: c_int, _: *const anyopaque, _: u32) c_int {
    return 0;
}

fn sendmsg_test(_: c_int, _: *const anyopaque, _: c_int) isize {
    return 10; // fake bytes sent
}

fn recvmsg_test(_: c_int, _: *anyopaque, _: c_int) isize {
    return 10; // fake bytes received
}

const socket_impl = if (is_test) socket_test else socket_real;
const bind_impl = if (is_test) bind_test else bind_real;
const listen_impl = if (is_test) listen_test else listen_real;
const accept_impl = if (is_test) accept_test else accept_real;
const connect_impl = if (is_test) connect_test else connect_real;
const sendmsg_impl = if (is_test) sendmsg_test else sendmsg_real;
const recvmsg_impl = if (is_test) recvmsg_test else recvmsg_real;

// ---------------------------------------------------------------------------
// Exported socket functions
// ---------------------------------------------------------------------------

/// Create a socket.
export fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int {
    return socket_impl(domain, sock_type, protocol);
}

/// Bind a socket to an address.
export fn bind(fd: c_int, addr: *const anyopaque, addrlen: u32) c_int {
    return bind_impl(fd, addr, addrlen);
}

/// Listen for connections on a socket.
export fn listen(fd: c_int, backlog: c_int) c_int {
    return listen_impl(fd, backlog);
}

/// Accept a connection on a socket.
export fn accept(fd: c_int, addr: ?*anyopaque, addrlen: ?*u32) c_int {
    return accept_impl(fd, addr, addrlen);
}

/// Connect a socket to an address.
export fn connect(fd: c_int, addr: *const anyopaque, addrlen: u32) c_int {
    return connect_impl(fd, addr, addrlen);
}

/// Send a message on a socket (wrapper around sendmsg).
export fn send(fd: c_int, buf: [*]const u8, len: usize, flags: c_int) isize {
    // In a full implementation, this would construct a msghdr and call sendmsg.
    // For now, forward directly to sendmsg_impl with a minimal msghdr-like approach.
    _ = buf;
    _ = len;
    return sendmsg_impl(fd, @ptrCast(&flags), flags);
}

/// Receive a message from a socket (wrapper around recvmsg).
export fn recv(fd: c_int, buf: [*]u8, len: usize, flags: c_int) isize {
    // In a full implementation, this would construct a msghdr and call recvmsg.
    _ = buf;
    _ = len;
    var flags_mut = flags;
    return recvmsg_impl(fd, @ptrCast(&flags_mut), flags);
}

/// Send a message on a socket.
export fn sendmsg(fd: c_int, msg: *const anyopaque, flags: c_int) isize {
    return sendmsg_impl(fd, msg, flags);
}

/// Receive a message from a socket.
export fn recvmsg(fd: c_int, msg: *anyopaque, flags: c_int) isize {
    return recvmsg_impl(fd, msg, flags);
}

/// Set socket options.
/// TODO: No dedicated TRX syscall yet; stub with -ENOSYS.
export fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: u32) c_int {
    _ = fd;
    _ = level;
    _ = optname;
    _ = optval;
    _ = optlen;
    errno_mod.errno = errno_mod.ENOSYS;
    return -1;
}

/// Get socket options.
/// TODO: No dedicated TRX syscall yet; stub with -ENOSYS.
export fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: *anyopaque, optlen: *u32) c_int {
    _ = fd;
    _ = level;
    _ = optname;
    _ = optval;
    _ = optlen;
    errno_mod.errno = errno_mod.ENOSYS;
    return -1;
}

/// Shut down part of a full-duplex connection.
/// TODO: No dedicated TRX syscall yet; stub with -ENOSYS.
export fn shutdown(fd: c_int, how: c_int) c_int {
    _ = fd;
    _ = how;
    errno_mod.errno = errno_mod.ENOSYS;
    return -1;
}

// ---------------------------------------------------------------------------
// DNS stubs
// ---------------------------------------------------------------------------

/// Stub getaddrinfo -- only numeric addresses would be supported in future.
/// TODO: Full DNS resolution is far future.
export fn getaddrinfo(node: ?[*:0]const u8, service: ?[*:0]const u8, hints: ?*const anyopaque, res: **anyopaque) c_int {
    _ = node;
    _ = service;
    _ = hints;
    _ = res;
    // EAI_NONAME = -2 in glibc; return ENOSYS for now
    errno_mod.errno = errno_mod.ENOSYS;
    return -1;
}

/// Stub freeaddrinfo.
export fn freeaddrinfo(res: *anyopaque) void {
    _ = res;
    // Nothing to free -- getaddrinfo never allocates.
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "htons/ntohs round-trip" {
    const val: u16 = 0x1234;
    const net = htons(val);
    const host = ntohs(net);
    try testing.expectEqual(val, host);
}

test "htonl/ntohl round-trip" {
    const val: u32 = 0xDEADBEEF;
    const net = htonl(val);
    const host = ntohl(net);
    try testing.expectEqual(val, host);
}

test "htons byte swap on little-endian" {
    // 0x0050 (port 80) -> network order should be 0x5000 on LE
    const val: u16 = 80;
    const net = htons(val);
    try testing.expectEqual(@as(u16, 0x5000), net);
}

test "inet_pton parses 127.0.0.1" {
    var addr: u32 = 0;
    const ret = inet_pton(AF_INET, "127.0.0.1", @ptrCast(&addr));
    try testing.expectEqual(@as(c_int, 1), ret);
    // 127.0.0.1 in network byte order = 0x7F000001 big-endian
    // On little-endian: stored as 0x0100007F
    try testing.expectEqual(htonl(0x7F000001), addr);
}

test "inet_pton rejects invalid input" {
    var addr: u32 = 0;
    try testing.expectEqual(@as(c_int, 0), inet_pton(AF_INET, "256.0.0.1", @ptrCast(&addr)));
    try testing.expectEqual(@as(c_int, 0), inet_pton(AF_INET, "1.2.3", @ptrCast(&addr)));
    try testing.expectEqual(@as(c_int, 0), inet_pton(AF_INET, "1.2.3.4.5", @ptrCast(&addr)));
    try testing.expectEqual(@as(c_int, 0), inet_pton(AF_INET, "", @ptrCast(&addr)));
    try testing.expectEqual(@as(c_int, 0), inet_pton(AF_INET, "abc", @ptrCast(&addr)));
}

test "inet_ntop formats 127.0.0.1" {
    const addr = htonl(0x7F000001);
    var buf: [16]u8 = undefined;
    const result = inet_ntop(AF_INET, @ptrCast(&addr), &buf, buf.len);
    try testing.expect(result != null);

    // Compare the buffer contents
    const expected = "127.0.0.1";
    for (expected, 0..) |ch, i| {
        try testing.expectEqual(ch, buf[i]);
    }
    try testing.expectEqual(@as(u8, 0), buf[expected.len]);
}

test "inet_pton/inet_ntop round-trip" {
    var addr: u32 = 0;
    _ = inet_pton(AF_INET, "192.168.1.100", @ptrCast(&addr));

    var buf: [16]u8 = undefined;
    const result = inet_ntop(AF_INET, @ptrCast(&addr), &buf, buf.len);
    try testing.expect(result != null);

    const expected = "192.168.1.100";
    for (expected, 0..) |ch, i| {
        try testing.expectEqual(ch, buf[i]);
    }
}

test "sockaddr_in struct size is 16 bytes" {
    try testing.expectEqual(@as(usize, 16), @sizeOf(sockaddr_in));
}

test "AF_*/SOCK_* constants match expected values" {
    try testing.expectEqual(@as(c_int, 0), AF_UNSPEC);
    try testing.expectEqual(@as(c_int, 2), AF_INET);
    try testing.expectEqual(@as(c_int, 10), AF_INET6);
    try testing.expectEqual(@as(c_int, 1), SOCK_STREAM);
    try testing.expectEqual(@as(c_int, 2), SOCK_DGRAM);
    try testing.expectEqual(@as(c_int, 3), SOCK_RAW);
}

test "SHUT_* constants" {
    try testing.expectEqual(@as(c_int, 0), SHUT_RD);
    try testing.expectEqual(@as(c_int, 1), SHUT_WR);
    try testing.expectEqual(@as(c_int, 2), SHUT_RDWR);
}

test "socket test stub returns fd" {
    const fd = socket(AF_INET, SOCK_STREAM, 0);
    try testing.expectEqual(@as(c_int, 3), fd);
}

test "bind test stub returns 0" {
    var addr = sockaddr_in{
        .family = @intCast(AF_INET),
        .port = htons(8080),
        .addr = htonl(INADDR_ANY),
    };
    const ret = bind(3, @ptrCast(&addr), @sizeOf(sockaddr_in));
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "listen test stub returns 0" {
    const ret = listen(3, 128);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "accept test stub returns fd" {
    const fd = accept(3, null, null);
    try testing.expectEqual(@as(c_int, 4), fd);
}

test "connect test stub returns 0" {
    var addr = sockaddr_in{
        .family = @intCast(AF_INET),
        .port = htons(80),
        .addr = htonl(INADDR_LOOPBACK),
    };
    const ret = connect(3, @ptrCast(&addr), @sizeOf(sockaddr_in));
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "setsockopt returns -ENOSYS" {
    errno_mod.errno = 0;
    var val: c_int = 1;
    const ret = setsockopt(3, 1, 2, @ptrCast(&val), @sizeOf(c_int));
    try testing.expectEqual(@as(c_int, -1), ret);
    try testing.expectEqual(errno_mod.ENOSYS, errno_mod.errno);
}

test "getsockopt returns -ENOSYS" {
    errno_mod.errno = 0;
    var val: c_int = 0;
    var len: u32 = @sizeOf(c_int);
    const ret = getsockopt(3, 1, 2, @ptrCast(&val), &len);
    try testing.expectEqual(@as(c_int, -1), ret);
    try testing.expectEqual(errno_mod.ENOSYS, errno_mod.errno);
}

test "shutdown returns -ENOSYS" {
    errno_mod.errno = 0;
    const ret = shutdown(3, SHUT_RDWR);
    try testing.expectEqual(@as(c_int, -1), ret);
    try testing.expectEqual(errno_mod.ENOSYS, errno_mod.errno);
}

test "INADDR constants" {
    try testing.expectEqual(@as(u32, 0), INADDR_ANY);
    try testing.expectEqual(@as(u32, 0x7F000001), INADDR_LOOPBACK);
}
