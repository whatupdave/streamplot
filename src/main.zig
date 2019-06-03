const c = @cImport({
    @cInclude("ncurses.h");
    @cInclude("locale.h");
});

const std = @import("std");
use @import("string_map.zig");

const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const time = os.time;
const warn = std.debug.warn;

const MS_PER_FRAME = 200;

const colors = struct {
    var bar: c_int = undefined;
    var key: c_int = undefined;
    var value: c_int = undefined;
};

const A_BOLD = 1 << 13;
const A_STANDOUT = 1 << 8;

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

    var lastRefreshAt = time.milliTimestamp();
    const startAt = lastRefreshAt;
    while (true) {
        const line = try io.readLineFrom(stream, &buf);

        try p.count(line);

        const now = time.milliTimestamp();
        if (now - lastRefreshAt > MS_PER_FRAME) {
            try p.draw(startAt, now);
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

    fn draw(self: *Processor, startTs: u64, now: u64) !void {
        var max_key_len: usize = 0;
        var max_value: usize = 0;
        var it = self.map.iterator();
        while (it.next()) |next| {
            if (next.key.len > max_key_len) {
                max_key_len = next.key.len;
            }
            if (next.value > max_value) {
                max_value = next.value;
            }
        }

        var val_buf: [256]u8 = undefined;
        const max_val_str = try fmt.bufPrint(val_buf[0..], "{}", max_value);

        const bar_max_len = math.min(40, @intCast(usize, c.COLS) - max_val_str.len - max_key_len - 3);
        const bar_factor = @intToFloat(f32, bar_max_len) / @intToFloat(f32, max_value);

        const duration = try printDurationMs(self.buf_title[0..], now - startTs);
        try self.screen.mvprintw(0, 0, self.buf_title);

        var y: usize = 1;
        it = self.map.iterator();
        while (it.next()) |next| {
            // print label
            self.screen.move(y, 1);
            var i: usize = 0;
            while (i < max_key_len - next.key.len) : (i += 1) {
                self.screen.addch(' ');
            }
            self.screen.attron(colors.key);
            try self.screen.mvprintw(y, max_key_len - next.key.len + 1, next.key);
            self.screen.attroff(colors.key);

            // delimiter
            self.screen.addch(' ');

            // print bar
            const bar_len = @floatToInt(usize, @intToFloat(f32, next.value) * bar_factor);
            i = 0;
            self.screen.attron(colors.bar);
            while (i < bar_len) : (i += 1) {
                try self.screen.printw("\u25A0");
            }
            self.screen.attroff(colors.bar);
            i = 0;
            while (i < bar_max_len - bar_len) : (i += 1) {
                self.screen.addch(' ');
            }

            // delimiter
            self.screen.addch(' ');

            // print value
            const val = try fmt.bufPrint(val_buf[0..], "{}", next.value);
            i = 0;
            while (i < max_val_str.len - val.len) : (i += 1) {
                self.screen.addch(' ');
            }
            self.screen.attron(colors.value);
            try self.screen.printw(val);
            self.screen.attroff(colors.value);

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

    pub fn attron(self: Screen, attr: c_int) void {
        _ = c.attron(attr);
    }

    pub fn attroff(self: Screen, attr: c_int) void {
        _ = c.attroff(attr);
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
    _ = c.setlocale(c.LC_ALL, c"");
    _ = c.initscr();
    _ = c.use_default_colors();
    _ = c.curs_set(0);
    _ = c.start_color();

    var i: c_short = 1;
    _ = c.init_pair(i, c.COLOR_BLUE, -1);
    colors.bar = c.COLOR_PAIR(i | A_BOLD);

    i += 1;
    _ = c.init_pair(i, c.COLOR_YELLOW, -1);
    colors.key = c.COLOR_PAIR(i);

    i += 1;
    _ = c.init_pair(i, c.COLOR_BLACK, -1);
    colors.value = c.COLOR_PAIR(i | A_BOLD);

    return Screen{ .allocator = allocator };
}

fn printDurationMs(buf: []u8, durationMs: u64) ![]u8 {
    const hours = @divTrunc(durationMs, 60 * 60 * 1000);
    const minutes = @divTrunc(durationMs, 60 * 1000) % 60;
    const seconds = @divTrunc(durationMs, 1000) % 60;

    var i: usize = 0;
    const hoursStr = try fmt.bufPrint(buf[i..], "{}:", hours);
    i += hoursStr.len;

    if (minutes < 10) {
        _ = try fmt.bufPrint(buf[i..], "0");
        i += 1;
    }
    _ = try fmt.bufPrint(buf[i..], "{}:", minutes);
    i += 2;

    if (seconds < 10) {
        _ = try fmt.bufPrint(buf[i..], "0");
        i += 1;
    }
    _ = try fmt.bufPrint(buf[i..], "{}", seconds);
    i += 1;

    return buf[0..i];
}
