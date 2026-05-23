---
name: baidu-uploader
description: Upload cheat table files to Baidu Wangpan (百度网盘) and save the sharing link with retrieval code. Use this skill whenever the user says "upload to baidu", "baidu wangpan", "百度网盘", "share on baidu", "baidu link", "upload to cloud", "chinese cloud share", or wants to distribute the CT file via Baidu for Chinese users.
---

# Baidu Wangpan Uploader

Uploads the latest cheat table to Baidu Wangpan (百度网盘) via browser automation, creates a sharing link with retrieval code (提取码), and saves the result to a JSON registry for easy retrieval.

## Files

- **CT file**: `patches/LongYinLiZhiZhuan.CT`
- **Share registry**: `tools/baidu/shares.json`

## Prerequisites

- User must be logged into Baidu Wangpan in Chrome (pan.baidu.com)
- Codex-in-chrome browser automation tools available
- Note: Web session expires after 1-2 days. Desktop app session lasts longer but can't be automated via browser tools.

## Share Registry Format

The registry at `tools/baidu/shares.json` maps each upload by filename and version:

```json
{
  "uploads": [
    {
      "filename": "LongYinLiZhiZhuan.CT",
      "version": "v6",
      "game_version": "1.0.0f8",
      "url": "https://pan.baidu.com/s/xxxxx",
      "retrieval_code": "ab12",
      "upload_date": "2026-03-29",
      "size_bytes": 120947,
      "description": "v6 (1.0.0f8) item adder GUI, fog removal, equipment gen"
    }
  ]
}
```

## Workflow

### Step 1: Prepare metadata

Generate version info from git and the CT file:
```bash
git log --oneline -5 --no-merges
stat patches/LongYinLiZhiZhuan.CT
```

### Step 2: Navigate to Baidu Wangpan

1. Create a new tab or find existing pan.baidu.com tab
2. Navigate to `https://pan.baidu.com/disk/main`
3. Verify logged in (should see file list with 全部文件)

### Step 3: Upload the CT file via localhost + file input

Same pattern as fearless-updater:

1. **Start local HTTP server** on port 18999:
   ```python
   python -c "
   import http.server, os
   class Handler(http.server.SimpleHTTPRequestHandler):
       def do_GET(self):
           if self.path == '/ct':
               with open(r'C:\dev\longyin-cheats\patches\LongYinLiZhiZhuan.CT', 'rb') as f:
                   data = f.read()
               self.send_response(200)
               self.send_header('Content-Type', 'application/octet-stream')
               self.send_header('Content-Length', len(data))
               self.send_header('Access-Control-Allow-Origin', '*')
               self.end_headers()
               self.wfile.write(data)
           else:
               self.send_response(404); self.end_headers()
       def log_message(self, format, *args): pass
   http.server.HTTPServer(('127.0.0.1', 18999), Handler).serve_forever()
   " &
   ```

2. **Inject file via JavaScript** — fetch from localhost and set on Baidu's file input:
   ```javascript
   (async () => {
     const resp = await fetch('http://127.0.0.1:18999/ct');
     const blob = await resp.blob();
     const file = new File([blob], 'LongYinLiZhiZhuan.CT', {type: 'application/octet-stream'});
     const inputs = document.querySelectorAll('input[type="file"]');
     const input = inputs[0];
     const dt = new DataTransfer();
     dt.items.add(file);
     input.files = dt.files;
     input.dispatchEvent(new Event('change', {bubbles: true}));
   })();
   ```
   **Note:** Chrome will show a "Private Network Access" prompt — user clicks Allow once.

3. **Wait for upload** — Baidu shows an upload panel on the right side with progress. Wait for "上传完成 (1/1)".

4. The uploaded file appears in the file list with a timestamp suffix, e.g. `LongYinLiZhiZhuan_20260329_021646.CT`

### Step 4: Create sharing link

1. **Click the uploaded file** in the file list to select it (it may already be selected)
2. **Click 分享** (Share) button — either the toolbar button at top or inline icon next to file
3. **Share dialog appears** with options:
   - 链接分享 (Link Share) tab — should be active by default
   - 有效期 (Expiry): defaults to 365天 — leave as-is or select 永久有效
   - 提取码 (Retrieval code): 随机生成 (Random) — leave as-is
4. **Click 复制链接** (Copy Link) — this creates the link and copies it to clipboard
5. **Read the share info** from the tooltip that appears. It shows:
   - 链接: `https://pan.baidu.com/s/xxxxx?pwd=xxxx`
   - 提取码: `xxxx`
6. **Extract URL and code** — zoom into the tooltip area (~460,440 to 650,590) to read the text, since clipboard.readText() triggers a permission dialog that freezes the page

**Important:** Do NOT use `navigator.clipboard.readText()` — it triggers a browser permission dialog that freezes the page. Instead, zoom into the share tooltip text to visually read the URL and retrieval code.

### Step 5: Save to registry

Read existing `tools/baidu/shares.json` (or create if doesn't exist), append the new entry:

```python
import json, os
registry_path = 'tools/baidu/shares.json'
if os.path.exists(registry_path):
    with open(registry_path) as f:
        data = json.load(f)
else:
    data = {"uploads": []}

data["uploads"].insert(0, {
    "filename": "LongYinLiZhiZhuan.CT",
    "version": "<version>",
    "game_version": "<game_version>",
    "url": "<baidu_share_url>",
    "retrieval_code": "<提取码>",
    "upload_date": "<YYYY-MM-DD>",
    "size_bytes": <file_size>,
    "description": "<brief description>"
})

with open(registry_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
```

### Step 6: Report to user

Show the user:
```
Uploaded: LongYinLiZhiZhuan.CT (v6)
Link: https://pan.baidu.com/s/xxxxx
提取码: ab12
Saved to: tools/baidu/shares.json
```

## Retrieving Previous Links

When the user asks for a previous Baidu link, read `tools/baidu/shares.json` and return the matching entry. Support lookup by version, game version, or just "latest".

## Notes

- The share registry is gitignored (contains public links but kept local for cleanliness)
- Always include game version in the description
- Baidu Wangpan interface is in Chinese — all button labels referenced in Chinese
- The first time this workflow runs, the user may need to teach the exact click sequence. Update this skill with the learned steps afterward (same approach used for fearless-updater).
