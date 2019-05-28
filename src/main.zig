const c = @cImport({
    @cInclude("ncurses.h");
});

const std = @import("std");

const AutoHashMap = std.AutoHashMap;
const fmt = std.fmt;
const io = std.io;
const os = std.os;
const time = os.time;
const warn = std.debug.warn;

const SECONDS_PER_FRAME = 1;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const screen = initscr(allocator);
    defer screen.cleanup();

    var stdin_file = try io.getStdIn();

    try processStream(allocator, &stdin_file.inStream().stream, screen);
}

fn processStream(allocator: *std.mem.Allocator, stream: var, screen: Screen) !void {
    const p = &Processor.init(allocator, screen);
    defer p.deinit();

    var stdout_file = try io.getStdOut();
    const stdout = &stdout_file;

    var buf = try std.Buffer.initSize(allocator, 0);

    var lastRefreshAt = time.timestamp();
    while (true) {
        const line = try io.readLineFrom(stream, &buf);

        try p.count(line);

        const now = time.timestamp();
        if (now - lastRefreshAt > SECONDS_PER_FRAME) {
            try p.draw(now);
            lastRefreshAt = now;
        }
    }
}

pub const Processor = struct {
    allocator: *std.mem.Allocator,
    screen: Screen,
    map: std.AutoHashMap([]const u8, i32),
    buf_title: [256]u8,

    fn init(allocator: *std.mem.Allocator, screen: Screen) Processor {
        var map = AutoHashMap([]const u8, i32).init(allocator);
        return Processor{
            .allocator = allocator,
            .screen = screen,
            .map = map,
            .buf_title = undefined,
        };
    }

    fn deinit(self: Processor) void {
        self.map.deinit();
    }

    fn count(self: *Processor, key: []const u8) !void {
        const entry = try self.map.getOrPutValue(key, 0);
        _ = try self.map.put(key, entry.value + 1);
    }

    fn draw(self: *Processor, ts: u64) !void {
        const title = try fmt.bufPrint(self.buf_title[0..], "{}", ts);
        try self.screen.mvprintw(0, 0, title);

        var max_length: usize = 0;
        var it = self.map.iterator();
        while (it.next()) |next| {
            if (next.key.len > max_length) {
                max_length = next.key.len;
            }
        }

        var y: usize = 1;
        it = self.map.iterator();
        var val_buf: [256]u8 = undefined;
        while (it.next()) |next| {
            try self.screen.mvprintw(y, max_length - next.key.len, next.key);

            const val = try fmt.bufPrint(val_buf[0..], "{}", next.value);
            try self.screen.mvprintw(y, max_length + 1, val);
            y += 1;
        }
        self.screen.refresh();
    }
};

pub const Screen = struct {
    allocator: *std.mem.Allocator,

    pub fn mvprintw(self: Screen, y: usize, x: usize, str: []const u8) !void {
        var buf = try std.Buffer.init(self.allocator, str);
        defer buf.deinit();

        _ = c.mvprintw(@intCast(c_int, y), @intCast(c_int, x), buf.ptr());
    }

    pub fn refresh(self: Screen) void {
        _ = c.refresh();
    }

    pub fn cleanup(self: Screen) void {
        _ = c.endwin();
    }
};

pub fn initscr(allocator: *std.mem.Allocator) Screen {
    _ = c.initscr();
    _ = c.curs_set(0);
    return Screen{ .allocator = allocator };
}
