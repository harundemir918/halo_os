# Screenshots of Halo running in QEMU

`os-*.png` are taken from the running OS, not from a desktop build: Linux 6.18, `haloinit`, our glibc, the Flutter engine's software renderer and the shell, on a virtio-gpu display (390 × 844). They were driven by touch events sent to a virtio tablet (`tools/qemu-drive.py`).

| File | What was done |
|---|---|
| `os-1-lock.png` | Boot |
| `os-2-home.png` | Hold the ring to unlock |
| `os-3-switchboard.png` | Swipe down from the top right |
| `os-4-switchboard-bluetooth-off.png` | Tap the Bluetooth row |
| `os-5-recents.png` | Swipe up from the bottom edge twice |
| `os-6-stream.png` | Swipe up again, then down from the top left |

The shell runs on mock data (`HALO_BACKEND=mock`). To retake them, see docs/BUILD.md §7.
