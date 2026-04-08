---
name: game-update
description: Handle a game binary update end-to-end. Detects DLL changes, archives old version, runs the full decompile and coverage pipeline, and produces an RVA diff report with cheat table impact analysis. Use when the user says "game updated", "new version", "update decomps", "rebuild call graph", "check for DLL changes", "new patch", or after Steam updates the game.
---

# Game Update Pipeline

**BEFORE STARTING:** Read `docs/reverse-engineering/pipeline-research-checklist.md` — the full checklist covers every known pitfall across the pipeline. This skill orchestrates game-decompiler + coverage-maximizer, so all their checklist items apply.

Orchestrates the full update pipeline when the game binary changes: detect, archive, decompile, resolve, index, and report.

**Total time: ~45 minutes** (mostly Ghidra analysis + parallel export).

## Paths

| Item | Path |
|---|---|
| Game install | `C:/Program Files (x86)/Steam/steamapps/common/LongYinLiZhiZhuan/` |
| Analysis workspace | `C:/dev/gameanalysis/` |
| Current binary | `C:/dev/gameanalysis/game_binary/` |
| Version archives | `C:/dev/gameanalysis/game_binary_versions/` |
| Decomps (new) | `C:/dev/gameanalysis/game_b_decomps_new/` |
| Il2CppDumper output | `C:/dev/gameanalysis/Il2CppDumper/` |
| Cheat table | `C:/dev/longyin-cheats/patches/LongYinLiZhiZhuan.CT` |
| RVA diff tool | `C:/dev/longyin-cheats/tools/rva_diff.py` |

## Phase 1: Detect Binary Changes

Compare hashes of the current archived DLL vs the live game DLL:

```bash
sha256sum "C:/dev/gameanalysis/game_binary/GameAssembly.dll"
sha256sum "C:/Program Files (x86)/Steam/steamapps/common/LongYinLiZhiZhuan/GameAssembly.dll"
```

- If hashes match: report "No binary changes detected" and **stop**.
- If hashes differ: report the size delta and proceed.

Also check global-metadata.dat:
```bash
sha256sum "C:/dev/gameanalysis/game_binary/global-metadata.dat"
sha256sum "C:/Program Files (x86)/Steam/steamapps/common/LongYinLiZhiZhuan/LongYinLiZhiZhuan_Data/il2cpp_data/Metadata/global-metadata.dat"
```

## Phase 2: Archive Old Version

1. Get the modification date of the **old** `C:/dev/gameanalysis/game_binary/GameAssembly.dll`:
```bash
stat -c %y "C:/dev/gameanalysis/game_binary/GameAssembly.dll" | cut -d' ' -f1
```

2. Create the versioned archive directory:
```bash
DATE=$(stat -c %y "C:/dev/gameanalysis/game_binary/GameAssembly.dll" | cut -d' ' -f1)
ARCHIVE="C:/dev/gameanalysis/game_binary_versions/$DATE"

# Handle same-day collision
if [ -d "$ARCHIVE" ]; then
  i=2; while [ -d "${ARCHIVE}_${i}" ]; do i=$((i+1)); done
  ARCHIVE="${ARCHIVE}_${i}"
fi

mkdir -p "$ARCHIVE"
```

3. Copy old files into the archive:
```bash
cp C:/dev/gameanalysis/game_binary/GameAssembly.dll "$ARCHIVE/"
cp C:/dev/gameanalysis/game_binary/global-metadata.dat "$ARCHIVE/"
cp C:/dev/gameanalysis/Il2CppDumper/script.json "$ARCHIVE/" 2>/dev/null
cp C:/dev/gameanalysis/Il2CppDumper/dump.cs "$ARCHIVE/" 2>/dev/null
cp C:/dev/gameanalysis/game_b_decomps_new/name_index.json "$ARCHIVE/" 2>/dev/null
cp C:/dev/gameanalysis/game_b_decomps_new/manual_names.json "$ARCHIVE/" 2>/dev/null
```

Report: "Archived old binary to `game_binary_versions/<DATE>/`"

## Phase 3: Copy New Binaries

```bash
GAME="C:/Program Files (x86)/Steam/steamapps/common/LongYinLiZhiZhuan"
cp "$GAME/GameAssembly.dll" C:/dev/gameanalysis/game_binary/
cp "$GAME/LongYinLiZhiZhuan_Data/il2cpp_data/Metadata/global-metadata.dat" C:/dev/gameanalysis/game_binary/
```

Verify:
```bash
ls -la C:/dev/gameanalysis/game_binary/GameAssembly.dll
ls -la C:/dev/gameanalysis/game_binary/global-metadata.dat
```

Both files must be non-zero size.

## Phase 4: Decompile (~40 min)

Invoke the `/game-decompiler` skill. It handles:
1. Il2CppDumper (~30 sec) -> script.json, dump.cs, il2cpp.h
2. Build name_index.json from script.json
3. Ghidra headless analysis (~24 min)
4. Parallel decompile export (~15 min, 8 threads)

Wait for it to complete before proceeding.

## Phase 5: Resolve + Index (~5 min)

