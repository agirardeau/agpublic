# `infallible-builder`

Macro crate for generating infallible Builder interfaces.

You should probably just use `typed-builder` instead.

## Example Usage

```toml
[dependencies]
infallible-builder = "0.0"
```

```rust
use infallible_builder::Builder;

#[derive(Default)]
#[Builder]
struct Person {
    name: String,
    age: i64,
    birthday: Option<String>,
}

let person = Person::builder()
    .name("Alice")
    .age(30)
    .build();
assert_eq!(person.name, "Alice");
assert_eq!(person.age, 30);
assert_eq!(person.birthday, None);
```

The base type must implement `Default`. To implement `Default` for structs with
non-`Default` fields, consider a crate like [smart-default]
(https://docs.rs/smart-default/latest/smart_default/):

```rust
use smart_default::SmartDefault;

// Non-Default type
pub enum Color { Red, Blue }

#[derive(SmartDefault)]
#[Builder]
pub struct Line {
    length: i64,
    #[default(Color::Red)]
    color: Color,
}
```

### Implementation Notes

As of 0.0, this is implemented as attribute proc macro that adds
`derive_builder::Builder` to the annotated struct. As a result, some
`#[builder()]` annotations supported by `derive_builder` are respected, however
this behavior may change in the future.
