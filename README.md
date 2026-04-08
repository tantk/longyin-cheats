# LongYinLiZhiZhuan Cheat Table (龙胤立志传 修改器)

A form-based Cheat Engine table for **LongYinLiZhiZhuan** (龙胤立志传), a martial arts RPG built on Unity IL2CPP.

All cheats are accessed through a Multi-Tool form with 5 tabs. Bilingual UI (Chinese + English).

## Screenshots

### General Tab
Resources, stats, talents, skills, battle, exploration, reputation, and character creation cheats.

![General Tab](screenshot/general.png)

### Sect Tab
Sect-wide management: member limit, talent/skill slots, loyalty, resources, research, buildings, and hero generation.

![Sect Tab](screenshot/sect.png)

### Martial Arts Tab
Searchable database of 989 skills with sorting, filtering by category/rarity/sect, dynamic stat columns, and one-click book adding.

![Martial Arts Tab](screenshot/martialart.png)

### Items Tab
Add medicine, food, horses, materials, equipment (with sub-type selection), treasures, and max rarity.

![Items Tab](screenshot/items.png)

### Events Tab
Browse and spawn 106 game events with category filter, search, and difficulty control.

![Events Tab](screenshot/event.png)

## Features

### General
- Set Money, Sect Currency, Faction Contribution, Meteorite
- Stat Caps, Talent Slots, Talent Points
- Fame, NPC Favor, Faction Affinity
- Skill Limit, Combat EXP%, Living EXP%
- Restore HP, Clear Injuries
- Battle Speed, Enemy 1HP
- Horse Speed, Dungeon Reveal, Infinite Stamina
- Character Creation: Attribute/Fight/Living Points, Talent Points & Slots

### Sect Management
- Member Limit (bypass cap)
- Sect-wide: Talent Points, Talent Slots, Prodigy, Loyalty, Skill Slots
- Max Resources, No Cost, Instant Research, Instant Buildings
- Generate Hero (custom level, sex, age, loyalty, stats)

### Martial Arts
- 989 skills with full stat display
- Filter by category, rarity, sect
- Sort by any column including dynamic stat columns
- Add skill books by selection or ID

### Items
- Medicine, Food, Horse (from game database)
- Materials (type + level + rarity)
- Equipment (category + sub-type from game database + level + rarity)
- Treasures (type + level + rarity)
- Max Rarity (upgrade all items to highest quality)

### Events
- 106 events (random + festivals + tournaments)
- Filter by category, search by name
- Spawn Here (in current area) or Spawn Event (world events)
- Custom difficulty

## Requirements

- [Cheat Engine 7.6+](https://cheatengine.org)
- LongYinLiZhiZhuan (Steam)

## Usage

1. Open Cheat Engine, attach to `LongYinLiZhiZhuan.exe`
2. Load `LongYinLiZhiZhuan.CT`
3. Enable "Open Multi-Tool" in the address list
4. Click "Connect" in the Multi-Tool form
5. Use the tabs to access cheats

## Building from Source

The CT is built from modular Lua source files using [CE2FS](https://pypi.org/project/ce2fs/):

```bash
pip install ce2fs
python scripts/build.py
```

Output: `dist/LongYinLiZhiZhuan.CT`

### Project Structure

```
src/                 # 17 Lua source modules (4000 lines)
data/                # Embedded data files (skills, items, forces)
scripts/             # Build tools (build.py, lint, pre-commit)
CheatTable/          # CE2FS decomposed tree
tools/               # Runtime tools (crash recovery, analysis)
.claude/skills/      # Claude Code skills for development
.github/workflows/   # CI (build + release)
```

### Architecture

```
src/*.lua  --build-->  CheatTable/LuaScript.lua  --ce2fs-->  dist/*.CT
                       CheatTable/CheatEntries/**/*.cea  --+
                       data/*.dat  --pack-->  CheatTable/Files/
```

- **LuaScript** (`src/*.lua`): MT namespace with IL2CPP resolution, hooks, cheats, UI helpers
- **CheatEntries** (`.cea`): Form layout and UI wiring
- **Data files** (`.dat`): Game databases for dropdowns (skills, items, forces)

Method addresses are resolved at runtime via IL2CPP APIs where possible.

## License

This project is provided for educational and personal use. Use at your own risk.
