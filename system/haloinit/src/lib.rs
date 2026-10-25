//! haloinit: Halo OS PID 1.
//!
//! Placeholder. The unit format, supervision and shutdown arrive in Phase 1.

/// Name reported in logs.
pub const NAME: &str = "haloinit";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn name_is_stable() {
        assert_eq!(NAME, "haloinit");
    }
}
