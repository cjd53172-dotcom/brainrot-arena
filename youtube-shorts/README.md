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
