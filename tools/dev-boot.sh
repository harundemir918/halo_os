#!/usr/bin/env bash
# Interim dev script until the `halo` build driver exists (docs/BUILD.md §5).
# Builds the qemu-arm64 kernel and a haloinit initramfs, then boots it in QEMU.
# Run it inside the build VM: limactl shell halo-builder
#
#   tools/dev-boot.sh kernel   fetch, verify and build the kernel
#   tools/dev-boot.sh initrd   build haloinit and the initramfs
#   tools/dev-boot.sh run      boot interactively (Ctrl-A X quits QEMU)
#   tools/dev-boot.sh test     boot headless and expect "haloinit: boot ok"
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

build_initrd() {
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
  (cd "$repo/system" && RUSTFLAGS="-C target-feature=+crt-static" \
    CARGO_TARGET_DIR="$out/target" cargo build --release -p haloinit \
    --target aarch64-unknown-linux-gnu)
  local stage=$out/initramfs
  rm -rf "$stage"
  mkdir -p "$stage"/{dev,proc,sys,run,tmp}
  install -m 0755 "$out/target/aarch64-unknown-linux-gnu/release/haloinit" "$stage/init"
  (cd "$stage" && find . | cpio -o -H newc --owner=0:0 --quiet | gzip -9 >"$initrd")
  ls -l "$initrd"
}

qemu() {
  qemu-system-aarch64 -M virt -cpu max -m 1G -smp 2 \
    -kernel "$image" -initrd "$initrd" \
    -append "console=ttyAMA0 $1" \
    -nographic -no-reboot
}

case ${1:-} in
  kernel) build_kernel ;;
  initrd) build_initrd ;;
  run) qemu "" ;;
  test)
    log=$out/boot-test.log
    timeout 180 bash -c "$(declare -f qemu); image=$image initrd=$initrd; qemu halo.test=boot" \
      >"$log" 2>&1 || true
    cat "$log"
    grep -q "haloinit: boot ok" "$log" && echo "PASS: booted to haloinit" || { echo "FAIL: no boot ok"; exit 1; }
    ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
