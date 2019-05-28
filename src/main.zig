const c = @cImport({
    @cInclude("ncurses.h");
});

const std = @import("std");
use @import("string_map.zig");

const fmt = std.fmt;
const io = std.io;
const mem = std.mem;
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
    var p = Processor.init(allocator, screen);
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
    map: StringMap(usize),
    buf_title: [256]u8,

    fn init(allocator: *std.mem.Allocator, screen: Screen) Processor {
        var map = StringMap(usize).init(allocator);
        return Processor{
            .allocator = allocator,
            .screen = screen,
            .map = map,
            .buf_title = undefined,
        };
    }

    fn deinit(self: *Processor) void {
        self.map.deinit();
    }

    fn count(self: *Processor, key: []const u8) !void {
        var optional_entry = self.map.get(key);
        if (optional_entry) |entry| {
            try self.map.set(key, entry + 1);
        } else {
            try self.map.set(key, 1);
        }
    }

    fn draw(self: *Processor, ts: u64) !void {
        const title = try fmt.bufPrint(self.buf_title[0..], "{}", ts);
        try self.screen.mvprintw(0, 0, title);

        var max_length: usize = 0;
        var max_value: f32 = 0;
        var it = self.map.iterator();
        while (it.next()) |next| {
            if (next.key.len > max_length) {
                max_length = next.key.len;
            }
            const fval = @intToFloat(f32, next.value);
            if (fval > max_value) {
                max_value = fval;
            }
        }

        var y: usize = 1;
        it = self.map.iterator();
        var val_buf: [256]u8 = undefined;
        while (it.next()) |next| {
            // print label
            self.screen.move(y, 1);
            var i: usize = 0;
            while (i < max_length - next.key.len) : (i += 1) {
                self.screen.addch(' ');
            }
            try self.screen.mvprintw(y, max_length - next.key.len + 1, next.key);

            // plot bar
            self.screen.addch(' ');

            const bar_len = @intToFloat(f32, next.value) / max_value * 20;
            var j: f32 = 0;
            while (j < bar_len) : (j += 1) {
                self.screen.addch('#');
            }
            self.screen.addch(' ');

            const val = try fmt.bufPrint(val_buf[0..], "{}", next.value);
            try self.screen.printw(val);
            self.screen.clrtoeol();
            y += 1;
        }
        self.screen.refresh();
    }
};

pub const Screen = struct {
    allocator: *std.mem.Allocator,

    pub fn addch(self: Screen, ch: u8) void {
        _ = c.addch(ch);
    }

    pub fn clrtoeol(self: Screen) void {
        _ = c.clrtoeol();
    }

    pub fn move(self: Screen, y: usize, x: usize) void {
        _ = c.move(@intCast(c_int, y), @intCast(c_int, x));
    }

    pub fn mvprintw(self: Screen, y: usize, x: usize, str: []const u8) !void {
        var buf = try std.Buffer.init(self.allocator, str);
        defer buf.deinit();

        _ = c.mvprintw(@intCast(c_int, y), @intCast(c_int, x), buf.ptr());
    }

    pub fn printw(self: Screen, str: []const u8) !void {
        var buf = try std.Buffer.init(self.allocator, str);
        defer buf.deinit();

        _ = c.printw(buf.ptr());
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
