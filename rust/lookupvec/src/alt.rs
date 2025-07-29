// Attempt at making a version of LookupVec that accepts a key
// function as a parameter, so that the Lookup trait doesn't
// have to be derived, or alternate keys can be used.
//
// This would be much better accomplished with const generics,
// but those are limited by
// https://github.com/rust-lang/rust/issues/98210.
//
// With the approach here, the key function must be supplied at
// runtime, which makes construction through stuff like serde
// and builders awkward.
//
// It also doesn't compile bc I can't get the generic parameters
// for the key function working correctly ¯\_(ツ)_/¯
//
use crate::core::Lookup;

use indexmap::IndexMap;

use core::hash::Hash;
use std::hash::RandomState;

#[cfg(feature = "std")]
#[derive(Debug, Clone)]
struct LookupVecAlt<K, V, F, S = RandomState>
where
    K: Hash + Eq + Clone,
    F: Fn(&V) -> K,
{
    map: IndexMap<K, V, S>,
    key_fn: F,
}

#[cfg(feature = "std")]
impl<K, V, F> LookupVecAlt<K, V, F>
where
    V: Lookup<Key = K>,
    K: Hash + Eq + Clone,
    F: Fn(&V) -> K,
{
    pub fn with_key(key_fn: F) -> Self {
        LookupVecAlt {
            map: IndexMap::<K, V>::new(),
            key_fn: key_fn,
        }
    }
}

#[cfg(feature = "std")]
impl<K, V, F> LookupVecAlt<K, V, F>
where
    V: Lookup<Key = K>,
    K: Hash + Eq + Clone,
    //F: for<'a> Fn(&'a V) -> <V as Lookup>::Key,
{
    pub fn new() -> Self {
        LookupVecAlt::<K, V, F>::with_key::(V::key)
    }
}
