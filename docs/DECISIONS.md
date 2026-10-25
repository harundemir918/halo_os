# Decision log

Short architecture decision records. Status is **Decided** (set by the project owner), **Proposed** (the current plan, open to change until the dependent phase starts) or **Open** (needs research).

When a decision changes, update its entry and note the date. Don't delete history.

---

## D-001 · Linux kernel, no distribution. **Decided** (2026-10-25)
Halo runs on the Linux kernel. No existing distribution (Ubuntu, Debian, Alpine, postmarketOS, AOSP userspace) is used as a base. We write PID 1, the service layer and the shell. Upstream libraries are built from source by our own recipes.

## D-002 · Flutter for all UI. **Decided** (2026-10-25)
The shell and all first-party apps are Flutter (Dart). Third-party apps target the Halo Flutter SDK.

## D-003 · Rust for system code. **Proposed**
haloinit, the compositor, all services and the build driver are Rust. C++ only where the Flutter Embedder API makes it the practical choice (halo-embedder). No new C code except kernel patches.
*Alternatives:* C/C++ (more risk), Go (GC pauses and a larger runtime in PID 1).

## D-004 · Own init (haloinit), not systemd. **Proposed**
Small, declarative TOML units, supervision, no D-Bus dependency. systemd would pull in D-Bus, journald and logind, and a lot of policy we don't need.

## D-005 · Compositor in Rust (Smithay) that embeds the shell's Flutter engine. **Proposed**
Apps are separate Wayland clients. App buffers become external textures in the shell scene. See ARCHITECTURE §5.
*Alternatives:* a single engine with multi-view (no isolation), the GTK embedder (heavy), wlroots in C (another language).
*Risk:* Flutter external-texture performance with dmabuf on the target GPUs. Prototype in Phase 3 before committing.

## D-006 · halo-bus: protobuf over Unix sockets, no D-Bus in core. **Proposed**
*Alternatives:* D-Bus (dbus-broker), Varlink, Cap'n Proto, gRPC.

## D-007 · glibc + LLVM/Clang toolchain. **Proposed**
Required by the practical constraints of the Flutter engine.

## D-008 · Read-only EROFS root, dm-verity, A/B updates. **Proposed**

## D-009 · Own build driver (`halo`) with TOML recipes, not Buildroot or Yocto. **Proposed**
*Risk:* this takes real effort. If it drags on in Phase 1, fall back to Buildroot only as the *builder* for base libraries, with no Buildroot defaults in the image.

## D-010 · First targets: QEMU aarch64, then Raspberry Pi 5 + touch panel. **Proposed**
The first phone is **Open** (OnePlus 6/6T, PinePhone Pro, Fairphone…).

## D-011 · Bluetooth and cellular stacks. **Open**
BlueZ and ModemManager both want D-Bus. Options: a private dbus-broker behind a Halo service, or our own thin layers (QMI/MBIM for modems).

## D-012 · Halo intelligence (summaries, Ask Halo). **Open**
On-device model versus opt-in cloud, the privacy model and the hardware requirements. The design depends on it (Stream summary card, Home "NOW"), so a rule-based fallback must exist.

## D-013 · Light appearance. **Open**
System offers Dark / Light / Auto, but only dark is designed. A light palette is needed before Auto/Light can ship.

## D-014 · Build host: Debian 13 (host tools only). **Decided** (2026-10-25)
Kernel, rootfs and image builds run on Debian 13 (trixie): in a Lima VM on macOS (`build/lima/halo-builder.yaml`) or in the container (`build/container/Containerfile`). It provides host tools only. No Debian package or file ends up in the target image, so D-001 holds. To do: pin the base image by digest and the apt packages by snapshot date once the container is built.
