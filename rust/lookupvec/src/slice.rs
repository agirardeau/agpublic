// This code is currently unused. A `Slice` struct that wraps
// `indexmap::map::Slice` would enable implementing Index for range types on
// LookupVec.
use crate::core::Lookup;
//use crate::iter::*;

use indexmap::map::Slice as InnerSlice;
use ref_cast::RefCast;

use std::ops::Index;
use std::ops::RangeBounds;

#[derive(RefCast)]
#[repr(transparent)]
pub struct Slice<T: Lookup> ( InnerSlice<T::Key, T> );

impl<I: RangeBounds<usize>, T: Lookup> Index<I> for Slice<T> {
    type Output = Slice<T>;

    fn index(&self, index: I) -> &Slice<T> {
        Slice::<T>::ref_cast(self.0.index((index.start_bound().cloned(), index.end_bound().cloned())))
    }
}
