const std = @import("std");

pub const OldValue = struct {
    str: []const u8,
    kind: ValueKind,
    offset: usize,
};

const PathItem = union(enum) {
    key: []const u8,
    index: usize,
};

/// Represents possible errors in this library.
pub const Error = error{
    InvalidJSON,
    InvalidBlock,
    KeyNotFound,
    IndexNotFound,
    InvalidTypeCast,
    UnexpectedEOF,
};

/// Represents a JSON value
pub const Value = struct {
    bytes: []const u8,
    kind: ValueKind,
    offset: usize,

    const Self = @This();

    pub fn toBool(self: Self) Error!bool {
        if (std.mem.eql(u8, self.bytes, "true")) {
            return true;
        } else if (std.mem.eql(u8, self.bytes, "false")) {
            return false;
        }

        return Error.InvalidTypeCast;
    }
};

/// Represents a JSON value type
pub const ValueKind = enum {
    boolean,
    string,
    integer,
    float,
    object,
    array,
};

/// Represents a JSON block, such as
/// Array, Object, String
const Block = struct {
    offset: usize,
    bytes: []const u8,
};

/// Returns offset of the next significant char
fn find_next_char(input: []const u8) !usize {
    var offset: usize = 0;

    // advances until finds a valid char
    while (offset < input.len) {
        switch (input[offset]) {
            ' ', '\n', '\r', '\t' => {
                offset += 1;
            },

            else => return offset,
        }
    }

    return 0;
}

/// Returns a json `Value` based on a path.
pub fn get(input: []const u8, path: anytype) Error!Value {

    // basically we get the path fields, and save as `PathItem`
    const path_fields = comptime std.meta.fields(@TypeOf(path));

    var keys: [path_fields.len]PathItem = undefined;
    inline for (path_fields) |f, i| {
        switch (f.field_type) {
            // used for array indexes
            comptime_int => {
                keys[i] = PathItem{ .index = f.default_value.? };
            },

            // everything else is a string for us, the compiler should handle
            // this errors, until I found a better way.
            // it is pretty? NO
            // does it work for now? YES
            else => {
                keys[i] = PathItem{ .key = f.default_value.? };
            },
        }
    }

    // reads input until match path, or until it ends
    var cursor: usize = 0;
    var key_matched = false;
    var depth: usize = 0;

    while (cursor < input.len) {
        cursor += try find_next_char(input[cursor..]);

        // std.log.warn("depth: {d} -> {s}", .{ depth, input[0 .. cursor + 1] });

        switch (input[cursor]) {
            '{' => {
                // we want to skip the block if its not matched,
                // unless its on the first level
                if (!key_matched and depth > 0) {
                    const block = try read_block(input[cursor..], '{', '}');
                    cursor += block.offset + 1; // we add 1 to include '}'
                    key_matched = false;
                    continue;
                }

                // we are at the end, so we return current block
                if (key_matched and depth == keys.len) {
                    const block = try read_block(input[cursor..], '{', '}');
                    return Value{
                        .bytes = block.bytes,
                        .kind = .object,
                        .offset = cursor,
                    };
                }

                if (keys.len == 0) {
                    const block = try read_block(input[cursor..], '{', '}');
                    return Value{
                        .bytes = block.bytes,
                        .kind = .object,
                        .offset = cursor,
                    };
                }

                // if we are here, it means the last key was matched or we are
                // just starting with the parsing so its safe to increase level
                // and cursor
                key_matched = false;
                depth += 1;
                cursor += 1;
            },
            '[' => {
                // we want to skip the block if its not matched,
                // unless its on the first level
                if (!key_matched and depth > 0) {
                    const block = try read_block(input[cursor..], '[', ']');
                    cursor += block.offset + 1; // we add 1 to include ']'
                    continue;
                }

                // we are at the end, so we return current block
                if (key_matched and depth == keys.len) {
                    const block = try read_block(input[cursor..], '[', ']');
                    return Value{
                        .bytes = block.bytes,
                        .kind = .array,
                        .offset = cursor,
                    };
                }

                // Probably used to get type, like object or array
                if (keys.len == 0) {
                    const block = try read_block(input[cursor..], '[', ']');
                    return Value{
                        .bytes = block.bytes,
                        .kind = .array,
                        .offset = cursor,
                    };
                }

                // if we are here, it means the last key was matched or we are
                // just starting with the parsing so its safe to increase level
                // and cursor
                if (key_matched) {
                    depth += 1;

                    const index = switch (keys[depth - 1]) {
                        .index => |v| v,
                        else => return error.KeyNotFound,
                    };

                    const item = try get_offset_by_index(input[cursor..], index);
                    cursor += item;
                    continue;
                }

                key_matched = false;
                cursor += 1;
            },

            '"' => {
                // parse double quote block
                const value = try read_string(input[cursor..]);
                cursor += value.offset + 1;

                // it means we are at the end
                if (key_matched and depth == keys.len) {
                    return Value{
                        .bytes = value.bytes,
                        .kind = .string,
                        .offset = cursor,
                    };
                }

                const next_cursor = try find_next_char(input[cursor..]);

                // it means is a key (we read one next char)
                if (input[cursor + next_cursor] == ':') {
                    cursor += next_cursor;

                    // here only keys works
                    const key = switch (keys[depth - 1]) {
                        .key => |v| v,
                        else => return Error.KeyNotFound,
                    };

                    // compare key with corresponding key in path param
                    if (std.mem.eql(u8, value.bytes, key)) {
                        key_matched = true;
                    }
                }
            },

            // number
            '-', '0'...'9' => {
                const number = read_number(input[cursor..]);
                if (key_matched) {
                    return Value{
                        .bytes = number.inner,
                        .kind = number.kind,
                        .offset = cursor,
                    };
                }

                cursor += number.offset;
            },

            // boolean
            't' => {
                // you cant reach this point unless is a key value
                if (!key_matched) {
                    return Error.InvalidJSON;
                }

                if (depth < keys.len) {
                    return Error.KeyNotFound;
                }

                const offset = (try read_until(input[cursor..], 'e')) + 1;
                if (std.mem.eql(u8, input[cursor .. cursor + offset], "true")) {
                    return Value{
                        .bytes = input[cursor .. cursor + offset],
                        .kind = .boolean,
                        .offset = cursor + offset,
                    };
                }

                return Error.InvalidJSON;
            },
            'f' => {
                // you cant reach this point unless is a key value
                if (!key_matched) {
                    return Error.InvalidJSON;
                }

                if (depth < keys.len) {
                    return Error.KeyNotFound;
                }

                const offset = (try read_until(input[cursor..], 'e')) + 1;
                if (std.mem.eql(u8, input[cursor .. offset + cursor], "false")) {
                    return Value{
                        .bytes = input[cursor .. offset + cursor],
                        .kind = .boolean,
                        .offset = cursor + offset,
                    };
                }

                return Error.InvalidJSON;
            },
            else => cursor += 1,
        }
    }

    return Error.InvalidJSON;
}

