# Building Halo OS

Status: **planned**. None of the commands below exist yet. This document describes the build system we are going to write. Update it when the real commands land.

## 1. Principles

- One command produces a bootable image from a clean checkout: `./halo build --target <target>`.
- Every upstream source is pinned by version and checksum in `third_party/manifest.toml`. Sources are downloaded into a cache and are never vendored into git.
- Builds are hermetic and reproducible. Everything runs inside the pinned build container, so macOS hosts work the same as Linux hosts.
- No distribution packages end up in the image. The container provides the *host* tools. The *target* is built entirely from our recipes.

### Build host

Kernel, rootfs and image builds need Linux. On macOS they run in a Lima VM defined in `build/lima/halo-builder.yaml` (Debian 13, host tools only, same package list as `build/container/Containerfile`):

```sh
limactl start --name halo-builder build/lima/halo-builder.yaml   # once
limactl shell halo-builder                                       # work inside
```

Lima mounts your home directory read-only at the same path, so the repo is visible in the VM. Build output goes to the VM's own disk. Copy artifacts out with `limactl copy`.

## 2. Toolchain

| Piece | Choice (proposed) | Why |
|---|---|---|
| Compiler | LLVM/Clang (pinned), cross for `aarch64-linux-gnu` and `x86_64-linux-gnu` | The Flutter engine builds with Clang. One compiler for everything. |
| libc | glibc (built from source into our sysroot) | The Flutter engine and Mesa are best supported on glibc. musl stays an option for static system binaries. |
| C++ runtime | libc++ | Matches the Flutter engine's build |
| Rust | Pinned stable via `rust-toolchain.toml`, targets `aarch64-unknown-linux-gnu`, `x86_64-unknown-linux-gnu` | System services, init, compositor |
| Flutter | Pinned SDK version (`.flutter-version`) plus a matching engine build from source (`third_party/flutter-engine`) | Embedder API, AOT `libapp.so`, `libflutter_engine.so` |
| Kernel | Mainline LTS, version pinned in `kernel/VERSION`, config fragments in `kernel/configs/` | |

## 3. Pipeline

```
fetch      → third_party sources into ~/.cache/halo/src (checksummed)
toolchain  → clang + glibc + libc++ sysroot per arch
kernel     → Image / bzImage + dtbs + modules
base       → recipes in build/recipes/*.toml (libdrm, mesa, libinput, ...)
engine     → libflutter_engine.so (release, embedder target)
system     → cargo build --release (haloinit, compositor, services)
embedder   → halo-embedder (C++)
dart       → flutter build bundle + gen_snapshot AOT for shell/ and apps/*
rootfs     → assemble staging tree → EROFS → dm-verity hash tree
image      → GPT: boot_a/b, system_a/b, data · sign
```

Recipes are small declarative TOML files (source, version, configure/build/install steps, deps) run by `halo`, our build driver (Rust, in `build/halo/`). We don't use Buildroot or Yocto. We want to own the build and keep it understandable. Buildroot can still serve as a reference for tricky packages.

## 4. Targets

| Target | Arch | Purpose | Phase |
|---|---|---|---|
| `qemu-arm64` | aarch64 | Primary development and CI target. `virt` + virtio-gpu (virgl), virtio-input, virtio-net | 1 |
| `qemu-x86_64` | x86_64 | Fast KVM on Linux hosts | 1 |
| `rpi5-dev` | aarch64 | First real hardware: Raspberry Pi 5 + official 7" touch display (or a DSI portrait panel). Good mainline support, cheap, no modem | 5 |
| `phone-1` | aarch64 | First real phone. Candidates with good mainline support: OnePlus 6/6T (sdm845), PinePhone Pro (rk3399s), Fairphone. **Open, decide before Phase 5 ends.** | 5–6 |

## 5. Planned commands

```sh
# UI iteration on the host (no OS build needed)
cd shell && flutter run -d macos --dart-define=HALO_BACKEND=mock

# Full OS
./halo doctor                       # checks host: container runtime, disk, KVM
./halo build --target qemu-arm64    # full image into out/qemu-arm64/
./halo run   --target qemu-arm64    # boots in QEMU with a 390x844 (x3 scale) window
./halo build kernel|system|shell    # rebuild one stage
./halo flash --target rpi5-dev --device /dev/sdX

# Tests
cargo test --workspace              # in system/
flutter test                        # in packages/* , shell/, apps/*
flutter test --update-goldens       # in shell/, refresh goldens (review the diff!)
./halo test boot --target qemu-arm64   # boots, waits for Lock, takes a screenshot
```

## 6. Output

```
out/<target>/
├── boot.img        kernel + initramfs + dtb (signed)
├── system.erofs    root image
├── system.verity   hash tree + root hash
├── halo.img        full disk image (GPT)
└── sdk/            sysroot + headers for building the embedder/apps out-of-tree
```
