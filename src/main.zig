const print = @import("std").debug.print;
const std = @import("std");
const net = std.net;

const host = "irc.freenode.net";
const port = 6667;
const nickname = "testing-001";
const delimiter = "\r\n";
const channel = "#some-random-channel-001";

const irc = struct {
    const This = @This();
    conn: net.Stream = undefined,
    allocator: std.mem.Allocator,
    buf: std.ArrayList(u8) = undefined,

    fn init(allocator: std.mem.Allocator) !*This {
        var this = try allocator.create(This);
        var conn = try net.tcpConnectToHost(allocator, host, port);
        var buf = std.ArrayList(u8).init(allocator);

        this.* = .{ .allocator = allocator, .conn = conn, .buf = buf };
        return this;
    }

    fn sendNickPacket(this: *This) anyerror!void {
        _ = try this.send("NICK " ++ nickname ++ delimiter);
    }

    fn sendUserPacket(this: *This) anyerror!void {
        _ = try this.send("USER " ++ nickname ++ " * * :" ++ nickname ++ delimiter);
    }

    fn sendPongPacket(this: *This, id: []u8) anyerror!void {
        const pong = try std.fmt.allocPrint(this.allocator, "PONG :{s}{s}", .{ id, delimiter });
        _ = try this.send(pong);
    }

    fn sendJoinPacket(this: *This) anyerror!void {
        const join = try std.fmt.allocPrint(this.allocator, "JOIN {s}{s}", .{ channel, delimiter });
        _ = try this.send(join);
    }

    fn readLine(this: *This) anyerror![]u8 {
        var chr: [1]u8 = undefined;
        this.buf.clearRetainingCapacity();

        while (chr[0] != '\n') {
            var len = try this.conn.read(&chr);
            if (len == 0) {
                break;
            }
            _ = try this.buf.append(chr[0]);
        }
        return this.buf.toOwnedSlice();
    }

    fn loop(this: *This) anyerror!void {
        defer this.conn.close();

        _ = try this.sendNickPacket();
        _ = try this.sendUserPacket();

        while (true) {
            const buf = try this.readLine();
            defer this.allocator.free(buf);
            if (buf.len == 0) {
                print("[BYE]: Connection Closed", .{});
                return;
            }
            print("[INFO]: {s}", .{buf});
            _ = try this.handleMessage(buf[0..buf.len]);
        }
    }

    fn send(this: *This, msg: []const u8) anyerror!void {
        print("[SEND]: {s}", .{msg});
        _ = try this.conn.write(msg);
    }

    fn handleMessage(this: *This, msg: []u8) anyerror!void {
        if (msg.len < 4) {
            return;
        }

        if (std.mem.eql(u8, msg[0..4], "PING")) {
            const idx = std.mem.indexOf(u8, msg, ":").?;
            const id = msg[idx + 1 ..];
            _ = try this.sendPongPacket(id);
        }

        if (std.mem.indexOf(u8, msg, " 396 ")) |_| {
            print("Auto joining {s}\n", .{channel});
            _ = try this.sendJoinPacket();
        }
    }

    fn deinit(this: *This) void {
        defer this.allocator.destroy(this);
    }
};

pub fn main() anyerror!void {
    var conn = try irc.init(std.heap.page_allocator);
    defer conn.deinit();

    _ = try conn.loop();
}
