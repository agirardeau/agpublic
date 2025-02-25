use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput, Data, Fields, Type, Error};

#[proc_macro_derive(Lookup, attributes(lookup_key))]
pub fn derive_lookup(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = input.ident;

    match validate_and_get_key_field(&input.data) {
        Ok((key_field, key_type)) => {
            let expanded = quote! {
                impl Lookup for #name {
                    type Key = #key_type;
                    
                    fn key(&self) -> Self::Key {
                        self.#key_field.clone()
                    }
                }
            };
            TokenStream::from(expanded)
        }
        Err(err) => err.to_compile_error().into(),
    }
}

fn validate_and_get_key_field(data: &Data) -> Result<(syn::Ident, Type), Error> {
    match data {
        Data::Struct(data_struct) => {
            match &data_struct.fields {
                Fields::Named(fields) => {
                    let key_fields: Vec<_> = fields.named.iter()
                        .filter(|field| {
                            field.attrs.iter()
                                .any(|attr| attr.path().is_ident("lookup_key"))
                        })
                        .collect();

                    match key_fields.len() {
                        0 => Err(Error::new_spanned(
                            fields,
                            "struct must have exactly one field marked with #[lookup_key]"
                        )),
                        1 => Ok((
                            key_fields[0].ident.clone().unwrap(),
                            key_fields[0].ty.clone()
                        )),
                        _ => Err(Error::new_spanned(
                            fields,
                            "multiple #[lookup_key] attributes found, only one is allowed"
                        )),
                    }
                },
                _ => Err(Error::new_spanned(
                    data_struct.struct_token,
                    "only named fields are supported"
                )),
            }
        },
        Data::Enum(data_enum) => Err(Error::new_spanned(
            data_enum.enum_token,
            "Lookup can only be derived for structs"
        )),
        Data::Union(data_union) => Err(Error::new_spanned(
            data_union.union_token,
            "Lookup can only be derived for structs"
        )),
    }
}
