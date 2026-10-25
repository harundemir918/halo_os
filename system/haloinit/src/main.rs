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

    // What to run as the shell, first match wins. The fbdev embedder runs the
    // Flutter shell; the splash only draws a picture. Both are interim until
    // the compositor exists (ROADMAP Phase 3).
    const SHELLS: &[(&str, &[&str])] = &[
        (
            "/sbin/halo-fbdev-embedder",
            &["/system/shell/flutter_assets", "/system/icudtl.dat"],
        ),
        ("/sbin/halo-splash", &[]),
    ];

    if let Err(e) = sys::mount("proc", "/proc", "proc", 0) {
        eprintln!("{NAME}: mount /proc failed: {e}");
    }
    // The root is read-only, so scratch space is tmpfs.
    for target in ["/tmp", "/run"] {
        if let Err(e) = sys::mount("tmpfs", target, "tmpfs", 0) {
            eprintln!("{NAME}: mount {target} failed: {e}");
        }
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
    } else if let Some((bin, args)) = SHELLS
        .iter()
        .find(|(b, _)| std::path::Path::new(b).exists())
    {
        // The Dart VM wants a writable HOME and temp directory.
        match Command::new(bin)
            .args(*args)
            .env("HOME", "/tmp")
            .env("TMPDIR", "/tmp")
            .env(
                "HALO_TRACE",
                if cmdline_has(&cmdline, "halo.trace") {
                    "1"
                } else {
                    ""
                },
            )
            .spawn()
        {
            Ok(child) => println!("{NAME}: started {bin} (pid {})", child.id()),
            Err(e) => eprintln!("{NAME}: cannot start {bin}: {e}"),
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
