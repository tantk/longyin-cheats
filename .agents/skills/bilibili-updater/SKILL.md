---
name: bilibili-updater
description: Update the Bilibili video description with the latest Baidu Wangpan download link for the cheat table. Use this skill whenever the user says "update bilibili", "bilibili description", "B站", "update video description", "bilibili link", or wants to update the cheat table download link on their Bilibili video.
---

# Bilibili Video Description Updater

Updates the Bilibili (B站) video description with the latest Baidu Wangpan share link and retrieval code from `tools/baidu/shares.json`.

## Files

- **Baidu share registry**: `tools/baidu/shares.json` — read the latest entry for URL + 提取码
- **Video info**: `tools/bilibili/video_info.txt` — stores video URL and metadata

## Prerequisites

- User must be logged into Bilibili (bilibili.com) in Chrome
- Latest Baidu share link must exist in `tools/baidu/shares.json`
- Codex-in-chrome browser automation tools available

## Workflow

### Step 1: Generate description from template

1. Read `tools/baidu/shares.json` — get latest entry (URL + 提取码)
2. Read `tools/bilibili/description_template.txt`
3. Replace `{{BAIDU_SHARE_SECTION}}` with:
   ```
   通过网盘分享的文件：[filename]
   链接: [url] 提取码: [code]
   ```
4. Save generated text to `tools/bilibili/current_description.txt`

Python snippet:
```python
import json
with open('tools/bilibili/description_template.txt', 'r', encoding='utf-8') as f:
    template = f.read()
with open('tools/baidu/shares.json', 'r', encoding='utf-8') as f:
    latest = json.load(f)['uploads'][0]
baidu = '通过网盘分享的文件：' + latest['filename'] + '\n链接: ' + latest['url'] + ' 提取码: ' + latest['retrieval_code']
desc = template.replace('{{BAIDU_SHARE_SECTION}}', baidu).rstrip()
with open('tools/bilibili/current_description.txt', 'w', encoding='utf-8') as f:
    f.write(desc)
```

### Step 2: Navigate to Bilibili video edit page

1. Navigate to: `https://member.bilibili.com/platform/upload/video/frame?type=edit&bvid=BV1yeXTBoEMG`
2. If redirected to login (passport.bilibili.com), ask user to log in and retry
3. Wait for 创作中心 (Creator Center) edit page to load

### Step 3: Replace the entire description

The description is in a **contenteditable div** (not a textarea). Use JavaScript:

```javascript
const el = document.querySelectorAll('[contenteditable]')[0];
el.innerText = newDesc;  // the full generated description string
el.dispatchEvent(new Event('input', { bubbles: true }));
```

Pass the description as a JSON-encoded string to preserve newlines and quotes safely.

### Step 4: Submit

1. Click **立即投稿** (Submit) button
2. Page redirects to video management dashboard (upload-manager/article)
3. Video status shows 审核中 (Under review) — this is normal after edits

### Step 5: Report to user

```
Updated Bilibili video description
Video: BV1yeXTBoEMG
New Baidu link: [url]
提取码: [code]
Status: 审核中 (under review)
```

## Notes

- Bilibili interface is in Chinese
- The first time this workflow runs, the user will teach the exact click sequence. Update this skill with the learned steps afterward.
- Always include 提取码 in the description — Chinese users need it to access Baidu downloads
- The video info file is gitignored (contains personal video URLs)
