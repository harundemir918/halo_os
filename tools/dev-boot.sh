#!/usr/bin/env bash
# Interim dev script until the `halo` build driver exists (docs/BUILD.md §5).
# Builds the qemu-arm64 kernel, an initramfs and an EROFS root image, then
# boots them in QEMU. Run it inside the build VM: limactl shell halo-builder
#
#   tools/dev-boot.sh kernel   fetch, verify and build the kernel
#   tools/dev-boot.sh initrd   build halo-initramfs and the initramfs
#   tools/dev-boot.sh rootfs   build haloinit and the EROFS root image
#   tools/dev-boot.sh run      boot interactively (Ctrl-A X quits QEMU)
#   tools/dev-boot.sh test     boot headless; expects a boot from the EROFS image
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
target=aarch64-unknown-linux-gnu

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

# Static glibc binaries: there is no libc in the initramfs or the root yet.
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

build_rootfs() {
  cargo_static haloinit
  local stage=$out/rootfs
  rm -rf "$stage"
  mkdir -p "$stage"/{sbin,dev,proc,sys,run,tmp}
  install -m 0755 "$out/target/$target/release/haloinit" "$stage/sbin/haloinit"
  # Everything owned by root, fixed timestamps: the image is reproducible.
  mkfs.erofs --all-root -T0 "$rootfs" "$stage" >/dev/null
  ls -l "$rootfs"
}

qemu() { # qemu <extra kernel args>
  qemu-system-aarch64 -M virt -cpu max -m 1G -smp 2 \
    -kernel "$image" -initrd "$initrd" \
    -drive "file=$rootfs,if=none,format=raw,id=root,readonly=on" \
    -device virtio-blk-device,drive=root \
    -append "console=ttyAMA0 root=/dev/vda rootfstype=erofs ro $1" \
    -nographic -no-reboot
}

case ${1:-} in
  kernel) build_kernel ;;
  initrd) build_initrd ;;
  rootfs) build_rootfs ;;
  run) qemu "" ;;
  test)
    log=$out/boot-test.log
    timeout 180 bash -c "$(declare -f qemu); image=$image initrd=$initrd rootfs=$rootfs; qemu halo.test=boot" \
      >"$log" 2>&1 || true
    cat "$log"
    fail=0
    for want in "halo-initramfs: switching root" "haloinit: root is erofs" "haloinit: boot ok"; do
      grep -q "$want" "$log" || { echo "MISSING: $want"; fail=1; }
    done
    [ "$fail" = 0 ] && echo "PASS: booted from the EROFS image" || { echo "FAIL"; exit 1; }
    ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
