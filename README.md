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
// Thameson


// Iterates an array

fn print_name(value: Value, i: usize) void {
    const name = get(value.bytes, .{"name"}) catch unreachable;
    std.log.warn("student{d} name: {s}", .{ i, name.bytes });
}


const students = try get(input, .{"student"});
try forEach(students.bytes, print_name);
// prints 
// "student0 name: Tom"
// "student1 name: Nick"
```

