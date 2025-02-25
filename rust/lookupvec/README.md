# LookupVec

Container with Vec-like properties that also offers O(1) lookup of items based on a primary key field

## Usage

```rust
#[derive(PartialEq, Lookup)]
struct MyStruct {
  #[lookup_key]
  pub name: String,
  pub description: String,
  pub count: usize,
}

let vec = LookupVec.from([
    MyStruct {
        name: "foo",
        description: "description of foo",
        count: 7,
    },
    MyStruct {
        name: "bar",
        description: "description of bar",
        count: 13,
    },
])
assert_eq!(vec[0], vec.get("foo"))
assert_eq!(vec[1], vec.get("bar"))
```