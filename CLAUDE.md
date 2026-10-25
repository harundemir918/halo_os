# CLAUDE.md

Guide for AI agents and contributors working in this repository.

## What this is

**Halo OS** is a mobile OS built from scratch on the **Linux kernel**, with **no distribution** (no Ubuntu, Debian, Alpine, postmarketOS or AOSP userspace). We own PID 1 and everything above it. **All UI is Flutter**: the system shell and the apps.

Current status: **pre-alpha.** The six shell screens run on macOS against mock data. A kernel and `haloinit` boot in QEMU. There is no graphical boot yet. Check [ROADMAP.md](ROADMAP.md) for the active phase before starting work, and tick off items (☐ → ◐ → ☑) as you complete them.

## Read first

| Doc | Read it when |
|---|---|
| [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | You touch any UI (shell, apps, `halo_ui`) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | You touch init, services, the compositor, the embedder, IPC or security |
| [docs/BUILD.md](docs/BUILD.md) | You touch the build, toolchain, kernel or images |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Before you make or change an architectural choice |
| `design/` | Visual truth. PNGs for looks, `.dc.html` sources for exact numbers (see `design/README.md`) |

## Hard rules

1. **No distribution.** Don't add a base distro, a distro package manager or distro packages to the target image. Upstream libraries (Mesa, libinput, PipeWire…) are allowed only through our own pinned recipes in `build/recipes/`. When an upstream dependency is new, add it to `third_party/manifest.toml` with its version, checksum and license.
2. **Don't silently change decisions.** Decisions marked *Decided* in `docs/DECISIONS.md` are the owner's call, so don't contradict them. Decisions marked *Proposed* may be challenged: write the case in DECISIONS.md and ask, don't just change course in code.
3. **Design fidelity.** UI must follow `docs/DESIGN_SYSTEM.md`:
   - **No grid, no glass, no dock.** No icon grids, no `BackdropFilter`/blur/translucent surfaces, no persistent dock.
   - **Volt `#D6FF3F` means on, active or yours, nothing else. Flare `#FF5B2E` means unread or alert, nothing else.**
   - Use the **notch** shapes (big top-left radius, three small). **Circles are for apps only.**
   - Bricolage Grotesque for the voice. DM Mono, UPPERCASE and tracked, for labels, counts and times.
   - Use `halo_ui` tokens and widgets. Never hard-code colors, radii or text styles in shell or app code.
   - Read exact values from `design/source/*.dc.html` (inline styles). Don't eyeball them from the PNGs.
4. **Every app is a separate sandboxed process.** Don't run apps inside the shell's engine.
5. **No D-Bus in core services.** Use halo-bus (protobuf over Unix sockets). See D-006 and D-011.
6. **No network at runtime for assets.** Fonts and images are bundled. Never use `google_fonts` runtime fetching.

## Languages and where they go

| Area | Language | Location (planned) |
|---|---|---|
| Init, device manager, services, compositor, build driver | Rust (stable, pinned) | `system/`, `build/halo/` |
| Flutter app embedder | C++ (Flutter Embedder API) | `embedder/` |
| Shell UI | Dart / Flutter | `shell/` |
| First-party apps | Dart / Flutter | `apps/<name>/` |
| Design system, SDK, IPC client | Dart packages | `packages/halo_ui`, `packages/halo_sdk`, `packages/halo_ipc` |
| IPC schemas | Protobuf | `system/proto/` |
| Kernel config and patches | Kconfig fragments, `git format-patch` | `kernel/` |
| Recipes for upstream components | TOML | `build/recipes/` |

No new C, except for kernel patches.

## Planned repo layout

```
design/        design exports (png) and sources (.dc.html). Read-only reference
docs/          architecture, design system, build, decisions
kernel/        VERSION, configs/<target>.fragment, patches/
build/         halo build driver (Rust), recipes/, container/
third_party/   manifest.toml (pinned upstream sources and licenses). No vendored code
system/        Rust workspace: haloinit, halo-initramfs, halo-devd, halo-compositor,
               halo-<service>…, proto/, halo-bus lib
embedder/      halo-embedder (C++), Flutter Wayland client embedder
shell/         Flutter shell: lock, home, recents, switchboard, stream, OSDs, keyboard
apps/          system (settings), messages, phone, camera, music, maps, notes, web
packages/      halo_ui, halo_sdk, halo_ipc
tools/         dev scripts, QEMU helpers
```

Create directories when the work needs them. Don't scaffold empty trees ahead of time.

## Commands

The `halo` build driver doesn't exist yet. The planned interface is in [docs/BUILD.md §5](docs/BUILD.md). When you add a real command, document it here and in BUILD.md in the same change. Don't document commands that don't work.

What works today (same steps as `.github/workflows/ci.yml`):

```sh
# Rust (toolchain pinned in rust-toolchain.toml; rustup installs it)
cd system && cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace

# Dart (Flutter pinned in .flutter-version)
cd packages/halo_ui && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test

cd packages/halo_sdk && dart analyze && dart test

# Shell on macOS, 390 x 844 window, mock data. Starts on Lock; swipe edges to move around.
cd shell && flutter run -d macos --dart-define=HALO_BACKEND=mock
# Open on another screen: --dart-define=HALO_START=home|switchboard|stream|recents|system
cd shell && flutter test                    # add --update-goldens after a deliberate visual change

# Token gallery on macOS
cd packages/halo_ui/example && flutter run -d macos
```

Boot the OS in QEMU (inside the Lima VM, see docs/BUILD.md "Build host"):

```sh
limactl shell halo-builder
# On the host first: (cd shell && flutter build bundle --debug --dart-define=HALO_BACKEND=mock)
tools/dev-boot.sh kernel && tools/dev-boot.sh sysroot && tools/dev-boot.sh initrd && tools/dev-boot.sh rootfs
tools/dev-boot.sh test    # PASS: booted from the EROFS image
tools/run-on-mac.sh       # on the Mac, not in the VM: copy the image out and run it in a native window (brew install qemu)
tools/dev-boot.sh vnc     # alternative: VNC on localhost:5900 (macOS Screen Sharing refuses localhost; use another client)
SHOT_ACTIONS="wait:3;shot:lock" tools/dev-boot.sh shot   # drive it with touch, screenshots in ~/halo-out/shots
```

Fast UI loop (once `shell/` exists): run the shell as a macOS desktop Flutter app with `--dart-define=HALO_BACKEND=mock` at a 390 × 844 window. Kernel, rootfs and image builds need Linux, so on macOS they run inside the build container.

## Conventions

**Rust**
- `cargo fmt` and `cargo clippy -- -D warnings` must be clean.
- Use `thiserror` in libraries and `anyhow` only at binary edges. Never `unwrap()` in PID 1 or the compositor.
- Use tokio for async services. Log through `tracing` → halo-logd.
- One binary per service, each with its own unit file in `system/<svc>/init.toml`.

**Dart / Flutter**
- `dart format` plus `flutter analyze` with no warnings. Use the lint set in `analysis_options.yaml` (to be added).
- Use stateless widgets and explicit state objects. Pick one state-management approach for the whole repo in Phase 2 and record it in DECISIONS.md.
- Shell and apps reach services only through `halo_sdk`. Every `halo_sdk` API has a mock implementation.
- Mock fixtures reuse the copy from the designs (Elif, "Design review · Room 3", Karaköy, Night Drive / Mira Okafor) so golden tests line up with `design/screens/`.

**Testing**
- Rust: unit tests per crate, plus integration tests for halo-bus.
- Flutter: widget tests for every `halo_ui` widget, and golden tests for every shell screen against the design PNGs.
- OS: `./halo test boot` boots in QEMU, waits for Lock, and takes a screenshot (Phase 1+).
- Run the relevant tests before claiming work is done. Report failures as they are.

**Git**
- Work on `dev`. `main` is the release branch. Open PRs from `dev` (or feature branches) to `main`.
- Write small, focused commits with imperative messages (`compositor: import dmabuf as external texture`), prefixed with the area (`kernel:`, `init:`, `shell:`, `halo_ui:`, `docs:`, `build:`).
- Commit or push only when asked.

## Keeping docs current
- A change to architecture updates `docs/ARCHITECTURE.md` and, if it reverses a choice, `docs/DECISIONS.md`.
- A new design token or component updates `docs/DESIGN_SYSTEM.md` and `halo_ui` together.
- Finishing a roadmap item updates the checkbox in `ROADMAP.md`.
