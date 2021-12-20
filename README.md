# zjson

A very tiny json library, it allows you to get a json value from a path.
Inspired by [jsonparser](https://github.com/buger/jsonparser) a Go library.

## Example:

```rs
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
// prints Thameson


// Iterates an array
fn print_name(value: Value, _: usize) void {
    const name = get(value.bytes, .{"name"}) catch unreachable;
    std.debug.log("student name: {s}", .{ name.bytes });
}

const students = try get(input, .{"student"});
try forEach(students.bytes, print_name);
// prints 
// "student0 name: Tom"
// "student1 name: Nick"


// this is the same as
var iter = try zjson.ArrayIterator(students);
while(try iter.next()) |s| {
    const name = get(value.bytes, .{"name"}) catch unreachable;
    std.debug.log("student name: {s}", .{ name.bytes });
}
```

