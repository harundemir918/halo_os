use haloinit::NAME;

fn main() {
    println!("{NAME}: Halo OS starting");
    #[cfg(target_os = "linux")]
    if std::process::id() == 1 {
        run_as_pid1();
    }
}

/// PID 1 must never exit: after the early setup it parks forever.
#[cfg(target_os = "linux")]
fn run_as_pid1() {
    use halo_sys as sys;
    use haloinit::{FLAG_TEST_BOOT, cmdline_has, root_fstype};
    use std::time::Duration;

    if let Err(e) = sys::mount("proc", "/proc", "proc", 0) {
        eprintln!("{NAME}: mount /proc failed: {e}");
    }
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();
    println!("{NAME}: cmdline: {}", cmdline.trim());
    let mounts = std::fs::read_to_string("/proc/mounts").unwrap_or_default();
    println!(
        "{NAME}: root is {}",
        root_fstype(&mounts).unwrap_or("unknown")
    );

    if cmdline_has(&cmdline, FLAG_TEST_BOOT) {
        println!("{NAME}: boot ok");
        let e = sys::poweroff();
        eprintln!("{NAME}: poweroff failed: {e}");
    }
    loop {
        std::thread::sleep(Duration::from_secs(3600));
    }
}
