const std = @import("std");

const lib = @import("lib.zig");
const Value = lib.Value;
const Error = lib.Error;

pub const ArrayIterator = struct {
    input: []const u8,
    index: usize = 0,
    cursor: usize = 1, // we want to skip '['

    const Self = @This();

    pub fn init(value: Value) !ArrayIterator {
        if (value.kind != .array) {
            return error.InvalidValue;
        }

        return ArrayIterator{ .input = value.bytes };
    }

    pub fn next(self: *Self) Error!?Value {
        self.cursor += try lib.find_next_char(self.input[self.cursor..]);
        if (self.cursor == self.input.len or self.input[self.cursor] == ']') {
            return null;
        }

        const value = try lib.get(self.input[self.cursor..], .{});
        self.cursor += value.offset + value.bytes.len + 1;

        // find,
        self.cursor += try lib.find_next_char(self.input[self.cursor..]);
        if (self.input[self.cursor] == ',') {
            self.index += 1;
        }

        return value;
    }
};

test "readme with array iterator" {
    const input =
        \\ {
        \\   "student": [
        \\     {
        \\       "id": "01",
        \\       "name": "Tom",
        \\       "lastname": "Price"
        \\     },
        \\     {
        \\       "id": "02",
        \\       "name": "Nick",
        \\       "lastname": "Thameson"
        \\     }
        \\   ]
        \\ }
    ;

    const students = try lib.get(input, .{"student"});
    var iter = try ArrayIterator.init(students);

    while (try iter.next()) |s| {
        const name = lib.get(s.bytes, .{"name"}) catch unreachable;
        std.debug.print("student name: {s}\n", .{name.bytes});
    }
}
