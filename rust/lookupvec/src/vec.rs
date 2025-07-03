use crate::core::Lookup;
use crate::iter::*;
//use crate::slice::Slice;

use delegate::delegate;
use indexmap::IndexMap;
use indexmap::Equivalent;
//use ref_cast::RefCast;

use core::cmp::Ordering;
use core::hash::BuildHasher;
use core::hash::Hash;
use core::ops::Index;
use core::ops::IndexMut;
use core::ops::RangeBounds;
#[cfg(feature = "std")]
use std::hash::RandomState;

#[cfg(feature = "std")]
#[derive(Debug, Clone)]
pub struct LookupVec<T: Lookup, S = RandomState> {
    map: IndexMap<T::Key, T, S>,
}

#[cfg(not(feature = "std"))]
#[derive(Debug, Clone)]
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

impl<T: Lookup, S> FromIterator<T> for LookupVec<T, S>
where S: BuildHasher + Default {
    fn from_iter<I: IntoIterator<Item = T>>(iterable: I) -> Self {
        let iter = iterable.into_iter();
        let (low, _) = iter.size_hint();
        let mut vec = Self::with_capacity_and_hasher(low, <_>::default());
        vec.extend(iter);
        vec
    }
}

#[cfg(feature = "std")]
impl<T: Lookup, const N: usize> From<[T; N]> for LookupVec<T, RandomState> {
    fn from(arr: [T; N]) -> Self {
        Self::from_iter(arr)
    }
}

impl<T: Lookup> Default for LookupVec<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T: Lookup, S> Extend<T> for LookupVec<T, S>
where S: BuildHasher {
    fn extend<I: IntoIterator<Item = T>>(&mut self, iterable: I) {
        // (Note: this is a copy of `std`/`hashbrown`'s reservation logic.)
        // Keys may be already present or show multiple times in the iterator.
        // Reserve the entire hint lower bound if the map is empty.
        // Otherwise reserve half the hint (rounded up), so the map
        // will only resize twice in the worst case.
        let iter = iterable.into_iter();
        let reserve = if self.is_empty() {
            iter.size_hint().0
        } else {
            (iter.size_hint().0 + 1) / 2
        };
        self.reserve(reserve);
        iter.for_each(move |t| {
            self.push(t);
        });
    }
}

impl<'a, T, S> Extend<&'a T> for LookupVec<T, S>
where
    T: Lookup + Copy,
    S: BuildHasher,
{
    /// Extend the map with all items pairs in the iterable.
    ///
    /// See the first extend method for more details.
    fn extend<I: IntoIterator<Item = &'a T>>(&mut self, iterable: I) {
        self.extend(iterable.into_iter().map(|&item| item));
    }
}

impl<T: Lookup, S> Index<usize> for LookupVec<T, S> {
    type Output = T;

    /// Returns a reference to the value at the supplied `index`.
    ///
    /// ***Panics*** if `index` is out of bounds.
    fn index(&self, index: usize) -> &T {
        self.get_index(index)
            .unwrap_or_else(|| {
                panic!(
                    "index out of bounds: the len is {len} but the index is {index}",
                    len = self.len()
                );
            })
    }
}

impl<T: Lookup, S> IndexMut<usize> for LookupVec<T, S> {
    /// Returns a mutable reference to the value at the supplied `index`.
    ///
    /// ***Panics*** if `index` is out of bounds.
    fn index_mut(&mut self, index: usize) -> &mut T {
        let len: usize = self.len();
        self.get_index_mut(index)
            .unwrap_or_else(|| {
                panic!("index out of bounds: the len is {len} but the index is {index}");
            })
    }
}

// This conflicts with the impl for usize. To get this behavior, we need to impl
// Index for each of the standard ranges, like indexmap does (see
// https://docs.rs/indexmap/2.7.1/src/indexmap/map/slice.rs.html#382-424).
//
//impl<I: RangeBounds<usize>, T: Lookup, S> Index<I> for LookupVec<T, S> {
//    type Output = Slice<T>;
//
//    fn index(&self, index: I) -> &Slice<T> {
//        Slice::<T>::ref_cast(self.map.index((index.start_bound().cloned(), index.end_bound().cloned())))
//    }
//}

#[cfg(test)]
mod tests {
    use super::*;
    use lookupvec_derive::Lookup;

    #[derive(Debug, PartialEq, Lookup)]
    struct TestItem {
        #[lookup_key]
        id: String,
    }

    fn item1() -> TestItem { TestItem { id: "item1".to_owned() } }
    fn item2() -> TestItem { TestItem { id: "item2".to_owned() } }
    fn item3() -> TestItem { TestItem { id: "item3".to_owned() } }

    #[derive(Debug, PartialEq, Lookup)]
    struct TestItemIntKey {
        #[lookup_key]
        id: u64,
    }

