use crate::core::Lookup;

use core::iter::FusedIterator;

use delegate::delegate;

pub struct Iter<'a, T: Lookup> (pub(crate) indexmap::map::Values<'a, T::Key, T>);
impl<'a, T: Lookup> Iterator for Iter<'a, T> {
    type Item = &'a T;

    delegate![
        to self.0 {
            fn next(&mut self) -> Option<&'a T>;
            fn last(self) -> Option<&'a T>;
            fn nth(&mut self, n: usize) -> Option<&'a T>;
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<'a, T: Lookup> DoubleEndedIterator for Iter<'a, T> {
    delegate![
        to self.0 {
            fn next_back(&mut self) -> Option<&'a T>;
            fn nth_back(&mut self, n: usize) -> Option<&'a T>;
        }
    ];
}
impl<T: Lookup> ExactSizeIterator for Iter<'_, T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for Iter<'_, T> {}


pub struct IterMut<'a, T: Lookup> (pub(crate) indexmap::map::ValuesMut<'a, T::Key, T>);
impl<'a, T: Lookup> Iterator for IterMut<'a, T> {
    type Item = &'a mut T;

    delegate![
        to self.0 {
            fn next(&mut self) -> Option<&'a mut T>;
            fn last(self) -> Option<&'a mut T>;
            fn nth(&mut self, n: usize) -> Option<&'a mut T>;
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<'a, T: Lookup> DoubleEndedIterator for IterMut<'a, T> {
    delegate![
        to self.0 {
            fn next_back(&mut self) -> Option<&'a mut T>;
            fn nth_back(&mut self, n: usize) -> Option<&'a mut T>;
        }
    ];
}
impl<T: Lookup> ExactSizeIterator for IterMut<'_, T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for IterMut<'_, T> {}

pub struct IntoIter<T: Lookup> (pub(crate) indexmap::map::IntoValues<T::Key, T>);
impl<T: Lookup> Iterator for IntoIter<T> {
    type Item = T;

    delegate![
        to self.0 {
            fn next(&mut self) -> Option<T>;
            fn last(self) -> Option<T>;
            fn nth(&mut self, n: usize) -> Option<T>;
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<T: Lookup> DoubleEndedIterator for IntoIter<T> {
    delegate![
        to self.0 {
            fn next_back(&mut self) -> Option<T>;
            fn nth_back(&mut self, n: usize) -> Option<T>;
        }
    ];
}
impl<T: Lookup> ExactSizeIterator for IntoIter<T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for IntoIter<T> {}


pub struct Keys<'a, T: Lookup> (pub(crate) indexmap::map::Keys<'a, T::Key, T>);
impl<'a, T: Lookup> Iterator for Keys<'a, T> {
    type Item = &'a T::Key;

    delegate![
        to self.0 {
            fn next(&mut self) -> Option<&'a T::Key>;
            fn last(self) -> Option<&'a T::Key>;
            fn nth(&mut self, n: usize) -> Option<&'a T::Key>;
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<'a, T: Lookup> DoubleEndedIterator for Keys<'a, T> {
    delegate![
        to self.0 {
            fn next_back(&mut self) -> Option<&'a T::Key>;
            fn nth_back(&mut self, n: usize) -> Option<&'a T::Key>;
        }
    ];
}
impl<T: Lookup> ExactSizeIterator for Keys<'_, T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for Keys<'_, T> {}

pub struct IntoKeys<T: Lookup> (pub(crate) indexmap::map::IntoKeys<T::Key, T>);
impl<T: Lookup> Iterator for IntoKeys<T> {
    type Item = T::Key;

    delegate![
        to self.0 {
            fn next(&mut self) -> Option<T::Key>;
            fn last(self) -> Option<T::Key>;
            fn nth(&mut self, n: usize) -> Option<T::Key>;
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<T: Lookup> DoubleEndedIterator for IntoKeys<T> {
    delegate![
        to self.0 {
            fn next_back(&mut self) -> Option<T::Key>;
            fn nth_back(&mut self, n: usize) -> Option<T::Key>;
        }
    ];
}
impl<T: Lookup> ExactSizeIterator for IntoKeys<T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for IntoKeys<T> {}

pub struct Drain<'a, T: Lookup> (pub(crate) indexmap::map::Drain<'a, T::Key, T>);
impl<T: Lookup> Iterator for Drain<'_, T> {
    type Item = T;

    fn next(&mut self) -> Option<Self::Item> {
        self.0.next().map(|item| item.1)
    }
    fn last(self) -> Option<Self::Item> {
        self.0.last().map(|item| item.1)
    }
    fn nth(&mut self, n: usize) -> Option<Self::Item> {
        self.0.nth(n).map(|item| item.1)
    }

    delegate![
        to self.0 {
            fn size_hint(&self) -> (usize, Option<usize>);
            fn count(self) -> usize;
        }
    ];
}
impl<T: Lookup> DoubleEndedIterator for Drain<'_, T> {
    fn next_back(&mut self) -> Option<Self::Item> {
        self.0.next_back().map(|item| item.1)
    }
    fn nth_back(&mut self, n: usize) -> Option<Self::Item> {
        self.0.nth_back(n).map(|item| item.1)
    }
}
impl<T: Lookup> ExactSizeIterator for Drain<'_, T> {
    fn len(&self) -> usize { self.0.len() }
}
impl<T: Lookup> FusedIterator for Drain<'_, T> {}
