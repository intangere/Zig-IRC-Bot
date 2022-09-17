const print = @import("std").debug.print;
const std = @import("std");
const net = std.net;
const testing = std.testing;

const host = "irc.freenode.net";
const port = 6667;
const nickname = "testing-001";
const delimiter = "\r\n";
const channel = "#some-random-channel-001";

const irc = struct {
    var conn: net.Stream = undefined;

    fn init() anyerror!void {
        conn = try net.tcpConnectToHost(testing.allocator, host, port);
        _ = try conn.write(buildNickPacket());
        _ = try conn.write(buildUserPacket());
    }

    fn buildNickPacket() []const u8 {
        return "NICK " ++ nickname ++ delimiter;
    }

    fn buildUserPacket() []const u8 {
        return "USER " ++ nickname ++ " * * :" ++ nickname ++ delimiter;
    }

    fn buildPongPacket(id: []u8) anyerror![]const u8 {
        return try std.fmt.allocPrint(std.heap.page_allocator, "PONG :{s}{s}", .{ id, delimiter });
    }

    fn buildJoinPacket() anyerror![]const u8 {
        return try std.fmt.allocPrint(std.heap.page_allocator, "JOIN {s}{s}", .{ channel, delimiter });
    }

    fn readLine() anyerror![]u8 {
        var buf = std.ArrayList(u8).init(std.heap.page_allocator);
        var chr: [1]u8 = undefined;
        while (chr[0] != '\n') {
            var len = try conn.read(&chr);
            if (len == 0) {
                break;
            }
            _ = try buf.append(chr[0]);
        }
        return buf.toOwnedSlice();
    }

    fn loop() anyerror!void {
        _ = try init();
        while (true) {
            const buf = try readLine();
            if (buf.len == 0) {
                print("[BYE]: Connection Closed", .{});
                return;
            }
            print("[INFO]: {s}", .{buf});
            _ = try handleMessage(buf[0..buf.len]);
            std.heap.page_allocator.free(buf);
        }
    }

    fn send(msg: []const u8) anyerror!void {
        print("[SEND]: {s}", .{msg});
        _ = try conn.write(msg);
    }

    fn handleMessage(msg: []u8) anyerror!void {
        if (msg.len < 4) {
            return;
        }

        if (std.mem.eql(u8, msg[0..4], "PING")) {
            const idx = std.mem.indexOf(u8, msg, ":").?;
            const id = msg[idx + 1 ..];
            const pong = try buildPongPacket(id);
            _ = try send(pong);
        }

        if (std.mem.indexOf(u8, msg, " 396 ")) |_| {
            print("Auto joining {s}\n", .{channel});
            const join = try buildJoinPacket();
            _ = try send(join);
        }
    }
};

pub fn main() anyerror!void {
    _ = try irc.init();
    _ = try irc.loop();
}
