---
name: ct-updater
description: Update the cheat table after a game binary update. Verifies and fixes CT hooks, field offsets, and AOB signatures against the new GameAssembly.dll. Use this skill after running /game-update and getting the RVA diff report, or when the user says "fix CT", "update cheat table", "CT broken", "verify cheats", "cheats not working after update", "patch the CT", or when the diff report shows SHIFTED/REMOVED entries. This skill is specifically for LongYinLiZhiZhuan CT maintenance — do not use for creating new cheats (use /cheat-creator instead).
---

# CT Updater — Fix Cheat Table After Game Update

After `/game-update` produces a diff report showing what changed, this skill guides fixing the CT so all cheats work on the new binary.

## Prerequisites

- `/game-update` has been run (or at minimum, new `script.json` and `dump.cs` exist)
- RVA diff report at `C:/dev/gameanalysis/game_b_decomps_new/rva_diff_*.md`
- CT file at `patches/LongYinLiZhiZhuan.CT`

## Step 1: Read the Diff Report

Read the latest `rva_diff_*.md` from `C:/dev/gameanalysis/game_b_decomps_new/`.

Check:
- **CT Impact table** — any SHIFTED or REMOVED entries need fixing
- **Methods shifted count** — if 0, CT is likely fine with no changes
- **Methods added/removed** — new methods may enable new cheats, removed ones break existing hooks

## Step 2: Assess CT Resolution Patterns

The CT (v7+) uses three resolution patterns. Each has different update sensitivity:

| Pattern | Used by | Breaks on update? | Fix needed? |
|---|---|---|---|
| **Dynamic resolution** (`il2cpp_class_get_method_from_name`) | Member Limit, NoCost, Talent Slots, Item Adder methods | Almost never — resolves by class+method name | Only if class/method was renamed or removed |
| **AOB signatures** (`AOB_SIGS` table) | Item Adder (setBook, setMat, ctor, clone) | Sometimes — if the compiler changed instruction layout | Update the byte pattern |
| **Field offsets** (`hero + 0x220`, etc.) | All field-reading cheats (Money, Weight, Stats, etc.) | If class layout changed (fields added/removed/reordered) | Update offset values |

### Priority order:
1. Fix any SHIFTED/REMOVED methods in the CT Impact table (Step 3)
2. Verify AOB signatures still match (Step 4)
3. Verify field offsets haven't changed (Step 5)
4. Runtime test with CE MCP (Step 6)

## Step 3: Fix Broken Method References

If the diff report shows SHIFTED or REMOVED CT entries:

**For dynamically resolved methods** (v7 pattern): Usually no fix needed — `il2cpp_class_get_method_from_name` resolves by name at runtime. But verify the method still exists:

```bash
grep "MethodName" C:/dev/gameanalysis/Il2CppDumper/dump.cs
```

If the method was **renamed**: update the string in the CT's `writeString(nm, "MethodName")` call.
If the method was **removed**: the cheat needs redesign — escalate to user.

**For hardcoded RVAs** (should be none in v7+, but check): Convert to dynamic resolution following the pattern used by NoCost/MemberLimit cheats. See the CT's `_il2cpp_init()` and `il2cpp_class_get_method_from_name` pattern.

## Step 4: Verify AOB Signatures

The CT has 4 AOB signatures in the `AOB_SIGS` table:

```
setBook  = {sig="48 8B 43 68 48 85 C0 0F 84 ?? ?? ?? ?? 89 78 10", off=0x3F}
setMat   = {sig="89 6B 18 89 73 3C 89 7B 40", off=0x48}
ctor     = {sig="C7 47 44 00 00 80 3F 48 8B CF E8 ?? ?? ?? ?? 89 5F 14 83 FB 06", off=0x6A}
clone    = {sig="48 89 5C 24 08 57 48 83 EC 20 48 8B D9 E8 ?? ?? ?? ?? 48 8B F8 48 85 C0 74", off=0}
```

To verify (requires CE MCP with game running):

```
Use mcp__cheatengine__aob_scan to scan for each signature in GameAssembly.dll.
If a signature returns 0 results, it's broken and needs updating.
```

To fix a broken AOB:
1. Find the method's new address from the new `script.json` (look up by method name)
2. Use `mcp__cheatengine__disassemble` at the new address to get the new bytes
3. Build a new AOB pattern with `??` wildcards for operand bytes
4. Update `AOB_SIGS` in the CT

