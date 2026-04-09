#!/usr/bin/env python3
"""Build script: packs CheatTable/ into a distributable .CT file."""

import glob
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CT_DIR = os.path.join(ROOT, "CheatTable")
DIST_DIR = os.path.join(ROOT, "dist")
BUILD_ENV = os.path.join(ROOT, "BUILD_ENV")
DATA_DIR = os.path.join(ROOT, "data")


def read_build_env():
    """Read BUILD_ENV key=value pairs."""
    env = {}
    with open(BUILD_ENV) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def is_cea_file(filepath):
    """Check if file has AA directives ({$lua}, [ENABLE], etc.)."""
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            content = f.read(500)
            return "{$lua}" in content or "[ENABLE]" in content
    except Exception:
        return False


def lint_lua(luacheck_path="luacheck"):
    """Run luacheck on all .lua and .cea files in CheatTable/."""
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    from lint_cea import lint_file as lint_cea_file

    lua_files = glob.glob(os.path.join(CT_DIR, "**", "*.lua"), recursive=True)
    cea_files = glob.glob(os.path.join(CT_DIR, "**", "*.cea"), recursive=True)

    errors = 0
    checked = 0

    for f in lua_files:
        result = subprocess.run(
            [luacheck_path, f, "--no-color"],
            capture_output=True, text=True, cwd=ROOT
        )
        output = result.stdout or result.stderr
        if result.returncode >= 2:
            print(output)
            errors += 1
        checked += 1

    for f in cea_files:
        if is_cea_file(f):
            has_issues, output = lint_cea_file(f, luacheck_path)
            if has_issues and output:
                m = re.search(r'(\d+) errors?', output)
                if m and int(m.group(1)) > 0:
                    print(output)
                    errors += 1
            checked += 1

    if errors:
        print(f"\n[lint] {errors}/{checked} file(s) have errors")
        return False
    print(f"[lint] {checked} files OK")
    return True


def build():
    env = read_build_env()
    table_ver = env.get("TABLE_VERSION", "0.0.0")
    game_ver = env.get("GAME_VERSION", "unknown")

    print(f"Building LongYin CT v{table_ver} (game {game_ver})")

    # Step 1: Pack ALL data files into CheatTable/Files/
    files_dir = os.path.join(CT_DIR, "Files")
    os.makedirs(files_dir, exist_ok=True)
    # Clean stale files
    DATA_EXTS = ('.dat', '.lua')
    embeddable = {f for f in os.listdir(DATA_DIR)
                  if any(f.endswith(ext) for ext in DATA_EXTS)
                  and os.path.isfile(os.path.join(DATA_DIR, f))}
    for fname in os.listdir(files_dir):
        fpath = os.path.join(files_dir, fname)
        if not os.path.isfile(fpath):
            continue
        base_name = fname[:-4] if fname.endswith('.xml') else fname
        if base_name not in embeddable and any(base_name.endswith(ext) for ext in DATA_EXTS):
            os.remove(fpath)
    # Copy data files
    count = 0
    for fname in sorted(embeddable):
        src = os.path.join(DATA_DIR, fname)
        dst = os.path.join(files_dir, fname)
        shutil.copy2(src, dst)
        xml_path = dst + ".xml"
        if not os.path.exists(xml_path):
            with open(xml_path, "w", encoding="utf-8") as f:
                f.write(f"<File>\n  <Name>{fname}</Name>\n</File>\n")
        count += 1
    print(f"[pack_data] {count} files → CheatTable/Files/")

    # Step 2: Concatenate src/*.lua → CheatTable/LuaScript.lua
    src_dir = os.path.join(ROOT, "src")
    lua_script_path = os.path.join(CT_DIR, "LuaScript.lua")
    src_files = sorted(glob.glob(os.path.join(src_dir, "*.lua")))
    if not src_files:
        print("[build] No src/*.lua files found!")
        sys.exit(1)
    parts = []
    for sf in src_files:
        with open(sf, "r", encoding="utf-8") as f:
            parts.append(f.read())
    # Wrap modules after 00_init in pcall so load errors are visible
    # 00_init.lua defines MT={} and must run unwrapped
    init_part = parts[0]  # 00_init.lua
    rest_parts = "\n".join(parts[1:])
    combined = init_part + "\n" + \
        'local _mtLoadOk, _mtLoadErr = pcall(function()\n' + \
        rest_parts + "\n" + \
        'end)\n' + \
        'if not _mtLoadOk then\n' + \
        '  MT._loadError = tostring(_mtLoadErr)\n' + \
        '  print("[MT] LOAD ERROR: " .. MT._loadError)\n' + \
        '  showMessage("修改器加载出错 / Load error:\\n\\n" .. MT._loadError)\n' + \
        'end\n'
    with open(lua_script_path, "w", encoding="utf-8") as f:
        f.write(combined)
    print(f"[concat] {len(src_files)} src/*.lua → LuaScript.lua ({len(combined):,} chars)")

    # Step 3: Inject LuaScript.lua into .xml
    xml_path = os.path.join(CT_DIR, ".xml")
    tree = ET.parse(xml_path)
    root = tree.getroot()
    ls = root.find("LuaScript")
    if ls is None:
        ls = ET.SubElement(root, "LuaScript")
    ls.text = "\n" + combined + "\n  "
    tree.write(xml_path, encoding="unicode", xml_declaration=False)
    print(f"[inject] LuaScript.lua → .xml ({len(combined):,} chars)")

    # Step 4: Lint (non-fatal)
    luacheck = shutil.which("luacheck") or os.path.join("C:", os.sep, "tools", "luacheck.exe")
    if os.path.exists(luacheck):
        lint_lua(luacheck)
    else:
        print("[lint] luacheck not found, skipping")

    # Step 5: CE2FS pack → dist/*.CT
    os.makedirs(DIST_DIR, exist_ok=True)
    out_path = os.path.join(DIST_DIR, "LongYinLiZhiZhuan.CT")
    subs = [f"{k}={v}" for k, v in env.items()]
    cmd = ["ce2fs", "-i", CT_DIR, "-o", out_path] + subs
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[build] FAILED:")
        print(result.stderr or result.stdout)
        sys.exit(1)

    size = os.path.getsize(out_path)
    print(f"[build] {out_path} ({size:,} bytes)")
    print("[build] Done!")


if __name__ == "__main__":
    if "--lint-only" in sys.argv:
        luacheck = shutil.which("luacheck") or os.path.join("C:", os.sep, "tools", "luacheck.exe")
        if not os.path.exists(luacheck):
            print("[lint] luacheck not found")
            sys.exit(1)
        ok = lint_lua(luacheck)
        sys.exit(0 if ok else 1)
    build()