    macro_rules! assert_keys_eq {
        ($vec:expr, $($key:expr),+) => {
            assert_eq!($vec.keys().collect::<Vec<&String>>(), vec![$($key),+]);
        };
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
    fn test_push_and_get() {
        let mut vec = LookupVec::new();
        vec.push(item1());
        vec.push(item2());

        assert_eq!(vec.len(), 2);
        assert_eq!(vec.get("item1").unwrap().id, "item1");
        assert_eq!(vec.get_index(1).unwrap().id, "item2");
    }

    #[test]
    fn test_int_key() {
        let vec = lookupvec![
            TestItemIntKey { id: 10 },
            TestItemIntKey { id: 20 },
        ];

        assert_eq!(vec.len(), 2);
        assert_eq!(vec.get(&10).unwrap().id, 10);
        assert_eq!(vec.get_index(1).unwrap().id, 20);
    }

    #[test]
    fn test_insert_and_remove() {
        let mut vec = lookupvec![
            item1(),
            item2(),
        ];

        vec.insert(1, item3());
        assert_keys_eq!(sorted, "item1", "item3", "item2");

        let removed = vec.shift_remove("item2").unwrap();
        assert_eq!(removed.id, "item2");
        assert_eq!(vec.len(), 2);

        vec.shift_insert(1, item3());
        assert_keys_eq!(sorted, "item1", "item3", "item2");

    }

    #[test]
    fn test_iteration() {
        let vec = lookupvec![
            item1(),
            item2(),
        ];

        let keys: Vec<&String> = vec.keys().collect();
        assert_eq!(keys, vec!["item1", "item2"]);

        let mut iter = vec.iter();
        assert_eq!(iter.next().unwrap().id, "item1");
        assert_eq!(iter.next().unwrap().id, "item2");
        assert!(iter.next().is_none());
    }

    #[test]
    fn test_split_and_append() {
        let mut vec1 = lookupvec![
            item1(),
            item2(),
            item3(),
        ];

        let mut vec2 = vec1.split_off(1);
        assert_keys_eq!(vec1, "item1");
        assert_keys_eq!(vec2, "item2", "item3");

        vec1.append(&mut vec2);
        assert_keys_eq!(vec1, "item1", "item2", "item3");
        assert_eq!(vec2.len(), 0);
    }

    #[test]
    fn test_drain() {
        let mut vec = lookupvec![
            item1(),
            item2(),
            item3(),
        ];

        let drained: LookupVec<TestItem> = vec.drain(1..3).collect();
        assert_keys_eq!(vec, "item1");
        assert_keys_eq!(drained, "item2", "item3");
    }

    #[test]
    fn test_first_last() {
        let mut vec = LookupVec::new();
        assert!(vec.first().is_none());
        assert!(vec.last().is_none());

        vec.push(item1());
        vec.push(item2());

        assert_eq!(vec.first().unwrap().id, "item1");
        assert_eq!(vec.last().unwrap().id, "item2");
    }

    #[test]
    fn test_index_operations() {
        let mut vec = lookupvec![
            item1(),
            item2(),
            item3(),
        ];

        vec.move_index(0, 2);
        assert_keys_eq!(vec, "item2", "item3", "item1");

        vec.swap_indices(0, 1);
        assert_keys_eq!(vec, "item3", "item2", "item1");
    }

    #[test]
    fn test_from_array() {
        let arr = [
            item1(),
            item2(),
            item3(),
        ];
        let vec = LookupVec::from(arr);
        assert_keys_eq!(vec, "item1", "item2", "item3");
    }

    #[test]
    fn test_extend() {
        let mut vec = lookupvec![
            item1(),
        ];

        let items = vec![
            item2(),
            item3(),
        ];
        vec.extend(items);

        assert_keys_eq!(vec, "item1", "item2", "item3");
    }

    //#[test]
    //fn test_extend_refs() {
    //    let mut vec = LookupVec::new();
    //    let item1 = item1();
    //    let item2 = item2();
    //    let refs = vec![&item1, &item2];

    //    vec.extend(refs);
    //    assert_eq!(vec.len(), 2);
    //    assert_eq!(vec.get_index(0).unwrap().id, "item1");
    //    assert_eq!(vec.get_index(1).unwrap().id, "item2");
    //}

    #[test]
    fn test_sort() {
        let mut vec = lookupvec![
            item3(),
            item1(),
            item2(),
        ];

        vec.sort();
        assert_keys_eq!(vec, "item1", "item2", "item3");

        vec.sort_by(|a, b| b.id.cmp(&a.id));
        assert_keys_eq!(vec, "item3", "item2", "item1");

        vec.sort_unstable_by(|a, b| a.id.cmp(&b.id));
        assert_keys_eq!(vec, "item1", "item2", "item3");
    }

    #[test]
    fn test_sorted() {
        let vec = lookupvec![
            item3(),
            item1(),
            item2(),
        ];

        let sorted: LookupVec<_> = vec.clone().sorted().collect();
        assert_keys_eq!(sorted, "item1", "item2", "item3");

        let sorted_by: LookupVec<_> = vec.clone().sorted_by(|a, b| b.id.cmp(&a.id)).collect();
        assert_keys_eq!(sorted_by, "item3", "item2", "item1");

        let sorted_unstable: LookupVec<_> = vec.sorted_unstable_by(|a, b| b.id.cmp(&a.id)).collect();
        assert_keys_eq!(sorted_unstable_by, "item3", "item2", "item1");
    }

    #[test]
    fn test_capacity_management() {
        let mut vec = LookupVec::with_capacity(10);
        assert!(vec.capacity() >= 10);

        vec.reserve(5);
        vec.reserve_exact(5);

        vec.push(item1());
        vec.push(item2());

        vec.shrink_to(5);
        assert!(vec.capacity() >= 5);

        vec.shrink_to_fit();
        assert!(vec.capacity() >= 2);
    }

    #[test]
    fn test_index() {
        let mut vec = lookupvec![
            item1(),
            item2(),
        ];

        // Test immutable indexing
        let item = &vec[1];
        assert_eq!(item.id, "item2");

        // Test mutable indexing
        let item_mut = &mut vec[0];
        assert_eq!(item_mut.id, "item1");

        item_mut.id = "foo".to_owned();
        assert_eq!(vec[0].id, "foo");
    }
}