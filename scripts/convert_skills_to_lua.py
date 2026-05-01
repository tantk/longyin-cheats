#!/usr/bin/env python3
"""Convert skills_full.dat (pipe-delimited) to skills_full.lua (native Lua table).

Lua's load() compiles a table literal ~10x faster than line-by-line pipe parsing.
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAT_PATH = os.path.join(ROOT, "data", "skills_full.dat")
LUA_PATH = os.path.join(ROOT, "data", "skills_full.lua")

FIELDS = [
    "id", "name", "type", "typeName", "rareLv", "rareName",
    "forceID", "forceName", "manaCost", "baseDmg", "atkRange",
    "upgrade", "upgradeTotal", "equip", "use", "effects",
    "atkPosture", "defPosture", "weapon", "maxUse", "dmgBonus", "desc",
    "dmgRange",
]

INT_FIELDS = {"id", "type", "rareLv", "forceID", "maxUse"}
FLOAT_FIELDS = {"manaCost", "baseDmg", "upgradeTotal"}
LIST_FIELDS = {"atkPosture", "defPosture"}


def lua_escape(s):
    """Escape a string for Lua double-quoted literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def convert():
    with open(DAT_PATH, "r", encoding="utf-8") as f:
        lines = [l.strip() for l in f if l.strip()]

    out = ["return {"]
    for line in lines:
        parts = line.split("|")
        while len(parts) < len(FIELDS):
            parts.append("")

        entry_parts = []
        for name, val in zip(FIELDS, parts):
            if name in INT_FIELDS:
                entry_parts.append(f"{name}={int(val) if val else 0}")
            elif name in FLOAT_FIELDS:
                entry_parts.append(f"{name}={float(val) if val else 0}")
            elif name in LIST_FIELDS:
                if val:
                    entry_parts.append(f"{name}={{{val}}}")
                else:
                    entry_parts.append(f"{name}={{}}")
            else:
                entry_parts.append(f'{name}="{lua_escape(val)}"')

        out.append("{" + ",".join(entry_parts) + "},")

    out.append("}")

    with open(LUA_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    dat_size = os.path.getsize(DAT_PATH)
    lua_size = os.path.getsize(LUA_PATH)
    print(f"[convert] {len(lines)} skills: {dat_size:,} bytes dat → {lua_size:,} bytes lua")


if __name__ == "__main__":
    convert()
