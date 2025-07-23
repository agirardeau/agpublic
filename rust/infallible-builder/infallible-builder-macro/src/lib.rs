
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput};

#[allow(non_snake_case)]
#[proc_macro_attribute]
pub fn Builder(_attrs: TokenStream, item: TokenStream) -> TokenStream {
    let item = parse_macro_input!(item as DeriveInput);
    let name = item.ident.clone();
    let builder_name = quote::format_ident!("{name}Builder");

    TokenStream::from(quote! {
        #[derive(infallible_builder::derive_builder::Builder)]
        #[builder(
            default,
            pattern = "owned",
            crate = "infallible_builder::derive_builder",
            build_fn(private, name = "build_fallible", error = "std::convert::Infallible"),
            setter(into, strip_option),
        )]
        #item

        impl #name {
            pub fn builder() -> #builder_name {
                #builder_name::default()
            }
        }

        impl #builder_name {
            pub fn build(self) -> #name {
                use infallible_builder::UnwrapInfallible;
                self.build_fallible().unwrap_infallible()
            }
        }
    })
}
