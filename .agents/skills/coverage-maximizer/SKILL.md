---
name: coverage-maximizer
description: Maximize function name coverage in decompiled IL2CPP code to reach 100%. Use this skill after running the game-decompiler pipeline, when decomps have low coverage (many FUN_xxx references), or when the user says "increase coverage", "resolve names", "name the functions", "too many FUN_xxx", "100% coverage". Applies multiple high-accuracy techniques in order, then auto-describes remaining functions.
---

# Coverage Maximizer — 100% Function Name Resolution

**BEFORE STARTING:** Read `docs/reverse-engineering/pipeline-research-checklist.md` — specifically the "Before Name Resolution" and "Before GitNexus Indexing" sections. Key rules: use valid C identifiers only (no dots, no inline comments), sanitize all special characters.

After Ghidra decompilation, only ~34% of FUN_ references are resolved by the Il2CppDumper name_index alone. This skill applies 7 techniques in priority order to reach 100%.

## Technique Overview (apply in this order)

| # | Technique | Accuracy | Functions Named | Cumulative |
|---|-----------|----------|-----------------|------------|
| 1 | Il2CppDumper name_index | ~99% | ~63,000 | 34% |
| 2 | DLL export symbols | 100% | ~220 | 70% |
| 3 | Thunk resolution (pass 1) | ~99% | ~1,300 | 90% |
| 4 | Top runtime function ID | ~95% | ~20 | 94% |
| 5 | Code similarity matching | ~95% | ~200 | 96% |
| 6 | Thunk resolution (pass 2+3) | ~99% | ~1,000 | 96.5% |
| 7 | Ghidra Function ID extraction | 99% | ~250 | 97% |
| 8 | String-referenced functions | ~90% | ~65 | 97.1% |
| 9 | Auto-describe remaining | Descriptive | ~11,000 | **100%** |

## Implementation

### Prerequisites
- Decompiled C files in a `decomps/` directory
- `name_index.json` built from Il2CppDumper script.json
- Access to the GameAssembly.dll binary (for exports + strings)
- Old binary's `manual_names.json` (for code similarity matching)

### Technique 1: Name Index (already done by decompiler pipeline)
The name_index.json from Il2CppDumper provides 63K method names. This is the baseline.

### Technique 2: DLL Export Symbols

Read the PE export table — these are exact IL2CPP API function names.

```python
import pefile
pe = pefile.PE("GameAssembly.dll", fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT']])
for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
    if exp.name:
        va = pe.OPTIONAL_HEADER.ImageBase + exp.address
        # Add to manual_names if va is in decomps and not in name_index
```

### Technique 3: Thunk Resolution

A thunk is a function that just calls one other function. If the target is named, the thunk gets `thunk_<target_name>`.

```python
# For each unnamed decomp file < 500 bytes:
#   Find FUN_ calls in the body
#   If exactly 1 unique call target (excluding self) AND target is named:
#     Name this function "thunk_<target_name>"
```

Run multiple passes — each pass reveals new thunk targets for the next pass.

### Technique 4: Manual Runtime Function Identification

Read the top 20 most-referenced unnamed functions and identify them by code pattern:

| Pattern | IL2CPP Function |
|---------|----------------|
| LOCK/UNLOCK + bit manipulation on `*param_1` | `Il2CppCodeGenWriteBarrier` |
| Creates "IndexOutOfRangeException" | `il2cpp_codegen_raise_index_out_of_range_exception` |
| Reads class flags at `+0x132`, `+0x133` | `il2cpp_codegen_runtime_class_init` |
| `return *(param_1[0] + 0x12e)` | `il2cpp_class_get_rank` |
| Switch on `*(param + 10)` returning DATs | `il2cpp::vm::Class::FromIl2CppTypeEnum` |
| Card table bitmap with LOCK | `il2cpp::gc::GarbageCollector::SetWriteBarrier` |
| `_free_base()` call | `il2cpp_free` |
| `_malloc_base()` loop | `il2cpp_alloc` |
| Calls `_CxxThrowException` | `il2cpp_codegen_raise_exception_native` |

