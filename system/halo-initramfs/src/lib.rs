//! halo-initramfs: first userspace.
//!
//! Finds the root device named on the kernel command line, mounts it
//! read-only, moves the early mounts into it and executes the real init
//! there (`switch_root`). dm-verity and `/data` unlocking come later
//! (ARCHITECTURE §3).

use thiserror::Error;

/// Where the root filesystem is and what to run in it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootParams {
    /// Device node, from `root=` (`/dev/vda`).
    pub root: String,
    /// Filesystem type, from `rootfstype=`. Defaults to `erofs`.
    pub fstype: String,
    /// Init to execute in the new root, from `init=`. Defaults to
    /// `/sbin/haloinit`.
    pub init: String,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ParseError {
    #[error("no root= on the kernel command line")]
    MissingRoot,
    #[error("root= must be a device path starting with /dev/, got {0:?}")]
    BadRoot(String),
    #[error("init= must be an absolute path, got {0:?}")]
    BadInit(String),
}

pub const DEFAULT_FSTYPE: &str = "erofs";
pub const DEFAULT_INIT: &str = "/sbin/haloinit";

impl BootParams {
    /// Parse the kernel command line. The last occurrence of a key wins,
    /// like the kernel's own parameters.
    pub fn parse(cmdline: &str) -> Result<Self, ParseError> {
        let mut root = None;
        let mut fstype = None;
        let mut init = None;
        for word in cmdline.split_whitespace() {
            if let Some(v) = word.strip_prefix("root=") {
                root = Some(v);
            } else if let Some(v) = word.strip_prefix("rootfstype=") {
                fstype = Some(v);
            } else if let Some(v) = word.strip_prefix("init=") {
                init = Some(v);
            }
        }
        let root = root.ok_or(ParseError::MissingRoot)?;
        if !root.starts_with("/dev/") || root.len() <= "/dev/".len() {
            return Err(ParseError::BadRoot(root.to_string()));
        }
        let init = init.unwrap_or(DEFAULT_INIT);
        if !init.starts_with('/') {
            return Err(ParseError::BadInit(init.to_string()));
        }
        Ok(Self {
            root: root.to_string(),
            fstype: fstype.unwrap_or(DEFAULT_FSTYPE).to_string(),
            init: init.to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_qemu_command_line() {
        let p =
            BootParams::parse("console=ttyAMA0 root=/dev/vda rootfstype=erofs ro halo.test=boot")
                .unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(p.root, "/dev/vda");
        assert_eq!(p.fstype, "erofs");
        assert_eq!(p.init, "/sbin/haloinit");
    }

    #[test]
    fn defaults_apply() {
        let p = BootParams::parse("root=/dev/vda").unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(p.fstype, DEFAULT_FSTYPE);
        assert_eq!(p.init, DEFAULT_INIT);
    }

    #[test]
    fn init_can_be_overridden() {
        let p = BootParams::parse("root=/dev/vda init=/bin/sh").unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(p.init, "/bin/sh");
    }

    #[test]
    fn the_last_occurrence_wins() {
        let p = BootParams::parse("root=/dev/vda root=/dev/vdb").unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(p.root, "/dev/vdb");
    }

    #[test]
    fn missing_root_is_an_error() {
        assert_eq!(
            BootParams::parse("console=ttyAMA0"),
            Err(ParseError::MissingRoot)
        );
        assert_eq!(BootParams::parse(""), Err(ParseError::MissingRoot));
    }

    #[test]
    fn root_must_be_a_device_path() {
        for bad in ["root=vda", "root=/dev/", "root=/tmp/x", "root=UUID=abc"] {
            assert!(
                matches!(BootParams::parse(bad), Err(ParseError::BadRoot(_))),
                "{bad}"
            );
        }
    }

    #[test]
    fn init_must_be_absolute() {
        assert!(matches!(
            BootParams::parse("root=/dev/vda init=sbin/haloinit"),
            Err(ParseError::BadInit(_))
        ));
    }

    #[test]
    fn keys_are_matched_whole() {
        // "xroot=" must not count as "root=".
        assert_eq!(
            BootParams::parse("xroot=/dev/vda"),
            Err(ParseError::MissingRoot)
        );
    }

    #[test]
    fn newline_and_extra_spaces_are_fine() {
        let p = BootParams::parse("  root=/dev/vda\n").unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(p.root, "/dev/vda");
    }
}
