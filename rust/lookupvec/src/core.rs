use core::fmt::Debug;
use core::hash::Hash;
use core::ops::Deref;

pub trait Lookup {
    type Key: Hash + Eq + Clone + Debug;
    fn key(&self) -> Self::Key;
}

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