pub const foreach_op = fn (value: Value, index: usize) void;
pub fn forEach(input: []const u8, fn_call: foreach_op) !void {
    // we expect input to be an array
    if (input.len < 1 or input[0] != '[' or input[input.len - 1] != ']') {
        return Error.InvalidBlock;
    }

    var offset: usize = 1;
    var index: usize = 0;
    while (offset < input.len) {
        offset += try find_next_char(input[offset..]);
        switch (input[offset]) {
            '[' => {
                const block = try read_block(input[offset..], '[', ']');
                fn_call(Value{ .bytes = block.bytes, .kind = .array, .offset = offset }, index);
                offset += block.offset + 1; // +1 includes ]
            },
            '{' => {
                const block = try read_block(input[offset..], '{', '}');
                fn_call(Value{ .bytes = block.bytes, .kind = .object, .offset = offset }, index);
                offset += block.offset + 1; // +1 includes }
            },
            '"' => {
                const block = try read_string(input[offset..]);
                fn_call(Value{ .bytes = block.bytes, .kind = .string, .offset = offset }, index);
                offset += block.offset; // +1 includes "
            },
            '-', '0'...'9' => {
                const block = read_number(input[offset..]);
                fn_call(Value{ .bytes = block.inner, .kind = block.kind, .offset = offset }, index);
                offset += block.offset;
            },
            ',' => {
                offset += 1;
                index += 1;
            },
            // always at the end
            ']' => {
                offset += 1;
            },
            else => @panic("Not supported yet"),
        }
    }
}

fn read_block(input: []const u8, start: u8, end: u8) Error!Block {

    // first we should start block, is a valid block
    // this should never happens i guess
    if (input[0] != start) {
        @panic("library error when parsing block, this is my fault");
    }

    var offset: usize = 1;

    // now we read until find close delimiter
    while (offset < input.len and input[offset] != end) {
        offset += 1;
    }

    // if we reach the end and we didnt find the end delimiter,
    // it means the block is invalid, because it has no end.
    if (offset == input.len) {
        return Error.InvalidBlock;
    }

    return Block{ .offset = offset, .bytes = input[0 .. offset + 1] };
}

fn read_string(input: []const u8) Error!Block {

    // first we should start block, is a valid block
    // this should never happens i guess
    if (input[0] != '"') {
        @panic("library error when parsing string, this is my fault");
    }

    var cursor: usize = 1;
    var last_escaped = false;

    // now we read until find close delimiter
    while (cursor < input.len) {
        switch (input[cursor]) {
            '"' => {
                if (last_escaped) {
                    cursor += 1;
                    last_escaped = false;
                } else {
                    break;
                }
            },
            '\\' => last_escaped = true,
            else => last_escaped = false,
        }
        cursor += 1;
    }

    // if we reach the end and we didnt find the end delimiter,
    // it means the block is invalid, because it has no end.
    if (cursor == input.len) {
        return Error.InvalidBlock;
    }

    return Block{ .offset = cursor, .bytes = input[1..cursor] };
}

