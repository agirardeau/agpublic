#[cfg(feature = "serde")]

use crate::LookupVec;
use crate::Lookup;

use serde::Deserialize;
use serde::Deserializer;
use serde::de::Error as DeError;
use serde::de::IntoDeserializer;
use serde::de::value::SeqDeserializer;
use serde::Serialize;
use serde::Serializer;
#[allow(unused_imports)]
use std::error::Error as _;
use std::hash::BuildHasher;

impl<T, S> Serialize for LookupVec<T, S> 
where 
    T: Lookup + Serialize,
    S: BuildHasher,
{
    fn serialize<Ser>(&self, serializer: Ser) -> Result<Ser::Ok, Ser::Error>
    where
        Ser: Serializer,
    {
        // Serialize as a sequence/array of values
        use serde::ser::SerializeSeq;
        let mut seq = serializer.serialize_seq(Some(self.len()))?;
        for value in self.iter() {
            seq.serialize_element(value)?;
        }
        seq.end()
    }
}

impl<'de, T, S> Deserialize<'de> for LookupVec<T, S>
where
    T: Lookup + Deserialize<'de>,
    S: BuildHasher + Default,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        // Deserialize from a sequence/array
        struct LookupVecVisitor<T, S> {
            marker: std::marker::PhantomData<(T, S)>,
        }

        impl<'de, T, S> serde::de::Visitor<'de> for LookupVecVisitor<T, S>
        where
            T: Lookup + Deserialize<'de>,
            S: BuildHasher + Default,
        {
            type Value = LookupVec<T, S>;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("a sequence of values")
            }

            fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::SeqAccess<'de>,
            {
                let mut vec: LookupVec<T, S> = LookupVec::with_capacity_and_hasher(
                    seq.size_hint().unwrap_or(0),
                    S::default()
                );

                while let Some(value) = seq.next_element()? {
                    if let Some(preexisting) = vec.push(value) {
                        //let key: T::Key = value.key();
                        return Err(A::Error::custom(format!("Found duplicate key {:?}", preexisting.key())))
                    }
                }

                Ok(vec)
            }
        }

        deserializer.deserialize_seq(LookupVecVisitor {
            marker: std::marker::PhantomData,
        })
    }
}

