#!/usr/bin/env python3
"""Interim recipe runner until the `halo` build driver exists (D-009).

    tools/recipe.py <name> [--force]

Reads build/recipes/<name>.toml, builds its `deps` first, fetches the pinned
source(s) named in third_party/manifest.toml (checksum verified), unpacks them
into $HALO_OUT and runs the steps with bash. A stamp records a finished recipe,
keyed by the recipe and the manifest entries, so nothing is rebuilt needlessly.

Environment given to steps: SRC (the first source), SRC_<NAME> for each source,
BUILD, SYSROOT, HALO_OUT, HALO_REPO, JOBS.
"""
import hashlib
import os
import subprocess
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = Path(os.environ.get("HALO_OUT", Path.home() / "halo-out"))
CACHE = Path(os.environ.get("HALO_SRC", Path.home() / ".cache/halo/src"))
SYSROOT = OUT / "sysroot"


def manifest_source(name):
    data = tomllib.loads((REPO / "third_party/manifest.toml").read_text())
    for s in data.get("source", []):
        if s["name"] == name:
            return s
    sys.exit(f"recipe: no [[source]] named {name!r} in third_party/manifest.toml")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch(src):
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / src["url"].rsplit("/", 1)[1]
    if not dest.exists():
        print(f"fetch {src['url']}", flush=True)
        part = dest.with_suffix(dest.suffix + ".part")
        subprocess.run(["curl", "-fsSL", "-o", str(part), src["url"]], check=True)
        part.rename(dest)
    got = sha256(dest)
    if got != src["sha256"]:
        sys.exit(f"recipe: checksum mismatch for {dest.name}\n  want {src['sha256']}\n  got  {got}")
    return dest


def unpack(src, archive):
    """Unpack into $HALO_OUT and return the source directory."""
    if archive.name.endswith(".zip"):
        dest = OUT / f"{src['name']}-{src['version']}"
        if not dest.exists():
            tmp = dest.with_name(dest.name + ".part")
            tmp.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(archive) as z:
                z.extractall(tmp)
            tmp.rename(dest)
        return dest
    with tarfile.open(archive) as t:
        top = t.getnames()[0].split("/")[0]
        dest = OUT / top
        if not dest.exists():
            t.extractall(OUT, filter="data")
    return dest


def run_recipe(name, force, done):
    if name in done:
        return
    recipe = tomllib.loads((REPO / f"build/recipes/{name}.toml").read_text())
    for dep in recipe.get("deps", []):
        run_recipe(dep, force, done)

    names = recipe["source"]
    names = [names] if isinstance(names, str) else names
    sources = [manifest_source(n) for n in names]

    key = hashlib.sha256()
    key.update((REPO / f"build/recipes/{name}.toml").read_bytes())
    for s in sources:
        key.update(repr(sorted(s.items())).encode())
    stamp = OUT / "stamps" / name
    if not force and stamp.exists() and stamp.read_text() == key.hexdigest():
        print(f"{name}: up to date")
        done.add(name)
        return

    env = dict(os.environ)
    env.update(
        HALO_OUT=str(OUT),
        HALO_REPO=str(REPO),
        SYSROOT=str(SYSROOT),
        BUILD=str(OUT / "build" / name),
        JOBS=str(os.cpu_count() or 2),
    )
    for i, s in enumerate(sources):
        srcdir = unpack(s, fetch(s))
        if i == 0:
            env["SRC"] = str(srcdir)
        env["SRC_" + s["name"].upper().replace("-", "_")] = str(srcdir)

    SYSROOT.mkdir(parents=True, exist_ok=True)
    for step in recipe.get("step", []):
        print(f"{name}: {step['name']}", flush=True)
        subprocess.run(["bash", "-ec", step["run"]], env=env, check=True)

    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(key.hexdigest())
    print(f"{name}: done", flush=True)
    done.add(name)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit(__doc__)
    run_recipe(args[0], "--force" in sys.argv, set())


if __name__ == "__main__":
    main()
