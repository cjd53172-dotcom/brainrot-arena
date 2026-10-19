#!/usr/bin/env python3
"""One-time YouTube OAuth — prints a refresh token for Cursor Secrets.

Requires env:
  YOUTUBE_CLIENT_ID
  YOUTUBE_CLIENT_SECRET

Headless-friendly flow (works on Cloud Agents):
  1. Script prints an authorize URL
  2. Open it on YOUR computer, sign in as the YouTube channel owner
  3. Browser redirects to http://localhost:8090/?code=... (page may fail to load — that's OK)
  4. Copy the FULL address-bar URL and paste it back here
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from google_auth_oauthlib.flow import Flow

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube",
]
REDIRECT_URI = "http://localhost:8090/"

ROOT = Path(__file__).resolve().parent
TOKEN_PATH = ROOT / ".youtube_token.json"


def client_config() -> dict:
    client_id = os.environ.get("YOUTUBE_CLIENT_ID", "").strip()
    client_secret = os.environ.get("YOUTUBE_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        print(
            "Set YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET first.\n"
            "Google Cloud Console → APIs → enable YouTube Data API v3 →\n"
            "Credentials → Create OAuth client → Desktop app.",
            file=sys.stderr,
        )
        sys.exit(1)
    return {
        "installed": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [REDIRECT_URI],
        }
    }


def extract_code(pasted: str) -> str:
    pasted = pasted.strip().strip('"').strip("'")
    if pasted.startswith("http://") or pasted.startswith("https://"):
        qs = parse_qs(urlparse(pasted).query)
        if "error" in qs:
            raise SystemExit(f"OAuth error: {qs['error']}")
        if "code" not in qs:
            raise SystemExit("URL has no ?code= parameter. Paste the full redirect URL.")
        return qs["code"][0]
    return pasted  # raw authorization code


def main() -> None:
    flow = Flow.from_client_config(client_config(), scopes=SCOPES)
    flow.redirect_uri = REDIRECT_URI
    auth_url, _ = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
    )
    print("\n1) Open this URL in YOUR browser (channel owner Google account):\n")
    print(auth_url)
    print(
        "\n2) Approve access. When the browser lands on localhost and fails to load,\n"
        "   copy the FULL URL from the address bar and paste it below.\n"
    )
    pasted = input("Paste redirect URL (or raw code): ").strip()
    code = extract_code(pasted)
    flow.fetch_token(code=code)
    creds = flow.credentials
    if not creds.refresh_token:
        raise SystemExit(
            "No refresh_token returned. Revoke prior grants at "
            "https://myaccount.google.com/permissions then re-run with prompt=consent."
        )

    payload = {
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": list(creds.scopes or SCOPES),
    }
    TOKEN_PATH.write_text(json.dumps(payload, indent=2) + "\n")
    print("\n=== SUCCESS ===")
    print(f"Saved local token cache to {TOKEN_PATH} (gitignored).")
    print("\nAdd this as a Cursor Secret (Dashboard → Cloud Agents → Secrets):")
    print(f"  YOUTUBE_REFRESH_TOKEN={creds.refresh_token}")
    print("\nAlso keep these secrets set:")
    print("  YOUTUBE_CLIENT_ID")
    print("  YOUTUBE_CLIENT_SECRET")
    print("\nThen ask me to post the Shorts.")


if __name__ == "__main__":
    main()
