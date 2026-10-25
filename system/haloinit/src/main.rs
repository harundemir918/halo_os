use haloinit::NAME;

fn main() {
    println!("{NAME}: Halo OS starting");
    #[cfg(target_os = "linux")]
    if std::process::id() == 1 {
        run_as_pid1();
    }
}

/// PID 1 must never exit: after the early setup it reaps children forever.
#[cfg(target_os = "linux")]
fn run_as_pid1() {
    use halo_sys as sys;
    use haloinit::{FLAG_TEST_BOOT, cmdline_has, root_fstype};
    use std::process::Command;
    use std::time::Duration;

    const SPLASH: &str = "/sbin/halo-splash";

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
    } else if std::path::Path::new(SPLASH).exists() {
        // Stands in for the shell until the Flutter embedder exists.
        match Command::new(SPLASH).spawn() {
            Ok(child) => println!("{NAME}: started {SPLASH} (pid {})", child.id()),
            Err(e) => eprintln!("{NAME}: cannot start {SPLASH}: {e}"),
        }
    }

    loop {
        match sys::wait_any() {
            Ok(Some(pid)) if pid > 0 => println!("{NAME}: child {pid} exited"),
            Ok(Some(_)) => {}
            // No children (or an error): wait a while before looking again.
            Ok(None) | Err(_) => std::thread::sleep(Duration::from_secs(1)),
        }
    }
}
