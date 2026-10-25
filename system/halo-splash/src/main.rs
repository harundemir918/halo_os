//! halo-splash: draw a PNG on the framebuffer, then stay alive.
//!
//! `halo-splash [image.png]` (default `/system/splash.png`).

use std::process::ExitCode;

fn main() -> ExitCode {
    #[cfg(target_os = "linux")]
    {
        match linux::run() {
            Ok(never) => match never {},
            Err(e) => {
                eprintln!("halo-splash: {e:#}");
                ExitCode::FAILURE
            }
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        eprintln!("halo-splash only runs on Linux");
        ExitCode::FAILURE
    }
}

#[cfg(target_os = "linux")]
mod linux {
    use anyhow::{Context, Result};
    use halo_splash::{blit_centered, decode_png, fb::Framebuffer};
    use std::convert::Infallible;
    use std::time::Duration;

    const DEV: &str = "/dev/fb0";
    const SYSFS: &str = "/sys/class/graphics/fb0";

    pub fn run() -> Result<Infallible> {
        let path = std::env::args()
            .nth(1)
            .unwrap_or_else(|| "/system/splash.png".to_string());
        let bytes = std::fs::read(&path).with_context(|| format!("read {path}"))?;
        let img = decode_png(&bytes).with_context(|| format!("decode {path}"))?;

        halo_sys::wait_for_path(DEV, Duration::from_secs(5)).context("wait for the framebuffer")?;
        let mut fb = Framebuffer::open(DEV, SYSFS).context("open the framebuffer")?;
        let surface = fb.surface();
        blit_centered(&img, fb.pixels(), surface);
        println!(
            "halo-splash: drawn {}x{} on {}x{}",
            img.width, img.height, surface.width, surface.height
        );
        // The picture stays only while the mapping does.
        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    }
}
