#!/usr/bin/env bash
# Interim dev script until the `halo` build driver exists (docs/BUILD.md §5).
# Builds the qemu-arm64 kernel, an initramfs and an EROFS root image, then
# boots them in QEMU. Run it inside the build VM: limactl shell halo-builder
#
#   tools/dev-boot.sh kernel   fetch, verify and build the kernel
#   tools/dev-boot.sh sysroot  build glibc and the engine from build/recipes
#   tools/dev-boot.sh initrd   build halo-initramfs and the initramfs
#   tools/dev-boot.sh rootfs   build haloinit, the embedder and the EROFS image
#   tools/dev-boot.sh test     boot headless; expects a boot from the EROFS image
#   tools/dev-boot.sh shot     boot with a display, save ~/halo-out/screenshot.png
#   tools/dev-boot.sh vnc      boot with a display on VNC (localhost:5900; macOS Screen Sharing
#                              refuses localhost, so on a Mac prefer tools/run-on-mac.sh)
#   tools/dev-boot.sh run      boot on the serial console (Ctrl-A X quits QEMU)
#
# The shell bundle comes from the host: run `flutter build bundle` in shell/
# first (it needs the Flutter SDK, which is not in the VM).
#
# Output goes to $HALO_OUT (default ~/halo-out), sources to $HALO_SRC.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out=${HALO_OUT:-$HOME/halo-out}
src=${HALO_SRC:-$HOME/.cache/halo/src}
kver=$(tr -d '[:space:]' <"$repo/kernel/VERSION")
ksrc=$out/linux-$kver
kbuild=$out/kbuild
image=$kbuild/arch/arm64/boot/Image
initrd=$out/initramfs.cpio.gz
rootfs=$out/system.erofs
sysroot=$out/sysroot
engine=$out/engine
embedder=$out/embedder/halo-fbdev-embedder
assets=$repo/shell/build/flutter_assets
target=aarch64-unknown-linux-gnu
display_args=(-device virtio-gpu-pci,xres=390,yres=844 -device virtio-tablet-pci -device virtio-keyboard-pci)

manifest() { # manifest <source-name> <key>
  python3 -I - "$repo/third_party/manifest.toml" "$1" "$2" <<'EOF'
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
print(next(s for s in data["source"] if s["name"] == sys.argv[2])[sys.argv[3]])
EOF
}

build_kernel() {
  mkdir -p "$src" "$out"
  local url sha tarball
  url=$(manifest linux url)
  sha=$(manifest linux sha256)
  tarball=$src/$(basename "$url")
  if [ ! -f "$tarball" ]; then
    curl -fsSL -o "$tarball.part" "$url"
    mv "$tarball.part" "$tarball"
  fi
  echo "$sha  $tarball" | sha256sum -c -
  [ -d "$ksrc" ] || tar -C "$out" -xf "$tarball"

  mkdir -p "$kbuild"
  make -C "$ksrc" O="$kbuild" ARCH=arm64 defconfig
  (cd "$kbuild" && "$ksrc/scripts/kconfig/merge_config.sh" -m .config \
    "$repo/kernel/configs/qemu-arm64.fragment")
  make -C "$ksrc" O="$kbuild" ARCH=arm64 olddefconfig

  # olddefconfig silently drops options whose dependencies are not met.
  local missing=0 line
  while IFS= read -r line; do
    case $line in CONFIG_*=*) ;; *) continue ;; esac
    grep -qxF "$line" "$kbuild/.config" || { echo "config not applied: $line"; missing=1; }
  done <"$repo/kernel/configs/qemu-arm64.fragment"
  [ "$missing" = 0 ] || exit 1

  make -C "$ksrc" O="$kbuild" ARCH=arm64 -j"$(nproc)" Image
}

build_sysroot() {
  python3 "$repo/tools/recipe.py" glibc
  python3 "$repo/tools/recipe.py" flutter-engine
}

# Static glibc binaries: the initramfs has no libc.
cargo_static() { # cargo_static <package>...
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
  local args=()
  for p in "$@"; do args+=(-p "$p"); done
  (cd "$repo/system" && RUSTFLAGS="-C target-feature=+crt-static" \
    CARGO_TARGET_DIR="$out/target" cargo build --release "${args[@]}" --target "$target")
}

build_initrd() {
  cargo_static halo-initramfs
  local stage=$out/initramfs
  rm -rf "$stage"
  mkdir -p "$stage"/{dev,proc,sys,newroot}
  install -m 0755 "$out/target/$target/release/halo-initramfs" "$stage/init"
  (cd "$stage" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9 >"$initrd")
  ls -l "$initrd"
}

build_embedder() {
  [ -f "$engine/flutter_embedder.h" ] || { echo "run: tools/dev-boot.sh sysroot"; exit 1; }
  mkdir -p "$(dirname "$embedder")"
  g++ -std=c++17 -O2 -Wall -Wextra -Werror -I "$engine" \
    "$repo/embedder/halo-fbdev/main.cc" -o "$embedder" \
    -L "$engine" -lflutter_engine -lpthread \
    -static-libstdc++ -static-libgcc -Wl,-rpath,/system/lib
}

