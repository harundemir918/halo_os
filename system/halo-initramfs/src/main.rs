//! Binary edge of halo-initramfs: anyhow is allowed here (CLAUDE.md).

fn main() {
    #[cfg(target_os = "linux")]
    linux::main();
    #[cfg(not(target_os = "linux"))]
    eprintln!("halo-initramfs only runs on Linux");
}

#[cfg(target_os = "linux")]
mod linux {
    use anyhow::{Context, Result};
    use halo_initramfs::BootParams;
    use halo_sys as sys;
    use std::os::unix::process::CommandExt;
    use std::process::Command;
    use std::time::Duration;

    const NEWROOT: &str = "/newroot";
    const NAME: &str = "halo-initramfs";

    pub fn main() {
        println!("{NAME}: starting");
        // Only returns on failure: success replaces this process.
        let err = match switch_root() {
            Ok(never) => match never {},
            Err(e) => e,
        };
        eprintln!("{NAME}: boot failed: {err:#}");
        // PID 1 must not exit (the kernel would panic), so stop the machine.
        let e = sys::poweroff();
        eprintln!("{NAME}: poweroff failed: {e}");
        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    }

    /// Mount the root device, move the early mounts into it and exec its init.
    /// Returns only on error.
    fn switch_root() -> Result<std::convert::Infallible> {
        // The kernel normally mounts devtmpfs on /dev already (EBUSY then).
        for (source, target, fstype) in [
            ("proc", "/proc", "proc"),
            ("sysfs", "/sys", "sysfs"),
            ("devtmpfs", "/dev", "devtmpfs"),
        ] {
            if let Err(e) = sys::mount(source, target, fstype, 0)
                && e.raw_os_error() != Some(sys::EBUSY)
            {
                return Err(e).with_context(|| format!("mount {target}"));
            }
        }

        let cmdline = std::fs::read_to_string("/proc/cmdline").context("read /proc/cmdline")?;
        let params = BootParams::parse(&cmdline)?;
        println!(
            "{NAME}: root {} ({}), init {}",
            params.root, params.fstype, params.init
        );

        sys::wait_for_path(&params.root, Duration::from_secs(10))
            .with_context(|| format!("wait for {}", params.root))?;
        std::fs::create_dir_all(NEWROOT).context("create /newroot")?;
        sys::mount(&params.root, NEWROOT, &params.fstype, sys::RDONLY)
            .with_context(|| format!("mount {} on {NEWROOT}", params.root))?;

        for dir in ["dev", "proc", "sys"] {
            let target = format!("{NEWROOT}/{dir}");
            std::fs::create_dir_all(&target).ok(); // read-only roots ship these
            sys::mount_move(&format!("/{dir}"), &target).with_context(|| format!("move /{dir}"))?;
        }

        println!("{NAME}: switching root");
        std::env::set_current_dir(NEWROOT).context("chdir /newroot")?;
        sys::mount_move(".", "/").context("move new root onto /")?;
        sys::chroot(".").context("chroot")?;
        std::env::set_current_dir("/").context("chdir /")?;

        let err = Command::new(&params.init).exec();
        Err(err).with_context(|| format!("exec {}", params.init))
    }
}