impl<'de, T, S, E> IntoDeserializer<'de, E> for LookupVec<T, S>
where
    T: Lookup + IntoDeserializer<'de, E>,
    S: BuildHasher,
    E: DeError,
{
    type Deserializer = SeqDeserializer<<Self as IntoIterator>::IntoIter, E>;

    fn into_deserializer(self) -> Self::Deserializer {
        SeqDeserializer::new(self.into_iter())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, PartialEq, Serialize, Deserialize)]
    struct TestItem {
        id: String,
        value: i32,
    }

    impl Lookup for TestItem {
        type Key = String;
        fn key(&self) -> String {
            self.id.clone()
        }
    }

    impl<'de> IntoDeserializer<'de, serde_json::Error> for TestItem {
        type Deserializer = serde_json::Value;

        fn into_deserializer(self) -> Self::Deserializer {
            serde_json::to_value(&self).unwrap()
        }
    }

    fn create_test_item(id: &str, value: i32) -> TestItem {
        TestItem {
            id: id.to_string(),
            value,
        }
    }

    #[derive(Debug, PartialEq, Serialize, Deserialize)]
    struct TestItemIntKey {
        id: u64,
        value: String,
    }

    impl Lookup for TestItemIntKey {
        type Key = u64;
        fn key(&self) -> u64 {
            self.id
        }
    }

    fn create_test_item_int_key(id: u64, value: &str) -> TestItemIntKey {
        TestItemIntKey {
            id: id,
            value: value.to_string(),
        }
    }

    #[test]
    fn test_serialize_empty() {
        let vec: LookupVec<TestItem> = LookupVec::new();
        let json = serde_json::to_string(&vec).unwrap();
        assert_eq!(json, "[]");
    }

    #[test]
    fn test_deserialize_empty() {
        let json = "[]";
        let vec: LookupVec<TestItem> = serde_json::from_str(json).unwrap();
        assert!(vec.is_empty());
    }

    #[test]
    fn test_serialize_single_item() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1", 42));
        
        let json = serde_json::to_string(&vec).unwrap();
        assert_eq!(json, r#"[{"id":"test1","value":42}]"#);
    }

    #[test]
    fn test_deserialize_single_item() {
        let json = r#"[{"id":"test1","value":42}]"#;
        let vec: LookupVec<TestItem> = serde_json::from_str(json).unwrap();
        
        assert_eq!(vec.len(), 1);
        let item = vec.get("test1").unwrap();
        assert_eq!(item.value, 42);
    }

    #[test]
    fn test_serialize_multiple_items() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1", 1));
        vec.push(create_test_item("test2", 2));
        vec.push(create_test_item("test3", 3));

        let json = serde_json::to_string(&vec).unwrap();
        assert_eq!(json, r#"[{"id":"test1","value":1},{"id":"test2","value":2},{"id":"test3","value":3}]"#);
    }

    #[test]
    fn test_deserialize_multiple_items() {
        let json = r#"[
            {"id":"test1","value":1},
            {"id":"test2","value":2},
            {"id":"test3","value":3}
        ]"#;
        let vec: LookupVec<TestItem> = serde_json::from_str(json).unwrap();

        assert_eq!(vec.len(), 3);
        assert_eq!(vec.get("test1").unwrap().value, 1);
        assert_eq!(vec.get("test2").unwrap().value, 2);
        assert_eq!(vec.get("test3").unwrap().value, 3);
    }

    #[test]
    fn test_roundtrip_serialization() {
        let mut original = LookupVec::new();
        original.push(create_test_item("a", 1));
        original.push(create_test_item("b", 2));

        let json = serde_json::to_string(&original).unwrap();
        let deserialized: LookupVec<TestItem> = serde_json::from_str(&json).unwrap();

        assert_eq!(original.len(), deserialized.len());
        assert_eq!(original.get("a").unwrap().value, deserialized.get("a").unwrap().value);
        assert_eq!(original.get("b").unwrap().value, deserialized.get("b").unwrap().value);
    }

    #[test]
    fn test_roundtrip_serialization_int_key() {
        let mut original = LookupVec::new();
        original.push(create_test_item_int_key(10, "a"));
        original.push(create_test_item_int_key(20, "b"));

        let json = serde_json::to_string(&original).unwrap();
        assert_eq!(json, r#"[{"id":10,"value":"a"},{"id":20,"value":"b"}]"#);

        let deserialized: LookupVec<TestItemIntKey> = serde_json::from_str(&json).unwrap();
        assert_eq!(original.len(), deserialized.len());
        assert_eq!(original.get(&10).unwrap().value, deserialized.get(&10).unwrap().value);
        assert_eq!(original.get(&20).unwrap().value, deserialized.get(&20).unwrap().value);
    }

    #[test]
    fn test_deserialize_invalid_json() {
        let json = r#"[{"id":"test1","value":1},]"#; // Invalid trailing comma
        let result: Result<LookupVec<TestItem>, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }

    #[test]
    fn test_order_preservation() {
        let json = r#"[
            {"id":"c","value":3},
            {"id":"a","value":1},
            {"id":"b","value":2}
        ]"#;
        let vec: LookupVec<TestItem> = serde_json::from_str(json).unwrap();

        let keys: Vec<_> = vec.keys().collect();
        assert_eq!(keys, vec!["c", "a", "b"]);
    }

    #[test]
    fn test_duplicate_keys_fail() {
        let json = r#"[
            {"id":"a","value":1},
            {"id":"b","value":2},
            {"id":"b","value":2}
        ]"#;
        let result: Result<LookupVec<TestItem>, _> = serde_json::from_str(json);
        assert!(result.is_err());
        let err_string = result.unwrap_err().to_string();
        assert!(
            err_string.contains(r#"Found duplicate key "b""#),
            "Unexpected error string: {}",
            err_string,
        );
    }

    #[test]
    fn test_into_deserializer() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1", 42));
        vec.push(create_test_item("test2", 84));

        let deserializer = vec.into_deserializer();
        let deserialized: Vec<TestItem> = Vec::deserialize(deserializer).unwrap();

        assert_eq!(deserialized.len(), 2);
        assert_eq!(deserialized[0].id, "test1");
        assert_eq!(deserialized[0].value, 42);
        assert_eq!(deserialized[1].id, "test2");
        assert_eq!(deserialized[1].value, 84);
    }
}