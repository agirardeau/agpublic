# `infallible-builder`

Macro crate for generating infallible Builder interfaces.

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

## Design Philosophy

Compared to other crates (e.g. [derive_builder]
(https://docs.rs/derive_builder/latest/derive_builder/index.html),
[typed-builder]
(https://docs.rs/typed-builder/latest/typed_builder/index.html)),
`infallible-builder` is more opinionated. It
generates builder types only with the following restrictions:

* Builders do not require fields, i.e. `MyType::builder().build()` is always
  allowed
* Builder methods are thin setters, at most calling `.into()`
* Builders do not contain additional logic or functionality, such as validation or
  serialization

This has some direct benefits:
    
* The `build()` method is always infallible, improving ergonomics
* The builder interface is self apparent from the base struct

`infallible-builder` makes other opinionated choices with the goal of builders
for different base structs having consistent interfaces:

* `setter(into, strip_option)` is configured by default
* The "owned" pattern is used rather than the "mutable" pattern, since "mutable"
  disallows structs with non-`Clone` fields

It is this crate author's opinion that builder customizability is ultimately
detrimental, mostly enabling use cases where builders are not an ideal fit.

### Implementation Notes

As of 0.0, this is implemented as attribute proc macro that adds
`derive_builder::Builder` to the annotated struct. As a result, some
`#[builder()]` annotations supported by `derive_builder` are respected, however
this behavior may change in the future.
