---
name: fearless-updater
description: Update the FearlessRevolution forum post for the LongYinLiZhiZhuan cheat table. Use this skill whenever the user says "update forum", "update fearless", "upload CT", "update the post", "push to fearless", or wants to update the cheat table attachment or post content on FearlessRevolution. Also use when the user asks to release a new version of the cheat table.
---

# FearlessRevolution Forum Post Updater

Updates the cheat table post on FearlessRevolution forum (phpBB).
Can upload a new CT attachment and/or update the post content.

## Forum Post Info

- **Topic URL**: https://fearlessrevolution.com/viewtopic.php?f=4&t=38568
- **Post ID**: 446470 (first post)
- **Forum ID**: 4 (Tables)
- **Topic ID**: 38568
- **Author**: tantk

## Files

- **CT file**: `patches/LongYinLiZhiZhuan.CT`
- **Post template**: `tools/fearless/current_post.txt`
- **Post info**: `tools/fearless/post_info.txt`
- **Update script**: `tools/update_forum_post.py`

## How to Update

### Option 1: Browser Automation — Attachment Upload (most common)

When the user wants to upload a new CT file, use Codex-in-chrome browser automation:

**Prerequisites:** User must be logged into FearlessRevolution in Chrome.

**Steps:**

1. **Generate description** from recent git commits. Always include game version:
   ```
   v6 (1.0.0f8) item adder GUI, fog removal, equipment gen, battle speed
   ```

2. **Navigate** to topic: `https://fearlessrevolution.com/viewtopic.php?f=4&t=38568`

3. **Click Edit** on the first post (find the edit button for post by tantk)

4. **Click "Attachments" tab** at the bottom of the edit form (below Preview/Submit buttons)

5. **Start HTTPS local file server** (MUST be HTTPS — Edge blocks HTTP localhost from HTTPS pages):
   ```bash
   python tools/cors_server.py 18999 patches
   ```
   Run in background. Self-signed cert at `tools/certs/localhost.crt` + `localhost.key`.

   **First-time setup:** User must visit `https://localhost:18999` in Edge and click Advanced → Continue to trust the cert. This is a one-time step.

6. **Inject file via Plupload** (JavaScript in browser). This is the critical step — do NOT use DataTransfer on the file input directly (phpBB won't actually upload it). Must use phpBB's Plupload API:
   ```javascript
   (async () => {
     const resp = await fetch('https://localhost:18999/LongYinLiZhiZhuan.CT');
     const blob = await resp.blob();
     const file = new File([blob], 'LongYinLiZhiZhuan.CT', {type: 'application/octet-stream'});
     phpbb.plupload.uploader.addFile(file);
   })();
   ```

7. **Wait for upload** — wait ~5 seconds, then verify the new attachment row shows a green checkmark (not just a progress bar). If it shows "HTTP error", reload the edit page and retry step 6.

8. **Set file comment** — IMPORTANT: click the empty FILE COMMENT textbox for the new (top) attachment row and type the description. Format:
   ```
   v6 (1.0.0f8) Chinese GUI, Rare control for all items, hero gen
   ```
   Generate from recent git commits. This comment is visible to users downloading the attachment.

9. **Click Submit** to save the post

10. **Kill the local server** after submission

**Important:** Always use `phpbb.plupload.uploader.addFile()`, never just DataTransfer. The fetch MUST use `https://localhost` not `http://localhost`.

### Option 2: Full Post Update

When the user wants to change the post content too:

1. Read current template from `tools/fearless/current_post.txt`
2. Update the content with new features/changes
3. Generate BBCode format
4. Either:
   a. Run the automated script: `python tools/update_forum_post.py --user X --password Y`
   b. Or provide the BBCode for the user to paste manually

### Option 3: Automated Update (if credentials available)

The script at `tools/update_forum_post.py` can automate the text update:

```bash
# Dry run (preview BBCode)
python tools/update_forum_post.py --user USERNAME --password PASSWORD --dry-run

# Actually update
python tools/update_forum_post.py --user USERNAME --password PASSWORD --post-id 446470
```

Note: File attachment upload is now automated via browser automation (Option 1). The Python script only handles post text, not attachments.

## Generating Attachment Description

Use this format:
```
龙胤立志传 修改器 [version] ([game version]) - [brief summary in English]
```

Example:
```
龙胤立志传 修改器 v6 (1.0.0 f8) - fog removal, no resource cost, equipment generator, battle speed
```

Pull the summary from recent git commits:
```bash
git log --oneline -5 --no-merges
```

## Generating BBCode Post Content

Use BBCode formatting for FearlessRevolution (phpBB):
- `[b]bold[/b]` for bold
- `[list][*]item[/list]` for lists
- `[url=...]link[/url]` for links
- `[code]...[/code]` for code blocks
- `[size=150]...[/size]` for headers

Always include:
1. Game name + Steam link
2. CE version requirement (7.6+)
3. Full feature list
4. How to use instructions
5. Notes/caveats (horse speed saves with game, fog is per-dungeon, etc.)

## After Updating

1. Save the updated post content back to `tools/fearless/current_post.txt`
2. Update `tools/fearless/post_info.txt` with new download count or version info
3. These files are gitignored so they stay local
