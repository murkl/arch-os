//! Terminal interface for the embedded modules: settings, answers, task runs, failure reports.
//! Nothing OS-specific is compiled in. The product is `product.yaml`, `lib.sh` and the module
//! folders.

pub mod cli;
pub mod i18n;
pub mod log;
pub mod script;
mod signals;
pub mod spec;
pub mod store;
mod term;
mod trace;
mod ui;
mod unattended;
pub mod version;

/// Every product file, keyed by its path relative to the product.
pub mod embedded {
    include!(concat!(env!("OUT_DIR"), "/embedded.rs"));
}
