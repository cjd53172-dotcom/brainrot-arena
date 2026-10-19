# Brainrot Arena — YouTube Shorts pack

Ready-to-upload vertical Shorts promoting **Brainrot Arena** on Roblox.

## What’s included

| Short | File | Length | Hook |
|-------|------|--------|------|
| 01 | `videos/01-they-added-brainrot.mp4` | ~13s | “They added brainrot to Roblox” |
| 02 | `videos/02-which-brainrot-wins.mp4` | ~13s | Cappuccino Assassino vs Bombardiro |
| 03 | `videos/03-hatched-a-legendary.mp4` | ~13s | Legendary hatch flex |
| 04 | `videos/04-catch-them-all.mp4` | ~15s | Collection showcase |

- `frames/` — 9:16 stills used to build the videos  
- `scripts/captions.md` — titles, captions, hashtags  
- `build_shorts.sh` — rebuild MP4s from frames with ffmpeg  

## Specs

- 720×1280 (9:16)
- H.264 + AAC
- Soft placeholder tone bed (swap for a trending Shorts sound on upload)

## Rebuild

```bash
./youtube-shorts/build_shorts.sh
```

Requires `ffmpeg` and `python3`.

## Link YouTube + post

YouTube is not connected until you add OAuth secrets. One-time setup:

1. [Google Cloud Console](https://console.cloud.google.com/) → create/select a project  
2. Enable **YouTube Data API v3**  
3. Configure OAuth consent screen (External is fine for personal use)  
4. Credentials → **Create OAuth client ID** → Application type **Desktop app**  
5. Copy Client ID + Client Secret into Cursor Secrets:
   - `YOUTUBE_CLIENT_ID`
   - `YOUTUBE_CLIENT_SECRET`
6. Run auth (prints a URL — open it on your computer as the channel owner):

```bash
export YOUTUBE_CLIENT_ID=...
export YOUTUBE_CLIENT_SECRET=...
python3 youtube-shorts/auth_youtube.py
```

7. Add the printed `YOUTUBE_REFRESH_TOKEN` as a Cursor Secret  
8. Tell the agent to post (or run):

```bash
# defaults to unlisted so you can review first
python3 youtube-shorts/upload_shorts.py
PRIVACY=public python3 youtube-shorts/upload_shorts.py   # go live
```

Titles/descriptions include `#Shorts` so YouTube shelves them as Shorts.