Invoke the `/coverage-maximizer` skill. It handles:
1. 9 resolution techniques -> 100% function name coverage
2. Verification (must confirm 100.00%)
3. Git init + commit in decomps_resolved/
4. GitNexus analyze -> knowledge graph rebuild

Wait for it to complete before proceeding.

## Phase 6: RVA Diff Report

Run the diff tool using the archived old script.json and the new one:

```bash
OLD_DATE="<date from Phase 2>"
NEW_DATE=$(stat -c %y "C:/dev/gameanalysis/game_binary/GameAssembly.dll" | cut -d' ' -f1)
OLD_SIZE=$(stat -c %s "C:/dev/gameanalysis/game_binary_versions/$OLD_DATE/GameAssembly.dll")
NEW_SIZE=$(stat -c %s "C:/dev/gameanalysis/game_binary/GameAssembly.dll")

python C:/dev/longyin-cheats/tools/rva_diff.py \
  "C:/dev/gameanalysis/game_binary_versions/$OLD_DATE/script.json" \
  "C:/dev/gameanalysis/Il2CppDumper/script.json" \
  --ct "C:/dev/longyin-cheats/patches/LongYinLiZhiZhuan.CT" \
  --old-dll-size "$OLD_SIZE" \
  --new-dll-size "$NEW_SIZE" \
  --old-date "$OLD_DATE" \
  --new-date "$NEW_DATE" \
  -o "C:/dev/gameanalysis/game_b_decomps_new/rva_diff_${OLD_DATE}_vs_${NEW_DATE}.md"
```

## Phase 7: dump.cs Class Diff (Field Offset Changes)

Field offset changes break cheats more often than RVA shifts. Compare key classes between old and new dump.cs to detect added/removed/reordered fields.

**Classes to diff** (these have hardcoded offsets in the CT):

| Class | Key offsets used | CT impact if changed |
|---|---|---|
| HeroData | 0x84 belongForceID, 0x178 HP, 0x17C MaxHP, 0x1A0-0x1A8 injuries, 0x1C0 sectCurrency, 0x220 itemListData, 0x35C talentPoints | All stat/resource cheats break |
| ItemListData | 0x18 money, 0x20 maxWeight, 0x28 items | Money, inventory cheats |
| ItemData | 0x10 itemID, 0x14 type, 0x18 subType, 0x20 name, 0x40 rareLv, 0x60 equipmentData | Item adder, max rarity |
| WorldData | 0x48 forces, 0x50 herosList, 0x80 events, 0xB0 timeDiff, 0x1D0 battleSpeed, 0x228 meteorite | Faction, exploration, battle cheats |
| ForceData | 0x10 forceID, 0x18 forceName, 0xD0 favorList, 0x128 researchID, 0x170 contribution | Sect management cheats |
| GameDataController | 0x90 speAddDataBase, 0xF0-0x108 equipDBs, 0x110 medDB, 0x118 foodDB, 0x128 skillDB, 0x198 tagDataBase | Item generation, talent buffs |
| GlobalData | 0x68 versionName, 0x70 fixName, 0x130 skillLimit | Version detect, skill limit |
| KungfuSkillData | 0x14 id, 0x20 name, 0x30 type, 0x34 rareLv, 0x48 addDmg, 0x58-0x68 speAddData, 0x70 atkRange, 0xC8 hide | Martial arts tab |
| StartMenuController | 0x80 attrPts, 0x84 fightPts, 0x88 livingPts | Character creation cheats |
| StartGameSettingController | 0x18 player | Creation talent points |

**How to diff:**

```bash
OLD_DUMP="C:/dev/gameanalysis/game_binary_versions/$OLD_DATE/dump.cs"
NEW_DUMP="C:/dev/gameanalysis/Il2CppDumper/dump.cs"

# For each critical class, extract and compare
for CLASS in HeroData ItemListData ItemData WorldData ForceData GameDataController GlobalData KungfuSkillData StartMenuController StartGameSettingController; do
  echo "=== $CLASS ==="
  diff <(grep -A 80 "^public class $CLASS " "$OLD_DUMP" | head -80) \
       <(grep -A 80 "^public class $CLASS " "$NEW_DUMP" | head -80)
done
```

**If fields shifted:**
- Fields added before a used offset → all offsets after it shift by field size (typically +8 for reference types, +4 for int/float, +1 for bool)
- Update the hardcoded offsets in `src/04_hook.lua` (equipDBs, discover), `src/09_data.lua` (readSpeDict, loadStatNames), `src/12_cheats_stats.lua` (hero offsets), and the .cea form code
- Fields removed → same but offsets decrease
- Fields reordered → compare old vs new offset comments in dump.cs

**If no field changes:** Report "Class layouts unchanged — field offsets are safe."

## Done

When complete, report to the user:

1. Summary: methods shifted/added/removed
2. CT impact: which hardcoded RVAs need updating (if any)
3. **Class layout changes**: which classes had fields added/removed/reordered, and which offsets need updating
4. Full report location: `game_b_decomps_new/rva_diff_*.md`

If any CT entries show **SHIFTED** or **REMOVED**, or any class layouts changed, remind the user to run the CT fix skill (or manually update addresses/offsets).
