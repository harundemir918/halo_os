use std::ffi::CString;
use std::io;
use std::path::Path;
use std::ptr;
use std::time::{Duration, Instant};

/// Mount flag: read-only.
pub const RDONLY: libc::c_ulong = libc::MS_RDONLY;

/// errno: device or resource busy (already mounted).
pub const EBUSY: i32 = libc::EBUSY;

/// Mount a filesystem of type `fstype` from `source` at `target`.
pub fn mount(source: &str, target: &str, fstype: &str, flags: libc::c_ulong) -> io::Result<()> {
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
            flags,
            ptr::null(),
        )
    };
    check(rc)
}

/// Move the mount at `source` to `target`.
pub fn mount_move(source: &str, target: &str) -> io::Result<()> {
    let source = CString::new(source)?;
    let target = CString::new(target)?;
    // SAFETY: both pointers come from live CStrings. For MS_MOVE the
    // filesystem type and data arguments are ignored and may be null.
    let rc = unsafe {
        libc::mount(
            source.as_ptr(),
            target.as_ptr(),
            ptr::null(),
            libc::MS_MOVE,
            ptr::null(),
        )
    };
    check(rc)
}

/// Change the root directory of this process to `path`.
pub fn chroot(path: &str) -> io::Result<()> {
    let path = CString::new(path)?;
    // SAFETY: the pointer comes from a live CString.
    let rc = unsafe { libc::chroot(path.as_ptr()) };
    check(rc)
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

/// Wait until `path` exists, polling every 20 ms, for at most `timeout`.
/// Device nodes appear a moment after their driver binds.
pub fn wait_for_path(path: &str, timeout: Duration) -> io::Result<()> {
    let start = Instant::now();
    loop {
        if Path::new(path).exists() {
            return Ok(());
        }
        if start.elapsed() >= timeout {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("{path} did not appear within {timeout:?}"),
            ));
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn check(rc: libc::c_int) -> io::Result<()> {
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wait_for_an_existing_path_returns_at_once() {
        assert!(wait_for_path("/", Duration::from_millis(50)).is_ok());
    }

    #[test]
    fn wait_for_a_missing_path_times_out() {
        let err = wait_for_path("/definitely/not/here", Duration::from_millis(60))
            .err()
            .map(|e| e.kind());
        assert_eq!(err, Some(io::ErrorKind::TimedOut));
    }

    #[test]
    fn mounting_without_privilege_fails_cleanly() {
        // Unprivileged test runs get EPERM (or ENOENT for the target); either
        // way it is an error, never a panic.
        assert!(mount("none", "/nonexistent-target", "tmpfs", 0).is_err());
    }

    #[test]
    fn nul_bytes_are_rejected_before_the_syscall() {
        let err = mount("a\0b", "/x", "tmpfs", 0).err().map(|e| e.kind());
        assert_eq!(err, Some(io::ErrorKind::InvalidInput));
    }
}
