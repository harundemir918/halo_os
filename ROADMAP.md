# Halo OS roadmap

Phases are sequential, but work can overlap. In particular, Phase 2 (shell UI on desktop) can start alongside Phase 1 because it only needs Flutter on the host. Each phase lists exit criteria, and a phase is done only when all of them hold.

Legend: ☐ to do · ◐ in progress · ☑ done

---

## Phase 0: Foundations
- ☑ Design exports and sources in `design/`
- ☑ Project docs: README, CLAUDE.md, ROADMAP, ARCHITECTURE, DESIGN_SYSTEM, BUILD, DECISIONS
- ☑ Repo skeleton. Directories that have content exist (`system/`, `packages/`, `kernel/`, `build/`, `third_party/`); the rest are created when work needs them (CLAUDE.md)
- ☑ Pin versions: Flutter 3.47.4 (`.flutter-version`), Rust 1.99.1 (`rust-toolchain.toml`), kernel 6.18.58 (`kernel/VERSION`), LLVM 23.1.4 (`third_party/manifest.toml`; reconcile with the Flutter engine clang before Phase 1)
- ◐ Build container image (host tools only): `build/container/Containerfile` written, never built (no container runtime on the dev machine yet)
- ◐ CI: format, lint and tests for Rust and Dart: `.github/workflows/ci.yml` written; every step passes locally, but it has not run on GitHub yet
- ☑ License chosen (MIT, `LICENSE`). Font licenses (OFL) recorded in `third_party/`

**Exit:** a clean checkout runs `cargo test` and `flutter test` (empty but wired) in CI.

## Phase 1: Boot to pixels (QEMU)
- ☐ `halo` build driver: fetch, toolchain, recipe runner
- ☐ Clang + glibc + libc++ sysroot for aarch64
- ☐ Kernel config fragments for `qemu-arm64` (virtio-gpu, virtio-input, DRM, EROFS, dm-verity, cgroup2, namespaces, Landlock)
- ☐ `halo-initramfs`: mount, switch_root
- ☐ `haloinit`: TOML units, supervision, shutdown and reboot
- ☐ `halo-devd`: uevents, device nodes, firmware loading
- ☐ Base recipes: libdrm, Mesa (virgl, later freedreno, panfrost, v3d), libinput, libevdev, xkbcommon, freetype, fontconfig
- ☐ Flutter engine built for the embedder target
- ☐ Minimal DRM/EGL embedder that shows a Flutter "hello" frame full screen and reacts to touch
- ☐ `./halo run` boots the image in QEMU

**Exit:** QEMU boots to a Flutter frame in under 3 s from kernel start, touch input works, and the image contains only what our recipes built.

## Phase 2: Shell UI (desktop, mock data)
- ☑ `packages/halo_ui`: tokens (colors, type, notch radii, spacing), bundled fonts, `NotchBorder`, `HaloTheme`
- ☐ Widgets: Switch, ToggleRow, Dial, Slat, Segmented, Slider, Buttons, CommandField, Timeline, BatteryLine, BatteryCells, Arc, Kicker
- ☐ `packages/halo_sdk` API surface plus the **mock** backend (fixtures matching the design copy: Elif, Design review, Room 3…)
- ☐ Screens: Lock, Home Arc, Recents, Switchboard, Stream, System
- ☐ Navigation and gestures: hold-to-open, the arc's focus/launch, slat pan and flick-to-close, shell edge swipes (see open questions)
- ☐ Golden tests against `design/screens/*.png` at 390 × 844 @2x
- ☐ Accessibility pass: semantics labels, text scaling (System → Text size), reduce motion

**Exit:** all six screens match the designs in golden tests, and the shell is fully navigable on macOS desktop with mock data.

## Phase 3: Compositor and multi-app
- ☐ Spike: dmabuf → Flutter external texture performance on virgl (validates D-005)
- ☐ `halo-compositor` (Smithay): DRM/KMS atomic, libinput, Wayland core + xdg-shell + linux-dmabuf + `halo_shell_v1`
- ☐ Shell runs inside the compositor (embedded engine) on QEMU
- ☐ `halo-embedder`: Flutter app as a Wayland client
- ☐ `halo-apps`: manifest, launch, lifecycle, freeze/thaw (cgroup freezer), recents list
- ☐ Recents slats show live and frozen app surfaces
- ☐ On-screen keyboard (shell-rendered, text-input-v3)

**Exit:** on QEMU, launch three apps from the arc, switch between them in Recents, close one with a flick, and type into a text field. 60 fps in shell transitions on QEMU/virgl (best effort) and on the dev board.

