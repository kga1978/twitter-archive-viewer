#!/usr/bin/env python3
"""
Generate viewer/tweets.json from a Twitter/X data archive.

Default usage (run from archive root):
    python3 process_tweets.py

General usage (any archive, any output directory):
    python3 process_tweets.py --archive /path/to/archive --output /path/to/output/dir
"""
import json
import re
import os
import argparse
import subprocess
import urllib.request
from datetime import datetime


def resolve_url(url):
    """Follow redirects (e.g. t.co) and return the final URL. Falls back to original on error."""
    if not url:
        return url
    # curl is more reliable for t.co (urllib gets 403 from Twitter)
    try:
        result = subprocess.run(
            ['curl', '-sI', '-L', '--max-redirs', '5', '-o', '/dev/null',
             '-w', '%{url_effective}', url],
            capture_output=True, text=True, timeout=10
        )
        final = result.stdout.strip()
        if final and final != url:
            return final
    except Exception:
        pass
    # urllib fallback
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=8) as resp:
            return resp.url
    except Exception:
        pass
    return url


def read_js_file(path):
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    json_str = re.sub(r'^window\.[A-Za-z0-9_.]+\s*=\s*', '', raw.strip()).rstrip(';')
    return json.loads(json_str)


def parse_twitter_date(s):
    try:
        dt = datetime.strptime(s, '%a %b %d %H:%M:%S +0000 %Y')
        return dt.strftime('%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        return s


def build_media_index(media_dir):
    """Index local media files: tweet_id -> list of filenames."""
    index = {}
    if not os.path.exists(media_dir):
        return index
    for fname in os.listdir(media_dir):
        if fname.startswith('.'):
            continue
        dash = fname.find('-')
        if dash > 0:
            index.setdefault(fname[:dash], []).append(fname)
    return index


def find_local_media(tweet_id, media_url, media_index):
    """Match a CDN media URL to a local file by the hash portion of the filename."""
    stem = os.path.splitext(os.path.basename(media_url))[0]
    for fname in media_index.get(tweet_id, []):
        if stem in fname:
            return fname
    return None


def find_local_profile_image(url, profile_media_dir):
    if not url or not os.path.exists(profile_media_dir):
        return None
    stem = os.path.splitext(os.path.basename(url))[0]
    for fname in os.listdir(profile_media_dir):
        if not fname.startswith('.') and stem in fname:
            return fname
    return None


def process_tweet(entry, media_index):
    tweet = entry['tweet']
    text = tweet.get('full_text', '')

    if text.startswith('RT @'):
        return None

    tweet_id = tweet['id_str']
    entities = tweet.get('entities', {})
    # extended_entities has full video/gif info and de-duped media
    ext_entities = tweet.get('extended_entities', {})

    # --- Media ---
    media_list = []
    seen_ids = set()
    raw_media = ext_entities.get('media') or entities.get('media') or []
    for m in raw_media:
        mid = m.get('id_str', '')
        if mid in seen_ids:
            continue
        seen_ids.add(mid)

        mtype = m.get('type', 'photo')
        media_url = m.get('media_url_https') or m.get('media_url', '')
        local_file = find_local_media(tweet_id, media_url, media_index)

        w, h = 0, 0
        for sz in ('large', 'medium', 'small'):
            s = m.get('sizes', {}).get(sz)
            if s:
                w, h = int(s['w']), int(s['h'])
                break

        video_url = None
        if mtype in ('video', 'animated_gif'):
            variants = m.get('video_info', {}).get('variants', [])
            mp4s = [v for v in variants if v.get('content_type') == 'video/mp4']
            if mp4s:
                best = max(mp4s, key=lambda v: int(v.get('bitrate', 0)))
                video_url = best['url']

        media_list.append({
            'id': mid,
            'type': mtype,
            'local_file': local_file,
            'remote_url': media_url,
            'width': w,
            'height': h,
            'video_url': video_url,
            'indices': [int(i) for i in m.get('indices', [])]
        })

    # --- Entities ---
    mentions = [
        {'screen_name': m['screen_name'], 'name': m['name'],
         'indices': [int(i) for i in m['indices']]}
        for m in entities.get('user_mentions', [])
    ]
    urls = [
        {'url': u['url'], 'expanded_url': u['expanded_url'],
         'display_url': u['display_url'], 'indices': [int(i) for i in u['indices']]}
        for u in entities.get('urls', [])
    ]
    hashtags = [
        {'text': h['text'], 'indices': [int(i) for i in h['indices']]}
        for h in entities.get('hashtags', [])
    ]

    # --- Reply info ---
    reply_to = None
    if tweet.get('in_reply_to_status_id_str'):
        reply_to = {
            'tweet_id': tweet['in_reply_to_status_id_str'],
            'screen_name': tweet.get('in_reply_to_screen_name', ''),
            'user_id': tweet.get('in_reply_to_user_id_str', '')
        }

    return {
        'id': tweet_id,
        'created_at': parse_twitter_date(tweet.get('created_at', '')),
        'text': text,
        'lang': tweet.get('lang', ''),
        'metrics': {
            'likes': int(tweet.get('favorite_count') or 0),
            'retweets': int(tweet.get('retweet_count') or 0)
        },
        'entities': {'mentions': mentions, 'urls': urls, 'hashtags': hashtags},
        'media': media_list,
        'reply_to': reply_to
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate a viewer from a Twitter/X data archive.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    parser.add_argument(
        '--archive', default=None,
        help='Path to archive root directory (default: directory containing this script)')
    parser.add_argument(
        '--output', default=None,
        help='Output directory for tweets.json (default: <archive>/viewer/)')
    args = parser.parse_args()

    # Resolve paths
    if args.archive:
        archive_dir = os.path.abspath(args.archive)
    else:
        archive_dir = os.path.dirname(os.path.abspath(__file__))

    data_dir          = os.path.join(archive_dir, 'data')
    media_dir         = os.path.join(data_dir, 'tweets_media')
    profile_media_dir = os.path.join(data_dir, 'profile_media')

    if args.output:
        viewer_dir = os.path.abspath(args.output)
    else:
        viewer_dir = os.path.join(archive_dir, 'viewer')

    print('Building media index...')
    media_index = build_media_index(media_dir)
    print(f'  Found {sum(len(v) for v in media_index.values())} local media files')

    print('Reading tweets.js...')
    raw_tweets = read_js_file(os.path.join(data_dir, 'tweets.js'))
    print(f'  {len(raw_tweets)} raw tweets')

    print('Processing...')
    processed = []
    skipped_rt = 0
    for entry in raw_tweets:
        result = process_tweet(entry, media_index)
        if result is None:
            skipped_rt += 1
        else:
            processed.append(result)

    processed.sort(key=lambda t: t['created_at'], reverse=True)

    print('Reading profile data...')
    profile_data  = read_js_file(os.path.join(data_dir, 'profile.js'))
    account_data  = read_js_file(os.path.join(data_dir, 'account.js'))
    follower_data = read_js_file(os.path.join(data_dir, 'follower.js'))
    following_data = read_js_file(os.path.join(data_dir, 'following.js'))

    profile = profile_data[0]['profile'] if profile_data else {}
    account = account_data[0]['account'] if account_data else {}
    description = profile.get('description', {})

    avatar_url = profile.get('avatarMediaUrl', '')
    header_url = profile.get('headerMediaUrl', '')

    raw_website = description.get('website', '')
    if raw_website:
        print(f'Resolving website URL: {raw_website}')
        resolved_website = resolve_url(raw_website)
        if resolved_website != raw_website:
            print(f'  → {resolved_website}')
    else:
        resolved_website = raw_website

    output = {
        'account': {
            'username': account.get('username', ''),
            'displayName': account.get('accountDisplayName', ''),
            'bio': description.get('bio', ''),
            'location': description.get('location', ''),
            'websiteUrl': resolved_website,
            'avatarUrl': avatar_url,
            'localAvatar': find_local_profile_image(avatar_url, profile_media_dir),
            'headerUrl': header_url,
            'localHeader': find_local_profile_image(header_url, profile_media_dir),
            'joined': account.get('createdAt', ''),
            'followerCount': len(follower_data),
            'followingCount': len(following_data)
        },
        'stats': {
            'total': len(processed),
            'skippedRetweets': skipped_rt,
            'earliest': processed[-1]['created_at'] if processed else '',
            'latest': processed[0]['created_at'] if processed else ''
        },
        'tweets': processed
    }

    os.makedirs(viewer_dir, exist_ok=True)
    out_path = os.path.join(viewer_dir, 'tweets.json')
    print('Writing tweets.json...')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, separators=(',', ':'))

    size_mb = os.path.getsize(out_path) / 1024 / 1024
    print(f'\nDone!')
    print(f'  {len(processed)} tweets kept  ({skipped_rt} bare retweets skipped)')
    print(f'  Output: {out_path}  ({size_mb:.1f} MB)')

    # Create symlinks so the viewer can find media files locally.
    # Only when using the default output path (backward compat with direct invocation).
    # When --output is set, make_archive_viewer.sh handles media linking/copying.
    if not args.output:
        for link_name, target in [('tweets_media', media_dir), ('profile_media', profile_media_dir)]:
            link_path = os.path.join(viewer_dir, link_name)
            if not os.path.lexists(link_path) and os.path.exists(target):
                os.symlink(target, link_path)
                print(f'  Symlink: viewer/{link_name} -> data/{link_name}')

    print('\nTo preview: serve viewer/ via HTTP (e.g. python3 -m http.server 8080)')


if __name__ == '__main__':
    main()