// has a lot of errors for now, specially on detecting format errors,
// ex: -8.65.4
//      8-5.6
// both valid numbers acording this function, but obviously not
fn read_number(input: []const u8) struct { offset: usize, inner: []const u8, kind: ValueKind } {
    var offset: usize = 0;
    var kind: ValueKind = .integer;

    // now we read until find close delimeter
    while (std.ascii.isDigit(input[offset]) or input[offset] == '.' or input[offset] == '-') : (offset += 1) {
        if (input[offset] == '-') {
            kind = .float;
        }
    }

    return .{ .offset = offset, .inner = input[0..offset], .kind = kind };
}

// Returns the offset, between the start of input to delimeter
fn read_until(input: []const u8, delimiter: u8) Error!usize {
    var offset: usize = 0;

    while (offset < input.len and input[offset] != delimiter) {
        offset += 1;
    }

    return offset;
}

// input needs to be a json array in this format:
// "[a, b, c, d, ...]"
//
// Returns the offset from 0 to the previous byte
fn get_offset_by_index(input: []const u8, index: usize) Error!usize {
    var offset: usize = 0;

    // check if is an array
    if (input[offset] == '[') {
        offset += 1;
        // else return error
    }

    var cursor_index: usize = 0;
    while (offset < input.len) {
        offset += try find_next_char(input[offset..]);

        if (cursor_index == index) {
            return offset;
        }

        switch (input[offset]) {
            '[' => {
                const block = try read_block(input[offset..], '[', ']');
                offset += block.offset + 1; // +1 includes ]
            },
            // always at the end
            ']' => {
                offset += 1;
            },
            '{' => {
                const block = try read_block(input[offset..], '{', '}');
                offset += block.offset + 1; // +1 includes }
            },
            '"' => {
                const block = try read_string(input[offset..]);
                offset += block.offset; // +1 includes "
            },
            '-', '0'...'9' => {
                const block = read_number(input[offset..]);
                offset += block.offset;
            },
            ',' => {
                offset += 1;
                cursor_index += 1;
            },
            else => @panic("Not supported yet"),
        }
    }

    return Error.IndexNotFound;
}

test "one level, only string" {
    var input =
        \\ {
        \\   "key1": "value1",
        \\   "key2": "value2",
        \\   "key3": false
        \\ }
    ;

    var value1 = try get(input, .{"key1"});
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "value1"));

    var value2 = try get(input, .{"key2"});
    try std.testing.expect(std.mem.eql(u8, value2.bytes, "value2"));

    var value3 = try get(input, .{"key3"});
    try std.testing.expect(std.mem.eql(u8, value3.bytes, "false"));
}

test "one level, only integer" {
    var input =
        \\ {
        \\   "key1": 8,
        \\   "key2": 5654
        \\ }
    ;

    var value1 = try get(input, .{"key1"});
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "8"));

    var value2 = try get(input, .{"key2"});
    try std.testing.expect(std.mem.eql(u8, value2.bytes, "5654"));
}

test "two level, only string" {
    var input =
        \\ {
        \\   "key1": { "key11": "value11" },
        \\   "key2": "value2",
        \\   "key3": { "key11": "value11" }
        \\ }
    ;

    var value1 = try get(input, .{ "key1", "key11" });
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "value11"));

    var value2 = try get(input, .{"key2"});
    try std.testing.expect(std.mem.eql(u8, value2.bytes, "value2"));

    var value3 = try get(input, .{"key3"});
    try std.testing.expect(std.mem.eql(u8, value3.bytes, "{ \"key11\": \"value11\" }"));
}

test "array" {
    var input =
        \\ {
        \\   "key1": [8, 5, 6],
        \\   "key2": 5654
        \\ }
    ;

    var value1 = try get(input, .{ "key1", 2 });
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "6"));
}

test "array with more keys" {
    var input =
        \\ {
        \\   "key1": [8, {"foo": "bar", "value": 6}, 5],
        \\   "key2": [{"foo": 23} , {"foo": "bar", "value": 6}, 5],
        \\   "key3": 5654
        \\ }
    ;

    var value1 = try get(input, .{ "key1", 1, "value" });
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "6"));
}

test "array with more keys 2" {
    var input =
        \\ {
        \\   "key": [
        \\      {
        \\          "value": 6
        \\      },
        \\      {
        \\          "value": 8
        \\      }
        \\   ]
        \\ }
    ;

    var value1 = try get(input, .{ "key", 1, "value" });
    try std.testing.expect(std.mem.eql(u8, value1.bytes, "8"));
}

fn print_name(value: Value, i: usize) void {
    const name = get(value.bytes, .{"name"}) catch unreachable;
    std.log.warn("student{d} name: {s}", .{ i, name.bytes });
}

test "readme example" {
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

    const name = try get(input, .{ "student", 1, "lastname" });
    try std.testing.expect(std.mem.eql(u8, name.bytes, "Thameson"));

    const students = try get(input, .{"student"});

    try forEach(students.bytes, print_name);
}
