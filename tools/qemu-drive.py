#!/usr/bin/env python3
"""Drive a running QEMU through its QMP socket: touch input and screenshots.

    qemu-drive.py <qmp.sock> <serial.log> <qemu-pid> <out-dir> "<actions>"

Actions are separated by ';'. Coordinates are pixels on the 390 x 844 screen.

    wait:SECONDS            sleep
    tap:X,Y                 touch and release
    hold:X,Y:MS             touch, hold for MS milliseconds, release
    swipe:X1,Y1:X2,Y2:MS    drag over MS milliseconds
    shot:NAME               save <out-dir>/NAME.png

Before the first action it waits for the shell's first frame in the serial log.
"""
import json
import os
import socket
import struct
import sys
import time
import zlib

W, H = 390, 844
ABS_MAX = 0x7FFF  # virtio tablet range


def main():
    sock_path, serial, qpid, out_dir, actions = sys.argv[1:6]
    os.makedirs(out_dir, exist_ok=True)

    def text():
        return open(serial, errors="replace").read() if os.path.exists(serial) else ""

    def wait(pred, what, timeout=240):
        end = time.time() + timeout
        while time.time() < end:
            if pred():
                return
            time.sleep(0.2)
        print("TIMEOUT waiting for", what)
        print(text()[-3000:])
        os.kill(int(qpid), 15)
        sys.exit(1)

    wait(lambda: os.path.exists(sock_path), "the QMP socket")
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock_path)
    f = s.makefile("rw")
    f.readline()  # greeting

    def qmp(cmd, **args):
        f.write(json.dumps({"execute": cmd, "arguments": args}) + "\n")
        f.flush()
        while True:
            msg = json.loads(f.readline())
            if "return" in msg:
                return msg["return"]
            if "error" in msg:
                raise RuntimeError(msg["error"])

    qmp("qmp_capabilities")
    start = time.time()
    wait(lambda: "halo-fbdev: first frame" in text() or "halo-splash: drawn" in text(),
         "the first frame")
    # Wall time from QEMU being launched, so it includes QEMU's own start-up.
    print(f"first frame {time.time() - start + float(os.environ.get('QEMU_HEAD_START', '0')):.1f}s after QEMU started")

    def scale(v, size):
        return int(max(0, min(size - 1, v)) * ABS_MAX / (size - 1))

    def move(x, y):
        qmp("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": scale(x, W)}},
            {"type": "abs", "data": {"axis": "y", "value": scale(y, H)}},
        ])

    def button(down):
        qmp("input-send-event", events=[
            {"type": "btn", "data": {"button": "left", "down": down}}])

    def shot(name):
        ppm = os.path.join(out_dir, name + ".ppm")
        qmp("screendump", filename=ppm)
        wait(lambda: os.path.exists(ppm) and os.path.getsize(ppm) > 100, "the screendump", 30)
        time.sleep(0.3)
        write_png(ppm, os.path.join(out_dir, name + ".png"))
        os.remove(ppm)
        print("shot", name)

    for action in [a.strip() for a in actions.split(";") if a.strip()]:
        kind, _, rest = action.partition(":")
        parts = rest.split(":") if rest else []
        pt = lambda p: tuple(float(v) for v in p.split(","))
        if kind == "wait":
            time.sleep(float(parts[0]))
        elif kind == "tap":
            x, y = pt(parts[0])
            move(x, y); time.sleep(0.15); button(True); time.sleep(0.12); button(False)
        elif kind == "hold":
            x, y = pt(parts[0])
            move(x, y); time.sleep(0.15); button(True)
            time.sleep(float(parts[1]) / 1000); button(False)
        elif kind == "swipe":
            (x1, y1), (x2, y2), ms = pt(parts[0]), pt(parts[1]), float(parts[2])
            steps = max(12, int(ms / 16))  # about 60 pointer events per second
            move(x1, y1); time.sleep(0.15); button(True)
            for i in range(1, steps + 1):
                move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
                time.sleep(ms / 1000 / steps)
            button(False)
        elif kind == "shot":
            shot(parts[0] if parts else rest)
        else:
            sys.exit(f"unknown action {action!r}")

    qmp("quit")


def write_png(ppm, png):
    """PPM (P6) to PNG without an imaging library."""
    data = open(ppm, "rb").read()
    parts = data.split(b"\n", 3)
    assert parts[0] == b"P6", parts[0]
    w, h = map(int, parts[1].split())
    pix = parts[3]
    # QEMU pads each row to a 4-byte boundary, so use the real stride.
    stride = len(pix) // h
    assert stride >= w * 3 and len(pix) == stride * h, (len(pix), w, h)
    raw = b"".join(b"\x00" + pix[y * stride:y * stride + w * 3] for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(png, "wb") as out:
        out.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6))
            + chunk(b"IEND", b"")
        )


if __name__ == "__main__":
    main()
