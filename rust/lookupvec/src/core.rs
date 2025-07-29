use std::fmt::Debug;
use std::hash::Hash;
use std::ops::Deref;

pub trait Lookup {
    type Key: Hash + Eq + Clone + Debug;
    fn key(&self) -> Self::Key;
}

#[cfg(feature = "std")]
impl<T, R> Lookup for R
where
    R: Deref<Target = T>,
    T: Lookup
{
    type Key = T::Key;
    fn key(&self) -> Self::Key {
        self.deref().key()
    }
}