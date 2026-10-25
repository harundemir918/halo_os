//! Thin, safe wrappers over the Linux syscalls early boot needs.
//!
//! Linux only: on other hosts the crate is empty, so the workspace still
//! builds and tests on macOS.

#[cfg(target_os = "linux")]
mod linux;

#[cfg(target_os = "linux")]
pub use linux::*;
