const print = @import("std").debug.print;
const std = @import("std");
const net = std.net;

const host = "irc.freenode.net";
const port = 6667;
const nickname = "testing-001";
const delimiter = "\r\n";
const channel = "#some-random-channel-001";

const Irc = struct {
    conn: net.Stream = undefined,
    allocator: std.mem.Allocator = undefined,
    buf: std.ArrayList(u8) = undefined,

    fn init(allocator: std.mem.Allocator) !Irc {
        var conn = try net.tcpConnectToHost(allocator, host, port);
        var buf = std.ArrayList(u8).init(allocator);

        return Irc{ .allocator = allocator, .conn = conn, .buf = buf };
    }

    fn sendNickPacket(self: *Irc) anyerror!void {
        _ = try self.send("NICK " ++ nickname ++ delimiter);
    }

    fn sendUserPacket(self: *Irc) anyerror!void {
        _ = try self.send("USER " ++ nickname ++ " * * :" ++ nickname ++ delimiter);
    }

    fn sendPongPacket(self: *Irc, id: []u8) anyerror!void {
        const pong = try std.fmt.allocPrint(self.allocator, "PONG :{s}{s}", .{ id, delimiter });
        _ = try self.send(pong);
    }

    fn sendJoinPacket(self: *Irc) anyerror!void {
        const join = try std.fmt.allocPrint(self.allocator, "JOIN {s}{s}", .{ channel, delimiter });
        _ = try self.send(join);
    }

    fn readLine(self: *Irc) anyerror![]u8 {
        var chr: [1]u8 = undefined;
        self.buf.clearRetainingCapacity();

        while (chr[0] != '\n') {
            var len = try self.conn.read(&chr);
            if (len == 0) {
                break;
            }
            _ = try self.buf.append(chr[0]);
        }
        return self.buf.toOwnedSlice();
    }

    fn loop(self: *Irc) anyerror!void {
        defer self.conn.close();

        _ = try self.sendNickPacket();
        _ = try self.sendUserPacket();

        while (true) {
            const line = try self.readLine();
            defer self.allocator.free(line);
            if (line.len == 0) {
                print("[BYE]: Connection Closed", .{});
                return;
            }
            print("[INFO]: {s}", .{line});
            _ = try self.handleMessage(line[0..line.len]);
        }
    }

    fn send(self: *Irc, msg: []const u8) anyerror!void {
        print("[SEND]: {s}", .{msg});
        _ = try self.conn.write(msg);
    }

    fn handleMessage(self: *Irc, msg: []u8) anyerror!void {
        if (msg.len < 4) {
            return;
        }

        if (std.mem.eql(u8, msg[0..4], "PING")) {
            const idx = std.mem.indexOf(u8, msg, ":").?;
            const id = msg[idx + 1 ..];
            _ = try self.sendPongPacket(id);
        }

        if (std.mem.indexOf(u8, msg, " 396 ")) |_| {
            print("Auto joining {s}\n", .{channel});
            _ = try self.sendJoinPacket();
        }
    }

    fn deinit(self: *Irc) void {
        defer self.buf.deinit();
    }
};

pub fn main() anyerror!void {

    var conn = try Irc.init(std.heap.page_allocator);
    defer conn.deinit();

    _ = try conn.loop();
}

