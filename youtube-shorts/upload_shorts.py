#!/usr/bin/env python3
"""Upload Brainrot Arena Shorts to YouTube via the Data API v3.

Auth (any of):
  - Env secrets: YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN
  - Or local cache from auth_youtube.py: youtube-shorts/.youtube_token.json

Usage:
  python3 youtube-shorts/upload_shorts.py              # upload all four
  python3 youtube-shorts/upload_shorts.py --dry-run    # print payload only
  python3 youtube-shorts/upload_shorts.py 01 03        # upload selected
  PRIVACY=unlisted python3 youtube-shorts/upload_shorts.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube",
]

ROOT = Path(__file__).resolve().parent
VIDEOS = ROOT / "videos"
TOKEN_PATH = ROOT / ".youtube_token.json"

# Default privacy: unlisted until you confirm they look right, then we can set public.
DEFAULT_PRIVACY = os.environ.get("PRIVACY", "unlisted")

SHORTS = {
    "01": {
        "file": "01-they-added-brainrot.mp4",
        "title": "They put brainrot on Roblox 💀 #Shorts",
        "description": (
            "They added brainrot to Roblox and I’m not okay 😭\n\n"
            "▶ Play free: https://www.roblox.com/games/92909397469421\n"
            "Search Brainrot Arena on Roblox.\n\n"
            "Catch pets. Battle. Flex your showcase.\n\n"
            "#BrainrotArena #Roblox #ItalianBrainrot #RobloxShorts #Brainrot #Shorts"
        ),
        "tags": [
            "Brainrot Arena",
            "Roblox",
            "Italian Brainrot",
            "Shorts",
            "Roblox Shorts",
        ],
    },
    "02": {
        "file": "02-which-brainrot-wins.mp4",
        "title": "Cappuccino Assassino vs Bombardiro Crocodilo #Shorts",
        "description": (
            "Cappuccino Assassino vs Bombardiro Crocodilo — who takes it?\n\n"
            "Drop your pick in the comments then battle it in Brainrot Arena on Roblox.\n\n"
            "#BrainrotArena #BombardiroCrocodilo #CappuccinoAssassino #Roblox #VS #Shorts"
        ),
        "tags": [
            "Brainrot Arena",
            "Bombardiro Crocodilo",
            "Cappuccino Assassino",
            "Roblox",
            "Shorts",
        ],
    },
    "03": {
        "file": "03-hatched-a-legendary.mp4",
        "title": "POV: you hatch a Legendary 🐐🪐 #Shorts",
        "description": (
            "POV: the egg pops and it’s a Legendary 🐐🪐\n\n"
            "Eggs. Battles. Brainrot gods.\n"
            "Play Brainrot Arena on Roblox.\n\n"
            "#BrainrotArena #Roblox #LegendaryPull #ItalianBrainrot #Shorts"
        ),
        "tags": [
            "Brainrot Arena",
            "Roblox",
            "Legendary",
            "Italian Brainrot",
            "Shorts",
        ],
    },
    "04": {
        "file": "04-catch-them-all.mp4",
        "title": "Rate this brainrot collection 💼 #Shorts",
        "description": (
            "Collecting brainrots like it’s a full-time job 💼🍌🍉\n\n"
            "Common → Rare → Epic → chaos.\n"
            "Brainrot Arena on Roblox. Search it.\n\n"
            "#BrainrotArena #Roblox #Collection #ItalianBrainrot #Shorts"
        ),
        "tags": [
            "Brainrot Arena",
            "Roblox",
            "Collection",
            "Italian Brainrot",
            "Shorts",
        ],
    },
}


def load_credentials() -> Credentials:
    client_id = os.environ.get("YOUTUBE_CLIENT_ID", "").strip()
    client_secret = os.environ.get("YOUTUBE_CLIENT_SECRET", "").strip()
    refresh = os.environ.get("YOUTUBE_REFRESH_TOKEN", "").strip()

    if client_id and client_secret and refresh:
        creds = Credentials(
            token=None,
            refresh_token=refresh,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=client_id,
            client_secret=client_secret,
            scopes=SCOPES,
        )
        creds.refresh(Request())
        return creds

    if TOKEN_PATH.exists():
        data = json.loads(TOKEN_PATH.read_text())
        creds = Credentials.from_authorized_user_info(data, SCOPES)
        if not creds.valid:
            if creds.refresh_token:
                creds.refresh(Request())
            else:
                raise SystemExit("Local token expired. Re-run auth_youtube.py")
        return creds

    raise SystemExit(
        "YouTube not linked.\n"
        "Add Cursor Secrets YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, "
        "YOUTUBE_REFRESH_TOKEN — or run: python3 youtube-shorts/auth_youtube.py"
    )


def upload_one(youtube, key: str, privacy: str, dry_run: bool) -> str | None:
    meta = SHORTS[key]
    path = VIDEOS / meta["file"]
    if not path.exists():
        raise SystemExit(f"Missing video: {path}")

    body = {
        "snippet": {
            "title": meta["title"][:100],
            "description": meta["description"],
            "tags": meta["tags"],
            "categoryId": "20",  # Gaming
        },
        "status": {
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": False,
        },
    }

    print(f"\n→ {key} {path.name}")
    print(f"  title: {body['snippet']['title']}")
    print(f"  privacy: {privacy}")

    if dry_run:
        print("  (dry-run, skipped)")
        return None

    media = MediaFileUpload(str(path), mimetype="video/mp4", resumable=True, chunksize=1024 * 1024)
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)

    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"  upload {int(status.progress() * 100)}%")

    video_id = response["id"]
    url = f"https://youtu.be/{video_id}"
    print(f"  live: {url}")
    return url


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload Brainrot Arena YouTube Shorts")
    parser.add_argument("keys", nargs="*", help="Short ids like 01 02 (default: all)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--privacy",
        choices=("private", "unlisted", "public"),
        default=DEFAULT_PRIVACY,
    )
    args = parser.parse_args()

    keys = args.keys or list(SHORTS.keys())
    for k in keys:
        if k not in SHORTS:
            raise SystemExit(f"Unknown short id {k!r}. Choose from: {', '.join(SHORTS)}")

    if args.dry_run:
        youtube = None
    else:
        creds = load_credentials()
        youtube = build("youtube", "v3", credentials=creds)

    results = {}
    try:
        for key in keys:
            results[key] = upload_one(youtube, key, args.privacy, args.dry_run)
    except HttpError as err:
        print(f"YouTube API error: {err}", file=sys.stderr)
        sys.exit(1)

    out = ROOT / "upload_results.json"
    if not args.dry_run:
        out.write_text(json.dumps(results, indent=2) + "\n")
        print(f"\nWrote {out}")
    print("\nDone.")


if __name__ == "__main__":
    main()
