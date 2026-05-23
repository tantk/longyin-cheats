---
name: youtube-updater
description: Update the YouTube video description with the latest Baidu Wangpan download link for the cheat table. Use this skill whenever the user says "update youtube", "youtube description", "update YT", "youtube link", or wants to update the cheat table download link on their YouTube video.
---

# YouTube Video Description Updater

Updates the YouTube video description with the latest Baidu Wangpan share link and retrieval code, using the YouTube Data API v3 (no browser automation needed).

## Files

- **Baidu share registry**: `tools/baidu/shares.json` — read latest URL + 提取码
- **Video info**: `tools/youtube/video_info.txt` — stores video ID
- **Description template**: `tools/youtube/description_template.txt` — template with `{{BAIDU_SHARE_SECTION}}` placeholder
- **OAuth credentials**: `tools/youtube/client_secret.json` — Google OAuth2 credentials
- **Cached token**: `tools/youtube/token.json` — cached OAuth token (auto-generated after first auth)
- **Update script**: `tools/youtube/update_description.py` — Python script for API calls

## Prerequisites

- `google-api-python-client` and `google-auth-oauthlib` installed (already available)
- Google Cloud project with YouTube Data API v3 enabled
- OAuth2 credentials downloaded to `tools/youtube/client_secret.json`
- Latest Baidu share link in `tools/baidu/shares.json`

## First-Time Setup

If `tools/youtube/client_secret.json` doesn't exist:

1. Go to https://console.cloud.google.com/
2. Create a project (or select existing)
3. Enable "YouTube Data API v3"
4. Go to Credentials → Create Credentials → OAuth 2.0 Client ID
5. Application type: Desktop app
6. Download the JSON → save as `tools/youtube/client_secret.json`
7. Under OAuth consent screen, add the user's Google account as a test user

First run will open a browser for OAuth consent. After that, the token is cached.

## Workflow

### Step 1: Generate description from template

Same pattern as bilibili-updater:

```python
import json
with open('tools/youtube/description_template.txt', 'r', encoding='utf-8') as f:
    template = f.read()
with open('tools/baidu/shares.json', 'r', encoding='utf-8') as f:
    latest = json.load(f)['uploads'][0]
baidu = '百度网盘: ' + latest['url'] + '\n提取码: ' + latest['retrieval_code']
desc = template.replace('{{BAIDU_SHARE_SECTION}}', baidu).rstrip()
```

### Step 2: Update via YouTube API

Run the update script:
```bash
python tools/youtube/update_description.py --video-id VIDEO_ID --description "new description"
```

Or call the API directly:
```python
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
import json, os

SCOPES = ['https://www.googleapis.com/auth/youtube']
TOKEN_PATH = 'tools/youtube/token.json'
SECRET_PATH = 'tools/youtube/client_secret.json'

def get_youtube_service():
    creds = None
    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    if not creds or not creds.valid:
        flow = InstalledAppFlow.from_client_secrets_file(SECRET_PATH, SCOPES)
        creds = flow.run_local_server(port=0)
        with open(TOKEN_PATH, 'w') as f:
            f.write(creds.to_json())
    return build('youtube', 'v3', credentials=creds)

def update_description(video_id, new_description):
    yt = get_youtube_service()
    # Get current video details (need snippet for update)
    resp = yt.videos().list(part='snippet', id=video_id).execute()
    if not resp['items']:
        raise Exception(f'Video {video_id} not found')
    snippet = resp['items'][0]['snippet']
    snippet['description'] = new_description
    # categoryId is required for update
    yt.videos().update(
        part='snippet',
        body={'id': video_id, 'snippet': snippet}
    ).execute()
    return snippet['title']
```

### Step 3: Report to user

```
Updated YouTube video description
Video: [title]
Video ID: [id]
New Baidu link: [url]
提取码: [code]
```

## Notes

- OAuth token expires periodically — the script auto-refreshes it
- YouTube API has a daily quota (10,000 units). A video update costs 50 units — plenty of headroom
- The credentials files are gitignored (tools/ is already in .gitignore)
- Video descriptions on YouTube have a 5000 character limit
