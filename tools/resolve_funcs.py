"""Resolve FUN_ addresses in Ghidra decompiled code to C# method names.

Usage:
  python tools/resolve_funcs.py "FUN_18078e440"
  python tools/resolve_funcs.py --file decompiled.c
  python tools/resolve_funcs.py --query "MATCH (f:Function) WHERE f.name = 'GameController__GenerateRandomEvent' RETURN f.content"
"""
import json
import re
import sys
import os

NAME_INDEX = "C:/dev/gameanalysis/game_b_decomps/name_index.json"
MANUAL_NAMES = os.path.join(os.path.dirname(__file__), "manual_names.json")
_cache = None

def load_index():
    global _cache
    if _cache is None:
        with open(NAME_INDEX, 'r') as f:
            raw = json.load(f)
        # Build addr -> name lookup
        _cache = {}
        for key, val in raw.items():
            addr = val.get('address', '')
            if addr.startswith('0x'):
                _cache[addr[2:].lower()] = val['name']
            # Also index from the key pattern FUN_ADDR-ADDR.c
            m = re.match(r'FUN_([0-9a-fA-F]+)', key)
            if m:
                _cache[m.group(1).lower()] = val['name']
        # Load manual names (override/supplement)
        if os.path.exists(MANUAL_NAMES):
            with open(MANUAL_NAMES, 'r') as f:
                manual = json.load(f)
            for key, name in manual.items():
                if key.startswith('_'):
                    continue
                m = re.match(r'FUN_([0-9a-fA-F]+)', key)
                if m:
                    _cache[m.group(1).lower()] = name
    return _cache

def resolve_address(addr_hex):
    """Resolve a single hex address to a C# name."""
    idx = load_index()
    addr = addr_hex.lower().replace('0x', '')
    return idx.get(addr)

def resolve_text(text):
    """Replace all FUN_XXXX references in text with C# names."""
    idx = load_index()
    def replacer(m):
        addr = m.group(1).lower()
        name = idx.get(addr)
        if name:
            return f'{name}/*{m.group(0)}*/'
        return m.group(0)
    return re.sub(r'FUN_([0-9a-fA-F]+)', replacer, text)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: resolve_funcs.py <address|--file path|--stdin>")
        sys.exit(1)

    if sys.argv[1] == '--file':
        with open(sys.argv[2], 'r') as f:
            print(resolve_text(f.read()))
    elif sys.argv[1] == '--stdin':
        print(resolve_text(sys.stdin.read()))
    else:
        # Single address or FUN_ reference
        addr = sys.argv[1].replace('FUN_', '').replace('0x', '')
        name = resolve_address(addr)
        if name:
            print(f'0x{addr} => {name}')
        else:
            print(f'0x{addr} => NOT FOUND')