build_rootfs() {
  [ -x "$sysroot/lib/ld-linux-aarch64.so.1" ] || { echo "run: tools/dev-boot.sh sysroot"; exit 1; }
  cargo_static haloinit halo-splash
  build_embedder
  local stage=$out/rootfs
  rm -rf "$stage"
  mkdir -p "$stage"/{sbin,lib,system/lib,system/shell,dev,proc,sys,run,tmp}
  install -m 0755 "$out/target/$target/release/haloinit" "$stage/sbin/haloinit"
  install -m 0755 "$out/target/$target/release/halo-splash" "$stage/sbin/halo-splash"
  install -m 0755 "$embedder" "$stage/sbin/halo-fbdev-embedder"
  # Our own glibc, and only what the engine and the embedder load.
  for lib in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1; do
    install -m 0755 "$sysroot/lib/$lib" "$stage/lib/$lib"
  done
  install -m 0755 "$engine/libflutter_engine.so" "$stage/system/lib/"
  install -m 0644 "$engine/icudtl.dat" "$stage/system/"
  # A frame rendered by the shell's golden test, for the splash fallback.
  install -m 0644 "$repo/shell/test/goldens/lock.png" "$stage/system/splash.png"
  if [ -d "$assets" ]; then
    cp -r "$assets" "$stage/system/shell/flutter_assets"
  else
    echo "note: $assets missing, the image will boot to the splash (run flutter build bundle in shell/)"
  fi
  # Everything owned by root, fixed timestamps: the image is reproducible.
  mkfs.erofs -zlz4 --all-root -T0 "$rootfs" "$stage" >/dev/null
  ls -l "$rootfs"
}

# KVM when the VM offers it (see nestedVirtualization in build/lima), else TCG.
accel_args() {
  if [ -w /dev/kvm ]; then
    echo "-machine virt,gic-version=host -accel kvm -cpu host"
  else
    echo "-machine virt -accel tcg -cpu max"
  fi
}

# qemu_common <serial> <extra kernel args> <qemu args>...
qemu_common() {
  local serial=$1 kargs=$2
  shift 2
  # shellcheck disable=SC2046
  qemu-system-aarch64 $(accel_args) -m 2G -smp 4 \
    -kernel "$image" -initrd "$initrd" \
    -drive "file=$rootfs,if=none,format=raw,id=root,readonly=on" \
    -device virtio-blk-device,drive=root \
    -serial "$serial" \
    -append "console=ttyAMA0 root=/dev/vda rootfstype=erofs ro vt.global_cursor_default=0 $kargs" \
    -no-reboot "$@"
}

# Boot with a virtio-gpu display and drive it through QMP (tools/qemu-drive.py):
# touch input and screenshots. SHOT_ACTIONS is the action list, for example
#   SHOT_ACTIONS="wait:3;shot:lock;hold:195,766:1200;wait:2;shot:home"
# Screenshots land in $out/shots/.
screenshot() {
  local qmp=$out/qemu-qmp.sock serial=$out/serial.log
  rm -f "$qmp" "$serial"
  rm -rf "$out/shots"
  qemu_common "file:$serial" "${SHOT_KARGS:-}" "${display_args[@]}" -display none \
    -qmp "unix:$qmp,server,nowait" &
  local qpid=$!
  python3 "$repo/tools/qemu-drive.py" "$qmp" "$serial" "$qpid" "$out/shots" \
    "${SHOT_ACTIONS:-wait:3;shot:screenshot}"
  wait "$qpid" 2>/dev/null || true
  grep -E "halo-initramfs|haloinit|halo-splash|halo-fbdev|\[halo\]" "$serial" | head -40 || true
}

case ${1:-} in
  kernel) build_kernel ;;
  sysroot) build_sysroot ;;
  initrd) build_initrd ;;
  rootfs) build_rootfs ;;
  run) qemu_common mon:stdio "" -nographic ;;
  vnc)
    echo "Open vnc://localhost:5900 (macOS: Finder > Go > Connect to Server). Ctrl-C stops."
    qemu_common stdio "" "${display_args[@]}" -display vnc=127.0.0.1:0
    ;;
  shot) screenshot ;;
  test)
    log=$out/boot-test.log
    # shellcheck disable=SC2046
    timeout 180 qemu-system-aarch64 $(accel_args) -m 2G -smp 4 \
      -kernel "$image" -initrd "$initrd" \
      -drive "file=$rootfs,if=none,format=raw,id=root,readonly=on" \
      -device virtio-blk-device,drive=root \
      -append "console=ttyAMA0 root=/dev/vda rootfstype=erofs ro halo.test=boot" \
      -nographic -no-reboot >"$log" 2>&1 || true
    cat "$log"
    fail=0
    for want in "halo-initramfs: switching root" "haloinit: root is erofs" "haloinit: boot ok"; do
      grep -q "$want" "$log" || { echo "MISSING: $want"; fail=1; }
    done
    [ "$fail" = 0 ] && echo "PASS: booted from the EROFS image" || { echo "FAIL"; exit 1; }
    ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
