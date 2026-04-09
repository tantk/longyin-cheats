# LongYinLiZhiZhuan Cheat Table (龙胤立志传 修改器)

[中文说明见下方](#龙胤立志传-修改器)

A form-based Cheat Engine table for **LongYinLiZhiZhuan** (龙胤立志传), a martial arts RPG built on Unity IL2CPP. Bilingual UI (Chinese + English). Compatible with BepInEx and other IL2CPP mods.

## Screenshots

### Martial Arts — 989 skills browser
![Martial Arts](screenshot/martialart.png)

| General | Sect |
|---------|------|
| ![General](screenshot/general.png) | ![Sect](screenshot/sect.png) |

| Items | Events |
|-------|--------|
| ![Items](screenshot/items.png) | ![Events](screenshot/event.png) |

## Features

- **General**: Money, Sect Currency, Faction Contribution, Meteorite, Stat Caps, Talent Slots/Points, Fame, NPC Favor, Faction Affinity, Skill Limit, Combat/Living EXP%, Restore HP, Clear Injuries, Battle Speed, Enemy 1HP, Horse Speed, Dungeon Reveal, Infinite Stamina, Character Creation (Attribute/Fight/Living/Talent Points & Slots)
- **Sect**: Member Limit, Sect-wide Talents/Prodigy/Loyalty/Skill Slots, Max Resources, No Cost, Instant Research/Buildings, Generate Hero
- **Martial Arts**: 989 skills browser with sorting, filtering, dynamic stat columns, one-click book adding
- **Items**: Medicine, Food, Horse, Materials, Equipment (with sub-type), Treasures, Max Rarity
- **Events**: 106 events with category filter, search, difficulty control, Spawn Here / Spawn World Event

## Requirements

- [Cheat Engine 7.4+](https://cheatengine.org) (7.6+ recommended)
- LongYinLiZhiZhuan (Steam)

## Usage

1. Open Cheat Engine, attach to `LongYinLiZhiZhuan.exe`
2. Load `LongYinLiZhiZhuan.CT`
3. Enable "Open Multi-Tool" in the address list
4. **Load a save first** (title screen won't work), then click "Connect"
5. Use the tabs to access cheats

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "请先加载存档再连接" | Not in-game yet | Load a save first, then Connect |
| "请先用CE连接游戏" | CE not attached | File → Open Process → select game |
| "修改器加载出错" popup | Lua module failed | Close CE completely, reopen, load CT |
| "修改器加载失败" | Script not initialized | Close CE completely, reopen, load CT |
| "多功能工具创建失败" | Form error | Screenshot and report |
| 2/5 classes | Old version | Re-download latest release |

**Copy Diagnostics** for bug reports:
- **Address list**: enable "复制加载诊断 [Copy Load Diagnostics]" — works even if Multi-Tool fails
- **Multi-Tool form**: click "复制诊断 [Copy Diag]" button (top right)
- Paste into forum/chat (Ctrl+V) — fits Bilibili's 1000 char limit

## Building from Source

```bash
pip install ce2fs
python scripts/build.py        # build CT
python scripts/release.py      # bump version + tag + push (CI builds)
```

### Project Structure

```
src/                 # 17 Lua source modules (~4000 lines)
data/                # Embedded data files (skills, items, forces)
scripts/             # Build + release tools
CheatTable/          # CE2FS decomposed tree
tools/               # Runtime tools (crash recovery, analysis)
.claude/skills/      # Claude Code skills for development
.github/workflows/   # CI (build + release)
```

### Architecture

```
src/*.lua  --build-->  LuaScript.lua  --ce2fs-->  dist/*.CT
                       CheatEntries/**/*.cea  --+
                       data/*.dat  --pack-->  CheatTable/Files/
```

## License

This project is provided for educational and personal use. Use at your own risk.

---

# 龙胤立志传 修改器

基于 Cheat Engine 的表单式修改器。界面支持中英双语。兼容BepInEx及其他IL2CPP模组。

## 功能列表

- **通用**：银两、门派贡献、外门贡献、陨铁、属性上限、天赋槽/天赋点、声望、NPC好感、门派好感、武学上限、武学/生活经验倍率、恢复生命、清除伤势、战斗加速、敌人1血、坐骑加速、迷宫全开、无限耐力、角色创建（属性点/武学点/生活点/天赋点和天赋槽）
- **门派**：人数上限、全派天赋点/天赋槽/天才+博学/忠诚满/武学槽满、资源填满、无消耗、瞬间研究/建筑、生成角色
- **武学**：989种武学浏览器，支持排序、筛选、动态属性列、一键添加秘籍
- **物品**：药品、食物、坐骑、材料、装备（含子类型）、珍品、品质全满
- **事件**：106个事件，分类筛选、搜索、自定义难度、生成到此处/生成世界事件

## 使用要求

- [Cheat Engine 7.4+](https://cheatengine.org) (7.6+ recommended)
- 龙胤立志传（Steam版）

## 使用方法

1. 打开 Cheat Engine，连接 `LongYinLiZhiZhuan.exe` 进程
2. 加载 `LongYinLiZhiZhuan.CT` 文件
3. 在地址列表中启用"打开多功能工具"
4. **请先加载存档**（标题画面无法连接），然后点击"连接游戏"
5. 通过选项卡使用各项修改功能

## 故障排除

| 错误 | 原因 | 解决方法 |
|------|------|----------|
| "请先加载存档再连接" | 还在标题画面 | 先加载存档再点连接 |
| "请先用CE连接游戏" | CE未连接游戏 | 文件→打开进程→选择游戏 |
| "修改器加载出错" 弹窗 | Lua模块加载失败 | 完全关闭CE，重新打开，加载CT |
| "修改器加载失败" | 脚本未初始化 | 完全关闭CE，重新打开，加载CT |
| "多功能工具创建失败" | 窗口创建出错 | 截图错误信息并反馈 |
| 2/5 classes | 旧版本 | 重新下载最新版 |

**复制诊断信息**（用于反馈问题）：
- **地址列表中**：启用"复制加载诊断 [Copy Load Diagnostics]"— 即使多功能工具无法打开也能使用
- **多功能工具窗口中**：点击右上角"复制诊断 [Copy Diag]"按钮
- 粘贴到论坛/聊天（Ctrl+V）— 已压缩至B站1000字评论限制以内

## 从源码构建

```bash
pip install ce2fs
python scripts/build.py        # 构建CT
python scripts/release.py      # 发版（自动版本号+标签+推送，CI构建）
```
