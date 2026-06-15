# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A zero-dependency tool that converts a Twitter/X personal data archive into a self-contained static web app. Input is the raw archive folder; output is `index.html` + `tweets.json` + media folders that can be served from any static host.

## Commands

**Build the viewer:**
```bash
bash make_archive_viewer.sh <archive_dir> [--local|--online] [--output <dir>] [--no-media] [--no-wallpaper]
```
- `--local` (default): symlinks `tweets_media/` into output
- `--online`: copies media (use for web deployment)
- `--no-media`: skips local media, falls back to Twitter CDN URLs

**Run directly with Python:**
```bash
python3 process_tweets.py --archive <archive_dir> --output <output_dir>
```

**Preview output locally:**
```bash
cd <output_dir> && python3 -m http.server 8080
# Open http://localhost:8080
```

No build step, no package manager, no test suite.

## Architecture

```
twitter-archive-viewer/
├── make_archive_viewer.sh   # Orchestrates build: calls process_tweets.py, copies viewer/
├── process_tweets.py        # Python processing pipeline (stdlib only)
└── viewer/index.html        # Single-file SPA — shipped as-is to output
```

### Data Flow

1. `process_tweets.py` reads the archive's `data/` directory (tweets.js, account.js, profile.js, follower.js, following.js, profile_media/, tweets_media/)
2. Parses Twitter's JS files (`window.YTD.tweets.part0 = [...]` → JSON)
3. Deduplicates media, resolves `t.co` shortened URLs, skips bare retweets
4. Writes `tweets.json` alongside the copied `index.html`

### tweets.json Shape

```json
{
  "account": { "username", "displayName", "bio", "avatarUrl", "localAvatar", ... },
  "stats": { "total", "skippedRetweets", "earliest", "latest" },
  "tweets": [{
    "id", "created_at", "text", "lang",
    "metrics": { "likes", "retweets" },
    "entities": { "mentions", "urls", "hashtags" },
    "media": [{ "type", "local_file", "remote_url", "width", "height", "video_url" }],
    "reply_to": { "tweet_id", "screen_name" }
  }]
}
```

### Frontend (viewer/index.html)

All rendering is client-side. Key runtime data structures:
- `allTweets[]`, `postsBase[]`, `repliesBase[]` — tweet arrays
- `byId{}` — tweet_id → tweet object (for threading/quote resolution)
- `threaded{}` — tweet_id → array of reply tweet objects

Key functions:
- `init()` — fetches tweets.json, builds all data structures, kicks off rendering
- `renderTimeline()` — renders currently visible tweets (infinite scroll via `visibleCount`)
- `buildTweetCard(tweet)` — creates a full tweet DOM element with media, replies, threading
- `getThreadChain(tweetId)` / `findThreadRoot(tweetId)` — conversation tree traversal
- `resolveUrlMeta(tweet, mediaIndices)` — separates archive self-links from external quote links
- `queueOembed(tweetId, callback)` — lazy-loads Twitter oEmbed for external quote cards
- `renderTweetText(text, entities, ...)` — converts raw text + entity offsets to HTML

Tabs (`currentTab`): `"posts"` | `"replies"` | `"search"`. Sort (`sortBy`): `"date-desc"` | `"date-asc"` | `"likes"` | `"retweets"`. Deep-linking via URL hash `#tweet-<id>`.
