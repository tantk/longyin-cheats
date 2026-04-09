#!/usr/bin/env python3
"""Release script: bump version, commit, tag, push. CI builds the CT.

Usage:
    python scripts/release.py          # patch bump (1.0.1 → 1.0.2)
    python scripts/release.py minor    # minor bump (1.0.1 → 1.1.0)
    python scripts/release.py major    # major bump (1.0.1 → 2.0.0)
    python scripts/release.py 1.2.3    # explicit version
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION_FILE = os.path.join(ROOT, "VERSION")
BUILD_ENV = os.path.join(ROOT, "BUILD_ENV")


def read_version():
    with open(VERSION_FILE) as f:
        return f.read().strip()


def bump(current, kind):
    parts = current.split(".")
    if len(parts) != 3:
        print(f"Bad version format: {current}")
        sys.exit(1)
    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
    if kind == "patch":
        patch += 1
    elif kind == "minor":
        minor += 1
        patch = 0
    elif kind == "major":
        major += 1
        minor = 0
        patch = 0
    else:
        print(f"Unknown bump type: {kind}")
        sys.exit(1)
    return f"{major}.{minor}.{patch}"


def write_version(ver):
    with open(VERSION_FILE, "w") as f:
        f.write(ver + "\n")
    # Update BUILD_ENV
    with open(BUILD_ENV) as f:
        content = f.read()
    content = re.sub(r"TABLE_VERSION=.*", f"TABLE_VERSION={ver}", content)
    with open(BUILD_ENV, "w") as f:
        f.write(content)


def run(cmd, **kwargs):
    print(f"  $ {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=ROOT, **kwargs)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)
    if result.stdout.strip():
        print(f"  {result.stdout.strip()}")
    return result


def main():
    current = read_version()
    arg = sys.argv[1] if len(sys.argv) > 1 else "patch"

    if re.match(r"^\d+\.\d+\.\d+$", arg):
        new_ver = arg
    else:
        new_ver = bump(current, arg)

    tag = f"v{new_ver}"
    print(f"Release: {current} → {new_ver} (tag: {tag})")
    print()

    # Check clean working tree
    result = subprocess.run("git status --porcelain", shell=True, capture_output=True, text=True, cwd=ROOT)
    if result.stdout.strip():
        print("Working tree not clean. Commit or stash changes first.")
        sys.exit(1)

    # Check tag doesn't exist
    result = subprocess.run(f"git tag -l {tag}", shell=True, capture_output=True, text=True, cwd=ROOT)
    if result.stdout.strip():
        print(f"Tag {tag} already exists!")
        sys.exit(1)

    # Bump version
    write_version(new_ver)
    print(f"Updated VERSION → {new_ver}")
    print(f"Updated BUILD_ENV → TABLE_VERSION={new_ver}")
    print()

    # Commit + tag + push
    run(f'git add VERSION BUILD_ENV')
    run(f'git commit -m "Release {tag}"')
    run(f'git tag {tag}')
    run(f'git push origin main')
    run(f'git push origin {tag}')

    print()
    print(f"Released {tag}!")
    print(f"CI will build CT: https://github.com/tantk/longyin-cheats/actions")
    print(f"Release page: https://github.com/tantk/longyin-cheats/releases/tag/{tag}")


if __name__ == "__main__":
    main()
