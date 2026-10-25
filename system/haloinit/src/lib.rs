//! haloinit: Halo OS PID 1.
//!
//! First slice: mount `/proc`, read the kernel command line, report which
//! filesystem it runs from, and power off when asked to (`halo.test=boot`). Unit files, supervision and reaping
//! arrive later in Phase 1.

/// Name reported in logs.
pub const NAME: &str = "haloinit";

/// Command-line flag that makes the boot test power off after a good boot.
pub const FLAG_TEST_BOOT: &str = "halo.test=boot";

/// Whether `flag` appears as a whole word on the kernel command line.
pub fn cmdline_has(cmdline: &str, flag: &str) -> bool {
    cmdline.split_whitespace().any(|word| word == flag)
}

/// Filesystem type of `/` from the contents of `/proc/mounts`, if listed.
///
/// In the initramfs this is `rootfs`; after switching to the image it is the
/// image's type (`erofs`), which is how the boot test knows it ran from disk.
pub fn root_fstype(mounts: &str) -> Option<&str> {
    mounts.lines().find_map(|line| {
        let mut f = line.split_whitespace();
        let (_device, mountpoint, fstype) = (f.next()?, f.next()?, f.next()?);
        (mountpoint == "/").then_some(fstype)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn name_is_stable() {
        assert_eq!(NAME, "haloinit");
    }

    #[test]
    fn cmdline_matches_whole_words_only() {
        let cmdline = "console=ttyAMA0 halo.test=boot quiet";
        assert!(cmdline_has(cmdline, FLAG_TEST_BOOT));
        assert!(cmdline_has(cmdline, "quiet"));
        assert!(!cmdline_has(cmdline, "halo.test"));
        assert!(!cmdline_has("xhalo.test=boot", FLAG_TEST_BOOT));
        assert!(!cmdline_has("", FLAG_TEST_BOOT));
    }

    #[test]
    fn cmdline_tolerates_newline_and_extra_spaces() {
        assert!(cmdline_has("a  halo.test=boot\n", FLAG_TEST_BOOT));
    }

    #[test]
    fn root_fstype_finds_the_slash_mount() {
        let mounts = "rootfs / rootfs rw 0 0\nproc /proc proc rw 0 0\n";
        assert_eq!(root_fstype(mounts), Some("rootfs"));
        let after = "/dev/root / erofs ro,relatime 0 0\nproc /proc proc rw 0 0\n";
        assert_eq!(root_fstype(after), Some("erofs"));
    }

    #[test]
    fn root_fstype_ignores_other_mounts_and_junk() {
        assert_eq!(root_fstype("proc /proc proc rw 0 0\n"), None);
        assert_eq!(root_fstype("/ only-two\n"), None);
        assert_eq!(root_fstype(""), None);
        // A mountpoint that merely starts with "/" is not the root.
        assert_eq!(root_fstype("tmpfs /run tmpfs rw 0 0\n"), None);
    }
}
