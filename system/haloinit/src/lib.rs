//! haloinit: Halo OS PID 1.
//!
//! First slice: mount `/proc`, read the kernel command line, and power off
//! when asked to (`halo.test=boot`). Unit files, supervision and reaping
//! arrive later in Phase 1.

/// Name reported in logs.
pub const NAME: &str = "haloinit";

/// Command-line flag that makes the boot test power off after a good boot.
pub const FLAG_TEST_BOOT: &str = "halo.test=boot";

/// Whether `flag` appears as a whole word on the kernel command line.
pub fn cmdline_has(cmdline: &str, flag: &str) -> bool {
    cmdline.split_whitespace().any(|word| word == flag)
}

#[cfg(target_os = "linux")]
pub mod sys {
    //! Thin, safe wrappers over the syscalls PID 1 needs.

    use std::ffi::CString;
    use std::io;
    use std::ptr;

    /// Mount a filesystem of type `fstype` at `target`.
    pub fn mount(source: &str, target: &str, fstype: &str) -> io::Result<()> {
        let source = CString::new(source)?;
        let target = CString::new(target)?;
        let fstype = CString::new(fstype)?;
        // SAFETY: all three pointers come from live CStrings that outlive the
        // call, and the data pointer is allowed to be null.
        let rc = unsafe {
            libc::mount(
                source.as_ptr(),
                target.as_ptr(),
                fstype.as_ptr(),
                0,
                ptr::null(),
            )
        };
        if rc == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }

    /// Flush filesystems and power the machine off. Only returns on failure.
    pub fn poweroff() -> io::Error {
        // SAFETY: `sync` takes no arguments. `reboot` with RB_POWER_OFF takes
        // no pointers, and on success it does not return.
        unsafe {
            libc::sync();
            libc::reboot(libc::RB_POWER_OFF);
        }
        io::Error::last_os_error()
    }
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
}
