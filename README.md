# Twitter/X Archive Viewer

A self-contained viewer for your Twitter/X data archive. Works locally in a browser and can be deployed to any web server — no database, no server-side code, no external dependencies.

![Dark themed viewer with sidebar, tweet timeline, search, and media](https://raw.githubusercontent.com/placeholder/screenshot.png)

## Features

- Posts and Replies tabs with infinite scroll
- Full-text search across all tweets
- Date range and sort filters
- Inline media (images, videos, GIFs)
- Threaded conversations
- Embedded quote cards and reply references via oEmbed
- Deep-linkable URLs (`#tweet-<id>`)
- Mobile-responsive layout

## Requirements

- **Python 3** (any version ≥ 3.7)
- **bash** (macOS, Linux, or WSL on Windows)
- Your Twitter/X data archive (the folder you downloaded from Settings → Your account → Download an archive)

## Quick start

```bash
git clone <this-repo> twitter-archive-viewer
cd twitter-archive-viewer

bash make_archive_viewer.sh ~/Downloads/twitter_archive --local
```

Then open the printed URL in a browser (e.g. `http://localhost:8080`).

## Usage

```
bash make_archive_viewer.sh <archive_dir> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<archive_dir>` | Path to your Twitter/X archive root (the folder containing `data/`) |
| `--local` | **(default)** Local preview mode. Uses a symlink for `tweets_media` so no files are duplicated. |
| `--online` | Web deployment mode. Copies all files, no symlinks. Use this when uploading to a server. |
| `--no-media` | Skip `tweets_media`. Images fall back to Twitter CDN URLs, which may stop working over time. |
| `--no-wallpaper` | Hide the profile header/banner image. |
| `--logo <file>` | Custom image to show in the expanded sidebar (replaces the default `@username` text). |
| `--logo-icon <file>` | Custom image for the collapsed sidebar (32×32). Defaults to `--logo` if omitted. |
| `--output <dir>` | Output directory (default: `<archive_dir>/viewer-output/`) |

### Examples

**Local preview:**
```bash
bash make_archive_viewer.sh ~/Downloads/twitter_archive
# Follow the printed instructions to start the local server
```

**Build for web deployment:**
```bash
bash make_archive_viewer.sh ~/Downloads/twitter_archive --online --output ~/Desktop/my_viewer
# Then upload ~/Desktop/my_viewer/ to your web server
```

**No media (smaller output, images from CDN):**
```bash
bash make_archive_viewer.sh ~/Downloads/twitter_archive --online --no-media --output ~/Desktop/my_viewer
```

**Custom branding with separate logos for expanded and collapsed sidebar:**
```bash
bash make_archive_viewer.sh ~/Downloads/twitter_archive --online \
  --logo ~/my_logo_full.png \
  --logo-icon ~/my_logo_icon.png
```

## Local preview

After running with `--local`, start a local HTTP server:

```bash
cd <output_dir>          # e.g. ~/Downloads/twitter_archive/viewer-output
python3 -m http.server 8080
```

Then open **http://localhost:8080** in a browser.

> **Why HTTP?** The viewer fetches `tweets.json` via `fetch()`, which requires HTTP — it won't work when opened as a `file://` URL directly.

The output in local mode contains a symlink from `tweets_media/` → the original archive's `tweets_media/`. Keep the archive in place, or re-run the script if you move it.

## Web deployment

Run with `--online` to get a fully self-contained folder with no symlinks:

```bash
bash make_archive_viewer.sh ~/Downloads/twitter_archive --online --output ~/Desktop/my_viewer
```

Upload the entire `my_viewer/` folder to your server. The viewer works at any URL path — no `.htaccess`, no rewrites, no server-side configuration needed. You can link directly to the `index.html` or embed it in an iframe.

**Expected output structure:**
```
my_viewer/
├── index.html          # the viewer (single self-contained HTML file)
├── tweets.json         # preprocessed tweet data
├── profile_media/      # avatar and banner images
└── tweets_media/       # all tweet images and videos
```

### Note on media size

`tweets_media/` can be several gigabytes for large archives. If upload size is a concern:
- Use `--no-media` and rely on Twitter CDN URLs (less reliable long-term)
- Or upload only `tweets_media/` to a CDN/object store and update paths manually in `tweets.json`

## What gets included

The script reads your archive's `data/` folder and processes:

| Data | Source |
|------|--------|
| Tweets and replies | `data/tweets.js` |
| Profile info (username, bio, avatar) | `data/account.js`, `data/profile.js` |
| Follower/following counts | `data/follower.js`, `data/following.js` |
| Profile images | `data/profile_media/` |
| Tweet media (images, videos, GIFs) | `data/tweets_media/` |

Bare retweets (`RT @...`) are excluded from the viewer — they add noise without original content.

## Advanced: run `process_tweets.py` directly

The Python script can be used independently:

```bash
# Default: looks for archive in same directory, writes to ./viewer/
python3 process_tweets.py

# Explicit paths:
python3 process_tweets.py --archive ~/Downloads/twitter_archive --output ~/Desktop/my_viewer
```

This writes `tweets.json` to the output directory. You then copy `viewer/index.html` and media directories manually.

## Troubleshooting

**"data/tweets.js not found"** — make sure you're pointing at the archive root (the folder that *contains* `data/`), not the `data/` folder itself.

**Blank page in browser** — you opened `index.html` directly as a `file://` URL. Use the local HTTP server instead.

**Images not loading** — if you used `--no-media`, images rely on Twitter CDN URLs which may expire. Re-run with `--online` to copy media locally.

**oEmbed quote cards show "Tweet unavailable"** — those tweets were deleted or the account was suspended. This is expected behavior.