## Phase 4: Core system services
- ☐ `halo-bus`: proto schemas, Rust server lib, Dart client codegen, peer-credential auth
- ☐ `halo_sdk` real backend (replaces the mock where available)
- ☐ `halo-settings`, `halo-time` (NTP, timezone, alarms), `halo-logd`
- ☐ `halo-power`: battery line, battery cells, "full by" estimate, suspend/resume
- ☐ `halo-display`: brightness dial, auto brightness
- ☐ `halo-audio`: PipeWire, volume dial, media session, the Switchboard media strip
- ☐ `halo-net`: Wi-Fi scan, connect, airplane mode
- ☐ `halo-notify` + `halo-focus`: Stream timeline, actions, unread (Flare), focus filtering
- ☐ System (Settings) app wired to real services: Connections, Display, Sound, Focus, Privacy, Battery

**Exit:** on QEMU with virtio devices, Switchboard and System control real state and Stream shows real notifications from a test app.

## Phase 5: Hardware bring-up
- ☐ `rpi5-dev`: kernel config, device tree, panel and touch, v3d Mesa, Wi-Fi, audio
- ☐ Portrait panel orientation, DPI scaling to the 390-wide logical frame
- ☐ Real battery and fuel gauge (on a phone, or a UPS HAT for the Pi)
- ☐ Suspend-to-RAM with wake on power key and alarm
- ☐ **Pick the first phone (D-010)** and start its bring-up

**Exit:** the dev board boots Halo to Lock, all of Phase 4 works on it, and it resumes from suspend in under 1 s.

## Phase 6: Phone: telephony and connectivity
- ☐ Kernel and device support for `phone-1` (display, touch, GPU, charger, fuel gauge, sensors)
- ☐ Decide the BT and modem stacks (D-011)
- ☐ `halo-modem`: SIM, cellular data, SMS, voice calls with audio routing
- ☐ `halo-bt`: pairing, A2DP/HFP audio
- ☐ `halo-location`: GNSS
- ☐ Camera pipeline (libcamera) for the camera app and the lock shortcut
- ☐ Flashlight (lock shortcut)

**Exit:** daily-driver smoke test on `phone-1`: make and receive a call, send and receive SMS, mobile data, BT headphones, take a photo.

## Phase 7: Security and updates
- ☐ Per-app uid, namespaces, seccomp, Landlock, cgroup limits
- ☐ Permission manifest plus runtime grant prompts in the shell, Privacy settings
- ☐ `/data` encryption tied to the lock credential
- ☐ Verified boot: signed boot image, dm-verity, rollback protection
- ☐ `halo-update`: A/B OTA with auto-rollback
- ☐ `halo-keystore`

**Exit:** an external review of the sandbox, and an OTA round trip including a forced-failure rollback on hardware.

## Phase 8: First-party apps
- ☐ Messages, Phone, Camera, Music, Maps, Notes, Web (engine choice is open: WebView via WPE WebKit or Chromium/CEF)
- ☐ Calendar data source feeding Home "NOW", the Lock next-event card and Stream
- ☐ All apps use only `halo_ui`

**Exit:** every app on the Home arc is functional on `phone-1`.

## Phase 9: Halo intelligence
- ☐ Decide on-device versus cloud and the privacy model (D-012)
- ☐ `halo-intel`: the Stream summary ("Halo read 11 things for you / 3 need you"), the Home "NOW" pick, notification priority
- ☐ Ask Halo: voice and text assistant from the Home arc
- ☐ Rule-based fallback when the model is unavailable

**Exit:** summaries run within the latency and privacy budgets with no data leaving the device unless the user opts in.

## Phase 10: SDK and developer preview
- ☐ Public `halo_sdk` / `halo_ui` packages and docs
- ☐ App bundle tooling: `halo app build|sign|install`
- ☐ Emulator distribution (QEMU image + runner)
- ☐ Developer preview release

---

## Open questions
- **Shell gestures:** the designs show the screens but not how to reach them. Proposal: swipe up from the bottom edge for Home, swipe up and hold for Recents, swipe down from the top right for Switchboard, swipe down from the top left for Stream. The arc scrolls horizontally to focus an app, and a tap launches it.
- **Light appearance:** System offers Light and Auto, but there is no light palette yet (D-013).
- **Motion spec:** none exists. DESIGN_SYSTEM §8 has interim rules.
- **Arc with more than 7 apps:** scroll along the arc? An "all apps" view that respects "no grid"?
- **Web engine** for the Web app.
- **First phone** (D-010), **BT and modem stacks** (D-011), **AI approach** (D-012).
