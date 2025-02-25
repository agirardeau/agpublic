use crate::core::Lookup;
use crate::iter::*;

use delegate::delegate;
use indexmap::IndexMap;
use indexmap::Equivalent;

use std::cmp::Ordering;
use std::hash::BuildHasher;
use std::hash::Hash;
use std::hash::RandomState;
use std::ops::RangeBounds;

#[cfg(feature = "std")]
#[derive(Default)]
pub struct LookupVec<T: Lookup, S = RandomState> {
    map: IndexMap<T::Key, T, S>,
}

#[cfg(not(feature = "std"))]
#[derive(Debug, Default, Clone)]
pub struct LookupVec<T: Lookup, S> {
    map: IndexMap<T::Key, T, S>,
}

#[cfg(feature = "std")]
impl<T: Lookup> LookupVec<T> {
    pub fn new() -> Self {
        LookupVec {
            map: IndexMap::<T::Key, T>::new(),
        }
    }

    pub fn with_capacity(n: usize) -> Self {
        LookupVec {
            map: IndexMap::<T::Key, T>::with_capacity(n),
        }
    }
}

impl<T: Lookup, S> LookupVec<T, S> {
    pub const fn with_hasher(hasher: S) -> Self {
        LookupVec {
            map: IndexMap::with_hasher(hasher),
        }
    }

    pub fn with_capacity_and_hasher(n: usize, hasher: S) -> Self {
        LookupVec {
            map: IndexMap::with_capacity_and_hasher(n, hasher),
        }
    }
}

impl<T: Lookup, S> LookupVec<T, S> {
    delegate![
        to self.map {
            pub fn len(&self) -> usize;
            pub fn is_empty(&self) -> bool;

            pub fn move_index(&mut self, from: usize, to: usize);
            pub fn swap_indices(&mut self, a: usize, b: usize);

            pub fn reverse(&mut self);
            pub fn clear(&mut self);
            pub fn truncate(&mut self, len: usize);

            pub fn hasher(&self) -> &S;
            pub fn capacity(&self) -> usize;
            pub fn reserve(&mut self, additional: usize);
            pub fn reserve_exact(&mut self, additional: usize);
            pub fn shrink_to(&mut self, min_capacity: usize);
            pub fn shrink_to_fit(&mut self);
        }
    ];

    pub fn get_index(&self, index: usize) -> Option<&T> {
        self.map.get_index(index).map(|v| v.1)
    }

    pub fn get_index_mut(&mut self, index: usize) -> Option<&mut T> {
        self.map.get_index_mut(index).map(|v| v.1)
    }

    pub fn first(&self) -> Option<&T> {
        self.map.first().map(|v| v.1)
    }

    pub fn first_mut(&mut self) -> Option<&mut T> {
        self.map.first_mut().map(|v| v.1)
    }

    pub fn last(&self) -> Option<&T> {
        self.map.last().map(|v| v.1)
    }

    pub fn last_mut(&mut self) -> Option<&mut T> {
        self.map.last_mut().map(|v| v.1)
    }

    pub fn iter(&self) -> Iter<'_, T> {
        Iter(self.map.values())
    }
    pub fn iter_mut(&mut self) -> IterMut<'_, T> {
        IterMut(self.map.values_mut())
    }

    pub fn keys(&self) -> Keys<'_, T> {
        Keys(self.map.keys())
    }

    pub fn into_keys(self) -> IntoKeys<T> {
        IntoKeys(self.map.into_keys())
    }

    pub fn drain<R>(&mut self, range: R) -> Drain<'_, T>
    where R: RangeBounds<usize> {
        Drain(self.map.drain(range))
    }

    pub fn split_off(&mut self, at: usize) -> Self
    where S: Clone {
        LookupVec {
            map: self.map.split_off(at),
        }
    }

    pub fn shift_remove_index(&mut self, index: usize) -> Option<T> {
        self.map.shift_remove_index(index).map(|v| v.1)
    }

    pub fn swap_remove_index(&mut self, index: usize) -> Option<T> {
        self.map.swap_remove_index(index).map(|v| v.1)
    }
}