If CE isn't running, do static verification:
1. Look up the method in `dump.cs` to get the new RVA
2. Check the new decomp file for structural changes
3. If the method signature/body is unchanged, the AOB likely still works

## Step 5: Verify Field Offsets

Field offsets are the most common breakage point. The CT uses ~60 hardcoded offsets.

### Key offsets to verify (highest impact):

**HeroData class:**
- `0x220` — ItemListData pointer
- `0x1C0` — Sect Currency (float)
- `0x35C` — Talent Points (float)
- `0x84` — belongForceID
- `0x178` — Current HP, `0x17C` — Max HP

**ItemListData class:**
- `0x18` — Money, `0x20` — Max Weight, `0x28` — Items list

**WorldData class:**
- `0x50` — HerosList, `0x48` — Forces list
- `0x1D0` — Battle speed multiplier

**ForceData class:**
- `0x128` — Current research ID, `0x130` — TechLevelData list

### How to verify:

**Static check** — compare class definitions in old vs new `dump.cs`:
```bash
# Extract HeroData from old and new dump.cs and diff
grep -A 100 "class HeroData " C:/dev/gameanalysis/game_binary_versions/<old-date>/dump.cs > /tmp/old_hero.txt
grep -A 100 "class HeroData " C:/dev/gameanalysis/Il2CppDumper/dump.cs > /tmp/new_hero.txt
diff /tmp/old_hero.txt /tmp/new_hero.txt
```

If fields were added before the ones we use, all offsets after that point shift. Update accordingly.

**Runtime check** (CE MCP with game running):
```
Use mcp__cheatengine__read_integer or read_memory to verify known values at expected offsets.
For example, read hero + 0x84 (belongForceID) — should be a small integer (1-20).
If it returns garbage, the offset shifted.
```

### Auto-detection already in the CT

The CT has auto-detection for two known-fragile offsets:
- `S.OFF_MEDFOOD` — defaults to 0x68, falls back to 0x60 for early f7
- `S.OFF_HORSE` — defaults to 0x88, falls back to 0x80 for early f7

If more offsets become fragile, add similar auto-detection in `discover()`.

## Step 6: Runtime Test (CE MCP)

If Cheat Engine is running with the bridge loaded:

1. `mcp__cheatengine__ping` — verify connection
2. `mcp__cheatengine__get_process_info` — verify attached to game
3. Test each cheat category:
   - Enable Money cheat → verify no error, value changes
   - Enable Member Limit → verify no error
   - Enable Talent Slots → verify no error
   - Try Item Adder → verify item appears in inventory
4. Disable all cheats → verify clean restore

If CE is not running, document which cheats need runtime testing and remind the user.

**Important:** Always test with a FRESH CE attach (close CE, reopen, reattach). Stale cache bugs in `_il2cpp_init()` only appear on first use after attach — the IL2CPP class loading race condition means some classes may not have their static fields ready yet. The `ensure()` function handles this by refreshing stale `static=0` pointers, but new cheats must be tested on cold start to verify they work.

## Step 7: Commit

After all fixes verified:

```bash
git add patches/LongYinLiZhiZhuan.CT
git commit -m "Update CT for <new-date> game binary — <summary of changes>"
```

## Common Patterns

### Binary delta is small (<1KB), uniform shift
Most likely: code shifted, layouts unchanged. AOBs and field offsets usually survive.
Action: verify AOBs, spot-check 2-3 field offsets, done.

### Binary delta is large (>100KB) or methods added/removed
Likely: new content, possible class layout changes.
Action: full field offset verification via dump.cs diff. Check all AOBs.

### Method renamed or removed
Check `dump.cs` for the class — method may have been renamed, merged, or split.
Search decomps for similar functionality if the method is gone.

## Files Reference

| File | Purpose |
|---|---|
| `patches/LongYinLiZhiZhuan.CT` | The cheat table to fix |
| `C:/dev/gameanalysis/game_b_decomps_new/rva_diff_*.md` | Diff report from /game-update |
| `C:/dev/gameanalysis/Il2CppDumper/dump.cs` | New class/method definitions with offsets |
| `C:/dev/gameanalysis/Il2CppDumper/script.json` | New method address mappings |
| `C:/dev/gameanalysis/game_binary_versions/<date>/` | Archived old binaries + indices |
