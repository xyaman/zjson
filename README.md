# zjson

A very tiny json library, it allows you to get a json value from a path.
Inspired by [jsonparser](https://github.com/buger/jsonparser), a Go library.

This library is useful when you dont want to parse whole JSON file, or when
the structure is to complex to parse to structs. It **allocates no memory**.

> This library is still WIP, the API might change. There can be some bugs as it's not fully tested.

## API usage:

Here there is a basic example.

```zig
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

const lastname = try get(input, .{ "student", 1, "lastname" });
// Thameson


// Iterates an array
const students = try get(input, .{"student"});

var iter = try zjson.ArrayIterator(students);
while(try iter.next()) |s| {
    const name = try get(value.bytes, .{"name"}); 
    std.debug.print("student name: {s}\n", .{name.bytes});
}
// "student name: Tom"
// "student name: Nick"
```

For more usage examples, you can check [ytmusic-zig](https://github.com/xyaman/ytmusic-zig).