Scan the decomps to count FUN_ references, sort by frequency, read and identify the top 20-50.

### Technique 5: Code Similarity Matching (old → new binary)

If a previous binary's manual_names.json exists (from old analysis), transfer names by matching normalized function bodies.

```python
def normalize(content):
    """Strip addresses to create structural fingerprint"""
    body = content[content.find('{'):]  # body only
    body = re.sub(r'FUN_[0-9a-fA-F]+', 'FUN_X', body)
    body = re.sub(r'DAT_[0-9a-fA-F]+', 'DAT_X', body)
    body = re.sub(r'LAB_[0-9a-fA-F]+', 'LAB_X', body)
    body = re.sub(r'0x[0-9a-fA-F]{6,}', '0xADDR', body)
    return re.sub(r'\s+', ' ', body).strip()

# For each old manual name:
#   Fingerprint the old decomp
#   Search new decomps (similar size) for matching fingerprint
#   Transfer the name
```

This works because IL2CPP runtime functions have identical code across builds (same compiler, same source). Typically matches 150-200 functions.

### Technique 6: Additional Thunk Passes

After techniques 4-5 add more named functions, run thunk resolution again. Each pass catches thunks whose targets were just named.

### Technique 7: Ghidra Function ID Names

Ghidra's analysis already ran Function ID matching. Extract names from the decomp files themselves — if Ghidra named a function, it appears in the function signature line (not starting with `FUN_`).

```python
# For each unnamed decomp:
#   Read first code line (function signature)
#   Extract function name from signature
#   If it's NOT "FUN_xxx" and NOT a type keyword → Ghidra named it
```

Common finds: `operator_new`, `Baselib_*`, `CoTaskMemAlloc`, CRT functions like `common_flush_all`, `write_string`, math functions.

### Technique 8: String-Referenced Functions

Read DAT_ addresses from decomps, look them up in the .rdata section of the binary. If a short function references a readable string, name it `str_<string_content>`.

```python
# For each unnamed decomp < 1000 bytes:
#   Find DAT_xxx references
#   Check if address is in .rdata section
#   Try to read as UTF-8 string
#   If readable string found → name as str_<content>
```

### Technique 9: Auto-Describe Remaining Functions

For every remaining unnamed function, generate a descriptive label based on code patterns:

```python
def classify(addr, content):
    # Priority order:
    if is_constant_return(content):  return f"return_constant_{value}"
    if is_field_getter(content):     return f"field_getter_{offset}"
    if is_deref(content):            return "deref_param1"
    if is_noop(content):             return "noop_or_stub"
    if has_single_named_call(content): return f"calls_{target_name}"
    if has_lock_unlock(content):     return "interlocked_op"
    if calls_exception(content):     return f"throws_{exception_func}"
    if is_array_math(content):       return "array_element_access"
    # Fallback: describe by signature
    return f"{size}_{return_type}_{param_count}arg"
```

Categories generated:
- `return_constant_N` — returns a fixed value
- `field_getter_0xNN` — reads a field at known offset
- `calls_<named_func>` — wrapper around a known function
- `throws_<exception>` — exception throwing helper
- `interlocked_op` — atomic/LOCK operation
- `noop_or_stub` — empty or trivial function
- `small/medium/large_<type>_Narg` — size + signature based fallback

## Final Resolution Pass

After all techniques, run the resolver to apply all names to all decomp files:

```python
# Load name_index + manual_names
# For each decomp file:
#   Replace all FUN_xxx with resolved_name (NO /*FUN_xxx*/ comment!)
#   Rename file from FUN_xxx.c to ClassName$$Method.c
# Output to decomps_resolved/
```

**CRITICAL: Do NOT use the format `Name/*FUN_xxx*/(args)`.** The `/**/` comment between the function name and `(` breaks GitNexus's C call parser, causing ~80% of CALLS edges to be missing from the knowledge graph. Use plain `Name(args)` instead.

