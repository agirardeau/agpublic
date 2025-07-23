//pub use infallible_builder_macro::Builder;
pub use infallible_builder_macro::InfallibleBuilder;

#[cfg(test)]
mod tests {
    use super::*;
    use smart_default::SmartDefault;

    //#[derive(Default, Builder)]
    #[derive(Default)]
    #[InfallibleBuilder]
    struct Person {
        name: String,
        age: i64,
        birthday: Option<String>,
    }

    #[test]
    fn builder_sets_fields_correctly() {
        let person = Person::builder()
            .name("Alice")
            .age(30)
            .build();
        assert_eq!(person.name, "Alice");
        assert_eq!(person.age, 30);
    }

    #[test]
    fn builder_is_mutable() {
        let mut person_builder = Person::builder();
        person_builder.name("Bob");
        person_builder.age(25);
        let person = person_builder.build();
        assert_eq!(person.name, "Bob");
        assert_eq!(person.age, 25);
    }

    #[test]
    fn builder_uses_defaults() {
        let person = Person::builder().build();
        assert_eq!(person.name, "");
        assert_eq!(person.age, 0);
        assert_eq!(person.birthday, None);
    }

    #[test]
    fn builder_strips_option() {
        // The builder should accept the inner type for Option fields
        let person = Person::builder()
            .birthday("2000-01-01")
            .build();
        assert_eq!(person.birthday, Some("2000-01-01".to_string()));
    }

    #[test]
    fn builder_works_with_smart_default() {
        //#[derive(SmartDefault, Builder)]
        #[derive(PartialEq, SmartDefault)]
        #[InfallibleBuilder]
        struct Animal {
            #[default(Species::Dog)]
            pub species: Species,
        }

        // Non-Default type
        #[derive(Debug, Clone, PartialEq)]
        #[allow(dead_code)]
        enum Species {
            Dog,
            Cat,
        }

        let animal = Animal::builder().build();
        assert_eq!(animal.species, Species::Dog);
    }
}