#[cfg(feature = "std")]
impl<T: Lookup, S> LookupVec<T, S>
where S: BuildHasher {
    delegate![
        to self.map {
            pub fn get<Q>(&self, key: &Q) -> Option<&T> where Q: ?Sized + Hash + Equivalent<T::Key>;
            pub fn get_mut<Q>(&mut self, key: &Q) -> Option<&mut T> where Q: ?Sized + Hash + Equivalent<T::Key>;
            pub fn get_index_of<Q>(&mut self, key: &Q) -> Option<usize> where Q: ?Sized + Hash + Equivalent<T::Key>;
            pub fn contains_key<Q>(&self, key: &Q) -> bool where Q: ?Sized + Hash + Equivalent<T::Key>;
            pub fn shift_remove<Q>(&mut self, key: &Q) -> Option<T> where Q: ?Sized + Hash + Equivalent<T::Key>;
            pub fn swap_remove<Q>(&mut self, key: &Q) -> Option<T> where Q: ?Sized + Hash + Equivalent<T::Key>;
        }
    ];

    pub fn push(&mut self, value: T) -> Option<T> {
        self.map.insert(value.key(), value)
    }

    pub fn push_full(&mut self, value: T) -> (usize, Option<T>) {
        self.map.insert_full(value.key(), value)
    }

    pub fn insert(&mut self, index: usize, value: T) -> (usize, Option<T>) {
        self.map.insert_before(index, value.key(), value)
    }

    pub fn shift_insert(&mut self, index: usize, value: T) -> Option<T> {
        self.map.shift_insert(index, value.key(), value)
    }

    pub fn pop(&mut self) -> Option<T> {
        self.map.pop().map(|v| v.1)
    }

    pub fn append<S2>(&mut self, other: &mut LookupVec<T, S2>) {
        self.map.append(&mut other.map)
    }

    pub fn contains(&self, value: &T) -> bool {
        self.map.contains_key(&value.key())
    }

}

#[cfg(feature = "std")]
impl<T: Lookup, S> LookupVec<T, S>
where S: BuildHasher, T::Key: Ord {
    pub fn sort(&mut self) {
        // We use unstable for performance since there should never be duplicate
        // keys
        self.map.sort_unstable_keys()
    }

    pub fn sort_by<F>(&mut self, mut cmp: F)
        where F: FnMut(&T, &T) -> Ordering {
        self.map.sort_by(|_, v1, _, v2| cmp(v1, v2))
    }

    pub fn sort_unstable_by<F>(&mut self, mut cmp: F)
        where F: FnMut(&T, &T) -> Ordering {
        self.map.sort_unstable_by(|_, v1, _, v2| cmp(v1, v2))
    }

    pub fn sorted(mut self) -> IntoIter<T> {
        self.sort();
        self.into_iter()
    }

    pub fn sorted_by<F>(mut self, cmp: F) -> IntoIter<T>
        where F: FnMut(&T, &T) -> Ordering {
        self.sort_by(cmp);
        self.into_iter()
    }

    pub fn sorted_unstable_by<F>(mut self, cmp: F) -> IntoIter<T>
        where F: FnMut(&T, &T) -> Ordering {
        self.sort_unstable_by(cmp);
        self.into_iter()
    }
}

impl<'a, T: Lookup, S> IntoIterator for &'a LookupVec<T, S> {
    type Item = &'a T;
    type IntoIter = Iter<'a, T>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

impl<'a, T: Lookup, S> IntoIterator for &'a mut LookupVec<T, S> {
    type Item = &'a mut T;
    type IntoIter = IterMut<'a, T>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter_mut()
    }
}

impl<T: Lookup, S> IntoIterator for LookupVec<T, S> {
    type Item = T;
    type IntoIter = IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        IntoIter(self.map.into_values())
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use lookupvec_derive::Lookup;

    #[derive(Debug, PartialEq, Lookup)]
    struct TestItem {
        #[lookup_key]
        id: String,
    }

    fn create_test_item(id: &str) -> TestItem {
        TestItem { id: id.to_string() }
    }

    #[derive(Debug, PartialEq, Lookup)]
    struct TestItemIntKey {
        #[lookup_key]
        id: u64,
    }

    fn create_test_item_int_key(id: u64) -> TestItemIntKey {
        TestItemIntKey { id: id }
    }

