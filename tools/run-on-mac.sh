#!/usr/bin/env bash
# Run the Halo image in a native macOS window: QEMU with Apple's hypervisor
# (HVF) and a Cocoa display. Click and drag in the window as touch.
#
#   tools/run-on-mac.sh            copy the image from the build VM, then run it
#   tools/run-on-mac.sh --no-copy  run the copy from last time
#
# Needs `brew install qemu`. Build the image first (docs/BUILD.md §7). The
# serial console is this terminal; close the window or press Ctrl-C to stop.
set -euo pipefail

vm=${HALO_VM:-halo-builder}
dir=${HALO_RUN_DIR:-$HOME/.cache/halo/run}
# QEMU's Cocoa window draws one guest pixel per Retina pixel, so a 2x guest
# display makes a crisp 390 x 844 point window. Use HALO_SCALE=1 on a small
# screen. (zoom-to-fit crops the content on recent macOS, so it is off.)
scale=${HALO_SCALE:-2}
# HALO_HZ=120 paces the shell's frames at 120 Hz (default 60); HALO_TRACE=1 prints fps.
extra="${HALO_HZ:+halo.hz=$HALO_HZ} ${HALO_TRACE:+halo.trace}"
# Multiple-of-8 width, and no EDID (see tools/dev-boot.sh): with EDID on, the Cocoa
# window's size is sent to the guest, which reprobes and blanks the display.
xres=$(((390 * scale + 7) / 8 * 8))
yres=$((844 * xres / 390))
display=${HALO_QEMU_DISPLAY:-cocoa}

command -v qemu-system-aarch64 >/dev/null || { echo "install QEMU: brew install qemu"; exit 1; }
mkdir -p "$dir"

if [ "${1:-}" != "--no-copy" ]; then
  for f in kbuild/arch/arm64/boot/Image initramfs.cpio.gz system.erofs; do
    echo "copying $f"
    limactl copy "$vm:halo-out/$f" "$dir/$(basename "$f")"
  done
fi

exec qemu-system-aarch64 \
  -machine virt -accel hvf -cpu host -m 2G -smp 4 \
  -kernel "$dir/Image" -initrd "$dir/initramfs.cpio.gz" \
  -drive "file=$dir/system.erofs,if=none,format=raw,id=root,readonly=on" \
  -device virtio-blk-device,drive=root \
  -device "virtio-gpu-pci,xres=$xres,yres=$yres,edid=off" \
  -device virtio-tablet-pci -device virtio-keyboard-pci \
  -append "console=ttyAMA0 root=/dev/vda rootfstype=erofs ro vt.global_cursor_default=0 consoleblank=0 $extra" \
  -display "$display" -serial stdio -no-reboot
