//! The runtime: an interface for the modules embedded beside it. It asks, keeps the answers,
//! runs their shell in order and reports where it broke. Nothing about an operating system is
//! compiled in: the product is `product.yaml`, `lib.sh` and the module folders.

pub mod cli;
pub mod i18n;
pub mod log;
pub mod script;
pub mod spec;
pub mod store;
mod term;
mod ui;
pub mod version;

/// The product as the build embedded it: every file by its path relative to the product.
pub mod embedded {
    include!(concat!(env!("OUT_DIR"), "/embedded.rs"));
}
