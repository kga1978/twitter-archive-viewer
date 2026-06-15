#!/usr/bin/env bash
# make_archive_viewer.sh — Build a Twitter/X archive viewer for any archive.
#
# Usage:
#   bash make_archive_viewer.sh <archive_dir> [options]
#
# Arguments:
#   <archive_dir>    Path to your Twitter/X archive root (the folder containing data/)
#
# Options:
#   --local          Local preview mode: use a symlink for tweets_media (default)
#   --online         Web deployment mode: copy all files (no symlinks)
#   --no-media       Skip tweets_media; images fall back to Twitter CDN URLs
#   --no-wallpaper      Hide the profile header/banner image
#   --logo <file>       Custom logo for the expanded sidebar (replaces @username text)
#   --logo-icon <file>  Custom logo for the collapsed sidebar (defaults to --logo if omitted)
#   --output <dir>      Output directory (default: <archive_dir>/viewer-output/)
#
# Examples:
#   bash make_archive_viewer.sh ~/Downloads/twitter_archive --local
#   bash make_archive_viewer.sh ~/Downloads/twitter_archive --online --output ~/Desktop/my_viewer
#   bash make_archive_viewer.sh ~/Downloads/twitter_archive --online --logo ~/logo_full.png --logo-icon ~/logo_icon.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_PY="$SCRIPT_DIR/process_tweets.py"
INDEX_HTML="$SCRIPT_DIR/viewer/index.html"

# ── Defaults ────────────────────────────────────────────────────────────────
ARCHIVE_DIR=""
MODE="local"
INCLUDE_MEDIA=true
INCLUDE_WALLPAPER=true
LOGO_FILE=""
LOGO_ICON_FILE=""
OUTPUT_DIR=""

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 1
}

# ── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -lt 1 || "$1" == --* ]]; then
  echo "Error: archive directory is required as the first argument." >&2
  echo "" >&2
  usage