**Also sanitize dots:** Replace `.` with `_` in resolved names. Namespace dots (e.g., `DG.Tweening.Core`) create invalid C identifiers that GitNexus fails to parse, causing ~3,700 missing Function nodes.

## Stub Enrichment (after resolution)

~2,200 IL2CPP methods are compiler-inlined. Their decomp files are tiny stubs (< 200 bytes) because the real logic was expanded at call sites. After resolution, scan all resolved decomps to find callers of each stub and append context comments:

```c
// Original stub:
void ItemData$$GetHorseMaxWeightAdd(longlong param_1) {
    if (*(int *)(param_1 + 0x18) != 0) return;
    return;
}
// ========================================================
// COMPILER INLINED — stub entry point only (2 callers found)
// The real logic is expanded at call sites listed below.
// ========================================================
//
// INLINED AT: GameController$$CountHeroData.c:1641
//       fVar25 = (float)ItemData$$GetHorseMaxWeightAdd(*(longlong *)(param_2 + 0x208),0);
```

This makes stub files useful — you see where the real code lives without searching manually.

## Verification

```python
# Sample 2000 files, count remaining bare FUN_ references
# Target: 0 remaining (100% resolved)
import re, random
sample = random.sample(files, 2000)
for f in sample:
    total += len(re.findall(r'\bFUN_[0-9a-fA-F]+', content))
    resolved += len(re.findall(r'/\*FUN_[0-9a-fA-F]+\*/', content))
print(f"{resolved/total*100:.2f}% resolved")
```

**Do NOT proceed to indexing until verification shows 100.00%.**

## Build the Knowledge Graph (GitNexus Index)

Only after 100% coverage is confirmed:

```bash
cd <decomps_resolved_dir>
git init
git config core.longpaths true
git add -A
git commit -m "Resolved decomps from GameAssembly.dll — 100% coverage"
gitnexus analyze
```

GitNexus takes ~15 minutes for 55K files. Produces a LadybugDB knowledge graph.

### Sanity Check After Indexing

Query the graph to verify edge/node counts:

```bash
node <lbug-query>/scripts/query.cjs "<decomps_resolved>/.gitnexus/lbug" \
  "MATCH (f:Function) RETURN count(f) as nodes"
node <lbug-query>/scripts/query.cjs "<decomps_resolved>/.gitnexus/lbug" \
  "MATCH ()-[r:CodeRelation {type: 'CALLS'}]->() RETURN count(r) as edges"
```

**Expected ranges for ~55K decomp files:**
- Function nodes: **~55K** (should be close to file count — if much lower, check for parse failures from dots in names or invalid C syntax)
- CALLS edges: **~150K-250K** (roughly 3-5 calls per function on average)

**Alert thresholds:**
- Nodes < 90% of file count → name sanitization issue (dots, special chars in identifiers)
- Edges < 100K → call detection broken (likely `/*comments*/` between function name and `(`, or other non-standard C syntax)
- Edges < 50K → severely broken, do NOT use the graph for call tracing

If edges are low, check a sample function: compare the `ClassName$$Method(` references in its decomp text vs the CALLS edges in the graph. If the text has calls that the graph doesn't, the resolution format is breaking the parser.

### Known Limitation: IL2CPP Compiler Inlining

~3,500 IL2CPP methods are aggressively inlined by the compiler. Their decomps are tiny stubs (< 200 bytes) because the real logic was expanded at call sites. This is normal — not a Ghidra bug.

When a method's decomp looks trivially simple but you expect real logic:
1. The compiler inlined it — the real code is in the **callers**
2. Search for the method name in other decomps to find where the logic actually lives
3. The stub at the method's own address is just a leftover non-inlined entry point

## Output Summary

| Output | Location | Size |
|--------|----------|------|
| Resolved decomps | `game_b_decomps_new/decomps_resolved/` | 55K files, 100% named |
| Manual names | `game_b_decomps_new/manual_names.json` | ~14K entries |
| GitNexus DB | `decomps_resolved/.gitnexus/lbug/` | ~656 MB |
