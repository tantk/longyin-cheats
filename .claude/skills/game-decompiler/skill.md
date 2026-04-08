---
name: game-decompiler
description: Decompile an IL2CPP Unity game binary into raw C source files. Use this skill when the user says "decompile", "analyze the DLL", "new game version", "game updated", "rerun ghidra", "rebuild decomps", or when a new GameAssembly.dll needs reverse engineering. This skill produces RAW decomps only — after it finishes, run the coverage-maximizer skill to resolve names to 100% and build the GitNexus knowledge graph.
---

# IL2CPP Game Decompiler Pipeline

Decompile a Unity IL2CPP game binary into raw C source files with a basic name index.

**Total time: ~40 minutes** for a 33MB binary with 70K+ functions.

**BEFORE STARTING:** Read `docs/reverse-engineering/pipeline-research-checklist.md` — it lists every known pitfall in the pipeline with links to reference docs. Key items: import script.json names before Ghidra analysis, verify binary/metadata version match, set MAXMEM=16G.

**IMPORTANT**: This skill produces raw decomps with ~34% name resolution. After it completes, you MUST run the `coverage-maximizer` skill to push to 100% coverage and build the GitNexus index.

## Prerequisites

Check these are installed before starting:

```bash
# JDK 21
"C:/Program Files/Eclipse Adoptium/jdk-21.0.10.7-hotspot/bin/java" -version

# Ghidra 12.0.4
ls C:/dev/gameanalysis/ghidra/support/analyzeHeadless.bat

# Il2CppDumper v6.7.46
ls C:/dev/gameanalysis/Il2CppDumper/Il2CppDumper.exe

# GitNexus
gitnexus --version
```

If any are missing, install:
- JDK 21: `winget install EclipseAdoptium.Temurin.21.JDK`
- Ghidra: Download from https://github.com/NationalSecurityAgency/ghidra/releases, extract to `C:/dev/gameanalysis/ghidra/`
- Il2CppDumper: Download from https://github.com/Perfare/Il2CppDumper/releases
- GitNexus: `npm install -g gitnexus`

Configure `C:/dev/gameanalysis/ghidra/support/launch.properties`:
```properties
JAVA_HOME_OVERRIDE=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
MAXMEM=16G
```

## Pipeline Steps

### Step 1: Copy binary to workspace (avoid paths with spaces)

```bash
mkdir -p C:/dev/gameanalysis/game_binary
cp "<GamePath>/GameAssembly.dll" C:/dev/gameanalysis/game_binary/
cp "<GamePath>/<GameName>_Data/il2cpp_data/Metadata/global-metadata.dat" C:/dev/gameanalysis/game_binary/
```

For LongYinLiZhiZhuan:
```bash
GAME="C:/Program Files (x86)/Steam/steamapps/common/LongYinLiZhiZhuan"
cp "$GAME/GameAssembly.dll" C:/dev/gameanalysis/game_binary/
cp "$GAME/LongYinLiZhiZhuan_Data/il2cpp_data/Metadata/global-metadata.dat" C:/dev/gameanalysis/game_binary/
```

### Step 2: Run Il2CppDumper (~30 seconds)

```bash
cd C:/dev/gameanalysis/Il2CppDumper
./Il2CppDumper.exe C:/dev/gameanalysis/game_binary/GameAssembly.dll \
  C:/dev/gameanalysis/game_binary/global-metadata.dat .
```

Produces: `dump.cs` (class defs), `script.json` (95K method addresses), `il2cpp.h` (C headers).

The "Press any key" error at the end is harmless — it completed.

### Step 3: Build name_index.json from script.json

```python
import json
image_base = 0x180000000
with open("C:/dev/gameanalysis/Il2CppDumper/script.json") as f:
    script = json.load(f)
name_index = {}
for entry in script['ScriptMethod']:
    va = image_base + entry['Address']
    addr_hex = f"{va:x}"
    key = f"FUN_{addr_hex}-{addr_hex}.c"
    name_index[key] = {"name": entry['Name'], "address": f"0x{addr_hex}"}
with open("C:/dev/gameanalysis/game_b_decomps_new/name_index.json", "w") as f:
    json.dump(name_index, f)
```

### Step 4: Ghidra headless analysis (~24 minutes)

