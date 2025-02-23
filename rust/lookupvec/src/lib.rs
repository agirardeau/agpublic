// Trait impls:
//  To do:
//      IntoDeserializer<'de, E>
//      FromIterator<T>
//  Would be nice:
//      Extend<&'a T)>
//      Extend<T>
//      From<[T; N]>
//  Maybe:
//      Index<&Q>
//      Index<(Bound<usize>, Bound<usize>)>
//      Index<Range<usize>>
//      Index<RangeFrom<usize>>
//      Index<RangeFull>
//      Index<RangeInclusive<usize>>
//      Index<RangeTo<usize>>
//      Index<RangeToInclusive<usize>>
//      Index<usize>
//      IndexMut<&Q>
//      IndexMut<(Bound<usize>, Bound<usize>)>
//      IndexMut<Range<usize>>
//      IndexMut<RangeFrom<usize>>
//      IndexMut<RangeFull>
//      IndexMut<RangeInclusive<usize>>
//      IndexMut<RangeTo<usize>>
//      IndexMut<RangeToInclusive<usize>>
//      IndexMut<usize>
//  Nah:
//      Arbitrary
//      Arbitrary<'a>
//      BorshDeserialize
//      BorshSerialize
//      FromParallelIterator<(K, V)>
//      IntoParallelIterator
//      MutableKeys
//      ParallelDrainRange
//      ParallelExtend<(&'a K, &'a V)>
//      ParallelExtend<(K, V)>
//      RawEntryApiV1<K, V, S>
//
// Methods:
//  Maybe:
//      as_slice()
//      as_mut_slice()
//      into_boxed_slice()
//      binary_search_by()
//      binary_search_by_key()
//      binary_search_keys()
//      get_range()
//      get_range_mut()
//      insert_sorted()
//      shift_insert()
//      retain()
//  Nah:
//      entry()
//      first_entry()
//      last_entry()
//      get_index_entry()
//      get_full(&self, key: &str) -> Option<(usize, &str, &T)>;
//      get_full_mut(&mut self, key: &str) -> Option<(usize, &str, &mut T)>;
//      partition_point()
//      sort_unstable_by()
//      sort_unstable_keys()
//      sorted_unstable_by()
//      sort_by_cached_key()
//      shift_remove_entry()
//      shift_remove_full()
//      swap_remove_entry()
//      swap_remove_full()
//      try_reserve()
//      try_reserve_exact()
//      rayon:
//          par_keys()
//          par_values()
//          par_eq()
//          par_values_mut()
//          par_*
//

pub mod core;
pub mod iter;
#[cfg(feature = "serde")]
pub mod serde;
pub mod vec;

pub use core::Lookup;
pub use vec::LookupVec;
