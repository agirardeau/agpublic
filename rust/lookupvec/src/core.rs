use std::hash::Hash;

pub trait Lookup {
    type Key: Hash + Eq + Clone;
    fn key(&self) -> Self::Key;
}
