#!/usr/bin/env bash
# Build Brainrot Arena YouTube Shorts (9:16, ~15s each) from still frames.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
FRAMES="$ROOT/frames"
OUT="$ROOT/videos"
TMP="$ROOT/.tmp"
mkdir -p "$OUT" "$TMP"

W=720
H=1280
FPS=30

# Ken Burns zoom-in clip from a still image.
# Usage: make_clip <input.jpg> <duration_sec> <output.mp4> [zoom_end]
make_clip() {
  local src="$1" dur="$2" dest="$3" zend="${4:-1.18}"
  local frames=$((dur * FPS))
  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -i "$src" \
    -vf "scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},zoompan=z='min(zoom+0.0015,${zend})':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${frames}:s=${W}x${H}:fps=${FPS},format=yuv420p" \
    -t "$dur" -r "$FPS" -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
    "$dest"
}

# Soft whoosh-ish bed (silent-friendly; replace with trending audio on upload).
make_bed() {
  local dest="$1" dur="$2"
  local fade_out_start
  fade_out_start=$(python3 -c "print(max(0, float('${dur}') - 0.6))")
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=110:duration=${dur}" \
    -f lavfi -i "sine=frequency=165:duration=${dur}" \
    -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest,volume=0.08,afade=t=in:st=0:d=0.4,afade=t=out:st=${fade_out_start}:d=0.6" \
    -c:a aac -b:a 128k "$dest"
}

mux() {
  local video="$1" audio="$2" dest="$3"
  ffmpeg -y -hide_banner -loglevel error \
    -i "$video" -i "$audio" -c:v copy -c:a aac -shortest -movflags +faststart \
    "$dest"
}

echo "== Short 1: Hook reveal =="
make_clip "$FRAMES/short1-hook.jpg" 3 "$TMP/s1a.mp4" 1.12
make_clip "$FRAMES/short1-hero-roster.jpg" 7 "$TMP/s1b.mp4" 1.22
make_clip "$FRAMES/short-end-cta.jpg" 4 "$TMP/s1c.mp4" 1.10
ffmpeg -y -hide_banner -loglevel error \
  -i "$TMP/s1a.mp4" -i "$TMP/s1b.mp4" -i "$TMP/s1c.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=2.65[v01];[v01][2:v]xfade=transition=fade:duration=0.35:offset=9.3[v]" \
  -map "[v]" -r "$FPS" -c:v libx264 -pix_fmt yuv420p "$TMP/s1_video.mp4"
make_bed "$TMP/s1_audio.m4a" 14
mux "$TMP/s1_video.mp4" "$TMP/s1_audio.m4a" "$OUT/01-they-added-brainrot.mp4"

echo "== Short 2: VS battle =="
make_clip "$FRAMES/short2-vs-battle.jpg" 8 "$TMP/s2a.mp4" 1.20
make_clip "$FRAMES/short-end-cta.jpg" 5 "$TMP/s2b.mp4" 1.10
ffmpeg -y -hide_banner -loglevel error \
  -i "$TMP/s2a.mp4" -i "$TMP/s2b.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=7.65[v]" \
  -map "[v]" -r "$FPS" -c:v libx264 -pix_fmt yuv420p "$TMP/s2_video.mp4"
make_bed "$TMP/s2_audio.m4a" 13
mux "$TMP/s2_video.mp4" "$TMP/s2_audio.m4a" "$OUT/02-which-brainrot-wins.mp4"

echo "== Short 3: Legendary hatch =="
make_clip "$FRAMES/short3-legendary-hatch.jpg" 8 "$TMP/s3a.mp4" 1.25
make_clip "$FRAMES/short-end-cta.jpg" 5 "$TMP/s3b.mp4" 1.10
ffmpeg -y -hide_banner -loglevel error \
  -i "$TMP/s3a.mp4" -i "$TMP/s3b.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=7.65[v]" \
  -map "[v]" -r "$FPS" -c:v libx264 -pix_fmt yuv420p "$TMP/s3_video.mp4"
make_bed "$TMP/s3_audio.m4a" 13
mux "$TMP/s3_video.mp4" "$TMP/s3_audio.m4a" "$OUT/03-hatched-a-legendary.mp4"

echo "== Short 4: Collection flex =="
make_clip "$FRAMES/short4-collection.jpg" 8 "$TMP/s4a.mp4" 1.18
make_clip "$FRAMES/short1-hero-roster.jpg" 4 "$TMP/s4b.mp4" 1.15
make_clip "$FRAMES/short-end-cta.jpg" 4 "$TMP/s4c.mp4" 1.10
ffmpeg -y -hide_banner -loglevel error \
  -i "$TMP/s4a.mp4" -i "$TMP/s4b.mp4" -i "$TMP/s4c.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.3:offset=7.7[v01];[v01][2:v]xfade=transition=fade:duration=0.3:offset=11.4[v]" \
  -map "[v]" -r "$FPS" -c:v libx264 -pix_fmt yuv420p "$TMP/s4_video.mp4"
make_bed "$TMP/s4_audio.m4a" 15
mux "$TMP/s4_video.mp4" "$TMP/s4_audio.m4a" "$OUT/04-catch-them-all.mp4"

rm -rf "$TMP"
echo "Done. Videos in $OUT"
ls -lh "$OUT"