fi
ARCHIVE_DIR="$(cd "$1" && pwd)"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)        MODE="local" ;;
    --online)       MODE="online" ;;
    --no-media)     INCLUDE_MEDIA=false ;;
    --no-wallpaper) INCLUDE_WALLPAPER=false ;;
    --logo)
      shift
      [[ $# -gt 0 ]] || { echo "Error: --logo requires a file path." >&2; exit 1; }
      [[ -f "$1" ]] || { echo "Error: logo file not found: $1" >&2; exit 1; }
      LOGO_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
      ;;
    --logo-icon)
      shift
      [[ $# -gt 0 ]] || { echo "Error: --logo-icon requires a file path." >&2; exit 1; }
      [[ -f "$1" ]] || { echo "Error: logo-icon file not found: $1" >&2; exit 1; }
      LOGO_ICON_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
      ;;
    --output)
      shift
      [[ $# -gt 0 ]] || { echo "Error: --output requires a directory argument." >&2; exit 1; }
      mkdir -p "$1"
      OUTPUT_DIR="$(cd "$1" && pwd)"
      ;;
    -h|--help)  usage ;;
    *) echo "Error: unknown argument: $1" >&2; echo "" >&2; usage ;;
  esac
  shift
done

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$ARCHIVE_DIR/viewer-output"
fi

# ── Safety check ─────────────────────────────────────────────────────────────
if [[ "$OUTPUT_DIR" == "$ARCHIVE_DIR" ]]; then
  echo "Error: output directory cannot be the same as the archive directory." >&2
  exit 1
fi

# ── Validate tools ───────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "Error: python3 not found. Please install Python 3 and try again." >&2
  exit 1
fi

# ── Validate toolchain files ─────────────────────────────────────────────────
if [[ ! -f "$PROCESS_PY" ]]; then
  echo "Error: process_tweets.py not found at $PROCESS_PY" >&2
  exit 1
fi
if [[ ! -f "$INDEX_HTML" ]]; then
  echo "Error: viewer/index.html not found at $INDEX_HTML" >&2
  exit 1
fi

# ── Validate archive structure ────────────────────────────────────────────────
for required in data/tweets.js data/account.js data/profile.js; do
  if [[ ! -f "$ARCHIVE_DIR/$required" ]]; then
    echo "Error: $required not found in archive. Is $ARCHIVE_DIR a valid Twitter archive?" >&2
    exit 1
  fi
done

DATA_DIR="$ARCHIVE_DIR/data"
TWEETS_MEDIA="$DATA_DIR/tweets_media"
PROFILE_MEDIA="$DATA_DIR/profile_media"

# Warn (not error) if optional media directories are missing
if [[ ! -d "$PROFILE_MEDIA" ]]; then
  echo "Warning: data/profile_media/ not found — avatar will fall back to Twitter CDN." >&2
fi
if $INCLUDE_MEDIA && [[ ! -d "$TWEETS_MEDIA" ]]; then
  echo "Warning: data/tweets_media/ not found — switching to --no-media mode." >&2
  INCLUDE_MEDIA=false
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "=== Twitter Archive Viewer Builder ==="
echo "Archive: $ARCHIVE_DIR"
echo "Output:  $OUTPUT_DIR"
echo "Mode:    $MODE$(if ! $INCLUDE_MEDIA; then echo " (no media)"; fi)$(if ! $INCLUDE_WALLPAPER; then echo " (no wallpaper)"; fi)$(if [[ -n "$LOGO_FILE" ]]; then echo " (custom logo)"; fi)"
echo ""

echo "Creating output directory..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Processing tweets..."
python3 "$PROCESS_PY" --archive "$ARCHIVE_DIR" --output "$OUTPUT_DIR"

echo ""
echo "Copying viewer..."
cp "$INDEX_HTML" "$OUTPUT_DIR/index.html"

if [[ -d "$PROFILE_MEDIA" ]]; then
  echo "Copying profile media..."
  cp -r "$PROFILE_MEDIA" "$OUTPUT_DIR/profile_media"
fi

# Patch tweets.json for optional features
if [[ -n "$LOGO_FILE" ]]; then
  ext="${LOGO_FILE##*.}"
  dest_logo="profile_logo.$ext"
  cp "$LOGO_FILE" "$OUTPUT_DIR/$dest_logo"
  echo "Adding custom logo (full): $dest_logo"

  python3 -c "
path = '$OUTPUT_DIR/index.html'
with open(path) as f: html = f.read()
html = html.replace(
    '<meta name=\"description\" content=\"Twitter/X archive viewer\">',
    '<meta name=\"description\" content=\"Twitter/X archive viewer\">\n  <meta property=\"og:image\" content=\"$dest_logo\">'
)
with open(path, 'w') as f: f.write(html)
"

  dest_logo_icon=""
  if [[ -n "$LOGO_ICON_FILE" ]]; then
    icon_ext="${LOGO_ICON_FILE##*.}"
    dest_logo_icon="profile_logo_icon.$icon_ext"
    cp "$LOGO_ICON_FILE" "$OUTPUT_DIR/$dest_logo_icon"
    echo "Adding custom logo (icon): $dest_logo_icon"
  fi

  (cd "$OUTPUT_DIR" && _LOGO="$dest_logo" _LOGO_ICON="$dest_logo_icon" \
    python3 -c "
import json, os
path = 'tweets.json'
logo = os.environ['_LOGO']
logo_icon = os.environ.get('_LOGO_ICON', '')
with open(path) as f: data = json.load(f)
data['account']['logoFile'] = logo
if logo_icon:
    data['account']['logoIconFile'] = logo_icon
with open(path, 'w') as f: json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
")
fi

if ! $INCLUDE_WALLPAPER; then
  echo "Removing wallpaper (--no-wallpaper)..."
  (cd "$OUTPUT_DIR" && python3 -c "
import json
with open('tweets.json') as f: data = json.load(f)
data['account']['localHeader'] = None
data['account']['headerUrl'] = None
with open('tweets.json', 'w') as f: json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
")
fi

if $INCLUDE_MEDIA; then
  if [[ "$MODE" == "local" ]]; then
    echo "Linking tweets_media (--local)..."
    ln -s "$TWEETS_MEDIA" "$OUTPUT_DIR/tweets_media"
  else
    echo "Copying tweets_media (--online, this may take a moment)..."
    cp -r "$TWEETS_MEDIA" "$OUTPUT_DIR/tweets_media"
  fi
else
  echo "Skipping tweets_media (--no-media). Images will fall back to Twitter CDN."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "=== Done! ==="
du -sh "$OUTPUT_DIR" 2>/dev/null || true
echo ""

if [[ "$MODE" == "local" ]]; then
  echo "To preview locally:"
  echo "  cd \"$OUTPUT_DIR\""
  echo "  python3 -m http.server 8080"
  echo "  Then open: http://localhost:8080/"
  if $INCLUDE_MEDIA; then
    echo ""
    echo "Note: tweets_media is a symlink pointing into your archive."
    echo "Keep the archive at $ARCHIVE_DIR or re-run this script."
  fi
else
  echo "To deploy:"
  echo "  Upload the entire contents of the output folder to your web server."
  echo "  The viewer works at any URL path — no server-side configuration needed."
fi
