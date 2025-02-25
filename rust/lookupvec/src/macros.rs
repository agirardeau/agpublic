#[cfg(feature = "std")]
#[macro_export]
macro_rules! lookupvec {
    ($($item:expr,)+) => { $crate::lookupvec!($($item),+) };
    ($($item:expr),*) => {
        {
            // Note: `stringify!($item)` is just here to consume the repetition,
            // but we throw away that string literal during constant evaluation.
            const CAP: usize = <[()]>::len(&[$({ stringify!($item); }),*]);
            let mut vec = $crate::LookupVec::with_capacity(CAP);
            $(
                vec.push($item);
            )*
            vec
        }
    };
}