**IMPORTANT:** Use `-preScript ImportIl2CppNames.java` to import all script.json function addresses BEFORE analysis. This creates function entries at all 95K+ known IL2CPP addresses, preventing ~3,100 missing decomps and improving decompilation quality.

**ALWAYS clean before import.** Ghidra leaves lock files, .gpr markers, and stale java processes that block subsequent runs. Do a full cleanup EVERY TIME:

```bash
# Step 4a: Kill stale Java/Ghidra processes and clean project
taskkill //F //IM java.exe 2>/dev/null
sleep 2
rm -rf C:/dev/gameanalysis/ghidra_project/GameAssembly.rep \
       C:/dev/gameanalysis/ghidra_project/GameAssembly.gpr \
       C:/dev/gameanalysis/ghidra_project/GameAssembly.lock

# Step 4b: Fresh import + analysis (NEVER use -overwrite, always delete first)
cmd.exe //c "C:\dev\gameanalysis\ghidra\support\analyzeHeadless.bat \
  C:\dev\gameanalysis\ghidra_project GameAssembly \
  -import C:\dev\gameanalysis\game_binary\GameAssembly.dll \
  -preScript ImportIl2CppNames.java \
  -scriptPath C:\dev\gameanalysis\ghidra_project"
```

**Do NOT use `-overwrite` flag** — it removes the old project but may not properly save the new import. Always delete project files manually first.

### Step 5: Parallel decompile export (~15 minutes)

**IMPORTANT:** Clear old decomps first, then verify no lock files before running:

```bash
# Step 5a: Clear old decomps
rm -rf C:/dev/gameanalysis/game_b_decomps_new/decomps/*
rm -f C:/dev/gameanalysis/ghidra_project/GameAssembly.lock

# Step 5b: Export
cmd.exe //c "C:\dev\gameanalysis\ghidra\support\analyzeHeadless.bat \
  C:\dev\gameanalysis\ghidra_project GameAssembly \
  -process GameAssembly.dll -noanalysis \
  -postScript ExportDecompsParallel.java \
  -scriptPath C:\dev\gameanalysis\ghidra_project"
```

This uses 8 parallel decompiler threads with 30s per-function timeout. Exports ~74K .c files to `C:/dev/gameanalysis/game_b_decomps_new/decomps/`.

Key performance facts:
- Single-threaded: ~250 funcs/min (3+ hours total)
- 8-thread parallel: ~1000 funcs/min (~15 min for remaining)
- The script skips already-exported files (resumable after interruption)

## Done

When this skill finishes, tell the user:

> Decompilation complete. Raw decomps at `game_b_decomps_new/decomps/` with ~34% name resolution.
> Run `/coverage-maximizer` next to push to 100% coverage and build the GitNexus knowledge graph.

## Troubleshooting

### "Unable to lock project" or "Project marker file already exists"
Ghidra leaves lock files and .gpr markers from previous runs. **Always clean before import:**
```bash
taskkill //F //IM java.exe 2>/dev/null
sleep 2
rm -rf C:/dev/gameanalysis/ghidra_project/GameAssembly.rep \
       C:/dev/gameanalysis/ghidra_project/GameAssembly.gpr \
       C:/dev/gameanalysis/ghidra_project/GameAssembly.lock
```
Never use `-overwrite` — it empties the project without properly saving the new import.

### "Requested project program file(s) not found"
The project exists but is empty (usually after a failed `-overwrite`). Delete the entire project (see above) and re-import.

### "PyGhidra not available" error
Ghidra 12 uses PyGhidra, not Jython. Python scripts (.py) won't run. Use Java scripts (.java) instead.

### Path with spaces breaks analyzeHeadless.bat
Copy files to a space-free path like `C:/dev/gameanalysis/game_binary/`.

### Export seems stuck
Check progress: `ls decomps/ | wc -l`. Some complex functions take 30s each (the timeout limit). Check java.exe memory usage — should grow to 500MB+.

## Output (this skill only)

| Output | Location | Size |
|--------|----------|------|
| Raw decomps | `game_b_decomps_new/decomps/` | 74K files |
| Name index (basic) | `game_b_decomps_new/name_index.json` | 63K methods |
| Il2CppDumper | `Il2CppDumper/dump.cs, script.json, il2cpp.h` | |