    #[test]
    fn test_new_and_capacity() {
        let vec = LookupVec::<TestItem>::new();
        assert!(vec.is_empty());
        assert_eq!(vec.len(), 0);

        let vec = LookupVec::<TestItem>::with_capacity(5);
        assert!(vec.capacity() >= 5);
    }

    #[test]
    fn test_int_key() {
        let mut vec = LookupVec::new();
        let item1 = create_test_item_int_key(10);
        let item2 = create_test_item_int_key(20);

        vec.push(item1);
        vec.push(item2);

        assert_eq!(vec.len(), 2);
        assert_eq!(vec.get(&10).unwrap().key(), 10);
        assert_eq!(vec.get_index(1).unwrap().key(), 20);
    }

    #[test]
    fn test_push_and_get() {
        let mut vec = LookupVec::new();
        let item1 = create_test_item("test1");
        let item2 = create_test_item("test2");

        vec.push(item1);
        vec.push(item2);

        assert_eq!(vec.len(), 2);
        assert_eq!(vec.get("test1").unwrap().key(), "test1");
        assert_eq!(vec.get_index(1).unwrap().key(), "test2");
    }

    #[test]
    fn test_insert_and_remove() {
        let mut vec = LookupVec::new();
        let item1 = create_test_item("test1");
        let item2 = create_test_item("test2");
        let item3 = create_test_item("test3");

        vec.push(item1);
        vec.push(item2);
        vec.insert(1, item3);

        assert_eq!(vec.len(), 3);
        assert_eq!(vec.get_index(1).unwrap().key(), "test3");

        let removed = vec.shift_remove("test2").unwrap();
        assert_eq!(removed.key(), "test2");
        assert_eq!(vec.len(), 2);
    }

    #[test]
    fn test_iteration() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1"));
        vec.push(create_test_item("test2"));

        let keys: Vec<String> = vec.keys().map(|k| k.to_string()).collect();
        assert_eq!(keys, vec!["test1".to_string(), "test2".to_string()]);

        let mut iter = vec.iter();
        assert_eq!(iter.next().unwrap().key(), "test1");
        assert_eq!(iter.next().unwrap().key(), "test2");
        assert!(iter.next().is_none());
    }

    #[test]
    fn test_sort() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("c"));
        vec.push(create_test_item("a"));
        vec.push(create_test_item("b"));

        vec.sort();
        
        let keys: Vec<String> = vec.keys().map(|k| k.to_string()).collect();
        assert_eq!(keys, vec!["a".to_string(), "b".to_string(), "c".to_string()]);
    }

    #[test]
    fn test_split_and_append() {
        let mut vec1 = LookupVec::new();
        vec1.push(create_test_item("test1"));
        vec1.push(create_test_item("test2"));
        vec1.push(create_test_item("test3"));

        let mut vec2 = vec1.split_off(1);
        assert_eq!(vec1.len(), 1);
        assert_eq!(vec2.len(), 2);

        vec1.append(&mut vec2);
        assert_eq!(vec1.len(), 3);
        assert_eq!(vec2.len(), 0);
    }

    #[test]
    fn test_drain() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1"));
        vec.push(create_test_item("test2"));
        vec.push(create_test_item("test3"));

        let drained: Vec<TestItem> = vec.drain(1..3).collect();
        assert_eq!(drained.len(), 2);
        assert_eq!(vec.len(), 1);
    }

    #[test]
    fn test_first_last() {
        let mut vec = LookupVec::new();
        assert!(vec.first().is_none());
        assert!(vec.last().is_none());

        vec.push(create_test_item("test1"));
        vec.push(create_test_item("test2"));

        assert_eq!(vec.first().unwrap().key(), "test1");
        assert_eq!(vec.last().unwrap().key(), "test2");
    }

    #[test]
    fn test_index_operations() {
        let mut vec = LookupVec::new();
        vec.push(create_test_item("test1"));
        vec.push(create_test_item("test2"));
        vec.push(create_test_item("test3"));

        vec.move_index(0, 2);
        assert_eq!(vec.get_index(2).unwrap().key(), "test1");

        vec.swap_indices(0, 1);
        assert_eq!(vec.get_index(0).unwrap().key(), "test3");
        assert_eq!(vec.get_index(1).unwrap().key(), "test2");
    }
}