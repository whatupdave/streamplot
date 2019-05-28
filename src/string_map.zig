const std = @import("std");
const HashMap = std.HashMap;
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

// Modified version of BufMap from std library with string keys that supports comptime V
pub fn StringMap(comptime V: type) type {
    return struct {
        const Self = @This();

        hash_map: StringMapHashMap,

        const StringMapHashMap = HashMap([]const u8, V, mem.hash_slice_u8, mem.eql_slice_u8);

        pub fn init(allocator: *Allocator) Self {
            var self = Self{ .hash_map = StringMapHashMap.init(allocator) };
            return self;
        }

        pub fn deinit(self: *Self) void {
            var it = self.hash_map.iterator();
            while (true) {
                const entry = it.next() orelse break;
                self.free(entry.key);
            }

            self.hash_map.deinit();
        }

        /// Same as `set` but the key and value become owned by the StringMap rather
        /// than being copied.
        /// If `setMove` fails, the ownership of key and value does not transfer.
        pub fn setMove(self: *Self, key: []u8, value: V) !void {
            const get_or_put = try self.hash_map.getOrPut(key);
            if (get_or_put.found_existing) {
                self.free(get_or_put.kv.key);
                get_or_put.kv.key = key;
            }
            get_or_put.kv.value = value;
        }

        /// `key` and `value` are copied into the StringMap.
        pub fn set(self: *Self, key: []const u8, value: V) !void {
            // Avoid copying key if it already exists
            const get_or_put = try self.hash_map.getOrPut(key);
            if (!get_or_put.found_existing) {
                get_or_put.kv.key = self.copy(key) catch |err| {
                    _ = self.hash_map.remove(key);
                    return err;
                };
            }
            get_or_put.kv.value = value;
        }

        pub fn get(self: Self, key: []const u8) ?V {
            const entry = self.hash_map.get(key) orelse return null;
            return entry.value;
        }

        pub fn delete(self: *Self, key: []const u8) void {
            const entry = self.hash_map.remove(key) orelse return;
            self.free(entry.key);
            self.free(entry.value);
        }

        pub fn count(self: Self) usize {
            return self.hash_map.count();
        }

        pub fn iterator(self: *const Self) StringMapHashMap.Iterator {
            return self.hash_map.iterator();
        }

        fn free(self: Self, value: []const u8) void {
            self.hash_map.allocator.free(value);
        }

        fn copy(self: Self, value: []const u8) ![]u8 {
            return mem.dupe(self.hash_map.allocator, u8, value);
        }
    };
}
