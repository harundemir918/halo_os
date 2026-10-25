//! Linux framebuffer (`/dev/fbN`) mapped into memory.

use crate::Surface;
use std::fs::OpenOptions;
use std::io;
use std::os::fd::AsRawFd;

/// Parse sysfs `virtual_size` (`780,1688`).
pub fn parse_size(s: &str) -> Option<(u32, u32)> {
    let (w, h) = s.trim().split_once(',')?;
    Some((w.trim().parse().ok()?, h.trim().parse().ok()?))
}

fn read_trimmed(path: &str) -> io::Result<String> {
    Ok(std::fs::read_to_string(path)?.trim().to_string())
}

fn invalid(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg)
}

/// A mapped 32-bit framebuffer.
pub struct Framebuffer {
    ptr: *mut u8,
    len: usize,
    surface: Surface,
}

impl Framebuffer {
    /// Open `dev` (`/dev/fb0`). Geometry comes from `sysfs`
    /// (`/sys/class/graphics/fb0`), so no ioctl is needed.
    pub fn open(dev: &str, sysfs: &str) -> io::Result<Self> {
        let size = read_trimmed(&format!("{sysfs}/virtual_size"))?;
        let (width, height) =
            parse_size(&size).ok_or_else(|| invalid(format!("bad virtual_size {size:?}")))?;
        let bpp: u32 = read_trimmed(&format!("{sysfs}/bits_per_pixel"))?
            .parse()
            .map_err(|_| invalid("bad bits_per_pixel".into()))?;
        if bpp != 32 {
            return Err(invalid(format!("need a 32-bit framebuffer, got {bpp}")));
        }
        let stride: u32 = read_trimmed(&format!("{sysfs}/stride"))?
            .parse()
            .map_err(|_| invalid("bad stride".into()))?;

        let file = OpenOptions::new().read(true).write(true).open(dev)?;
        let len = stride as usize * height as usize;
        // SAFETY: a fresh shared mapping of `len` bytes of the open
        // framebuffer, checked against MAP_FAILED below. The mapping outlives
        // the file descriptor, which is allowed.
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                file.as_raw_fd(),
                0,
            )
        };
        if ptr == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            ptr: ptr.cast(),
            len,
            surface: Surface {
                width,
                height,
                stride,
            },
        })
    }

    pub fn surface(&self) -> Surface {
        self.surface
    }

    /// The pixels, `stride * height` bytes, B, G, R, X.
    pub fn pixels(&mut self) -> &mut [u8] {
        // SAFETY: `ptr` is a live mapping of `len` bytes owned by `self`, and
        // `&mut self` guarantees exclusive access to it.
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.len) }
    }
}

impl Drop for Framebuffer {
    fn drop(&mut self) {
        // SAFETY: unmaps exactly the region mapped in `open`, once.
        unsafe {
            libc::munmap(self.ptr.cast(), self.len);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_virtual_size() {
        assert_eq!(parse_size("780,1688\n"), Some((780, 1688)));
        assert_eq!(parse_size(" 1280 , 800 "), Some((1280, 800)));
    }

    #[test]
    fn rejects_bad_sizes() {
        assert_eq!(parse_size(""), None);
        assert_eq!(parse_size("780"), None);
        assert_eq!(parse_size("a,b"), None);
        assert_eq!(parse_size("780,-1"), None);
    }

    #[test]
    fn a_missing_framebuffer_is_an_error() {
        assert!(Framebuffer::open("/dev/does-not-exist", "/sys/does-not-exist").is_err());
    }
}
