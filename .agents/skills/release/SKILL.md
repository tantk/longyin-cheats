---
name: release
description: Release the latest cheat table to all platforms — FearlessRevolution, Baidu Wangpan, Bilibili, and YouTube. Use this skill whenever the user says "release", "publish CT", "push to all platforms", "release new version", "distribute CT", "update all platforms", or wants to upload and update everywhere after finishing a cheat table update.
---

# Release Cheat Table to All Platforms

Orchestrates the full release pipeline after a cheat table update. Runs each platform updater in sequence, since Baidu must complete before Bilibili/YouTube (they need the share link).

## Pipeline Order

```
1. FearlessRevolution  (upload CT attachment)
2. Baidu Wangpan       (upload CT, get share link + 提取码)
3. Bilibili            (update description with new Baidu link)
4. YouTube             (update description with new Baidu link)
```

Steps 3 and 4 depend on step 2 (need the Baidu URL). Steps 3 and 4 are independent of each other. YouTube uses the API so it can run without browser.

## Workflow

### Before starting

Verify the CT file is ready:
```bash
git log --oneline -3 --no-merges
stat patches/LongYinLiZhiZhuan.CT
```

Confirm with the user: "Ready to release to all 4 platforms?"

### Step 1: FearlessRevolution

Invoke the `fearless-updater` skill workflow:
- Start HTTPS localhost server (port 18999) — `python tools/cors_server.py 18999 patches`
- Navigate to topic, click Edit
- Click Attachments tab
- Inject CT via Plupload (`fetch('https://localhost:18999/LongYinLiZhiZhuan.CT')` → `phpbb.plupload.uploader.addFile()`)
- **Set file comment** on the new attachment — this is visible to download users, e.g. `v6 (1.0.0f8) Chinese GUI, Rare control for all items`
- Submit

### Step 2: Baidu Wangpan

Invoke the `baidu-uploader` skill workflow:
- Navigate to pan.baidu.com (reuse localhost server if still running)
- Inject CT via file input
- Wait for upload
- Click file → 分享 → 复制链接
- Read URL + 提取码 from tooltip
- Save to `tools/baidu/shares.json`

**Kill localhost server after this step.**

### Step 3: Bilibili

Invoke the `bilibili-updater` skill workflow:
- Generate description from template + latest Baidu link from shares.json
- Navigate to Bilibili edit page
- Replace contenteditable div with new description
- Click 立即投稿

### Step 4: YouTube

Invoke the `youtube-updater` skill workflow (API, no browser):
```bash
python -c "
import json
with open('tools/youtube/description_template.txt', 'r', encoding='utf-8') as f:
    template = f.read()
with open('tools/baidu/shares.json', 'r', encoding='utf-8') as f:
    latest = json.load(f)['uploads'][0]
baidu = '通过网盘分享的文件：' + latest['filename'] + chr(10) + '链接: ' + latest['url'] + ' 提取码: ' + latest['retrieval_code']
desc = template.replace('{{BAIDU_SHARE_SECTION}}', baidu).rstrip()
with open('tools/youtube/current_description.txt', 'w', encoding='utf-8') as f:
    f.write(desc)
"
python tools/youtube/update_description.py --video-id zAO95tQms00 --description-file tools/youtube/current_description.txt
```

### Step 5: Report

Show a summary table:

```
Release complete!

| Platform          | Status | Link                          |
|-------------------|--------|-------------------------------|
| FearlessRevolution| ✓      | viewtopic.php?f=4&t=38568     |
| Baidu Wangpan     | ✓      | [url] 提取码: [code]           |
| Bilibili          | ✓      | BV1yeXTBoEMG (审核中)          |
| YouTube           | ✓      | zAO95tQms00                    |
```

## Error Handling

If any step fails:
- Report which step failed and why
- Ask the user if they want to continue with remaining steps or fix and retry
- Steps 3+4 can be retried independently since they just read from shares.json

## Notes

- The whole pipeline takes ~2-3 minutes
- FearlessRevolution and Baidu require being logged in via Chrome
- Bilibili requires being logged in via Chrome
- YouTube uses cached OAuth token (no browser needed after first auth)
- If the localhost "Private Network Access" prompt appears (Baidu step), user clicks Allow once
- Always confirm with user before starting — this publishes to 4 platforms
