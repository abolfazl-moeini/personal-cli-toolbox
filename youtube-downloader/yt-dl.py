#!/usr/bin/env python3
from __future__ import annotations    # <- keeps annotations as strings on <3.10
"""
Batch‑download YouTube links using yt‑dlp (aria2c by default),
skip finished files, resume partials, quality fallback, cookie bypass.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional               # <-- Added

# --------------------------------------------------------------------------- #
FILENAME_TEMPLATE = "%(title)s [%(id)s].%(ext)s"


# Works on py3.8/3.9 now
def extract_video_id(url: str) -> Optional[str]:   # <-- Optional here
    patterns = [
        r"[?&]v=([0-9A-Za-z_-]{11})",
        r"youtu\.be/([0-9A-Za-z_-]{11})",
        r"embed/([0-9A-Za-z_-]{11})",
        r"youtube\.com/v/([0-9A-Za-z_-]{11})",
    ]
    for pat in patterns:
        m = re.search(pat, url)
        if m:
            return m.group(1)
    return None


def is_fully_downloaded(vid: str, directory: Path) -> bool:
    for p in directory.iterdir():
        if f"[{vid}]." in p.name and not p.name.endswith((".part", ".aria2")):
            return True
    return False


def build_cmd_sets(url: str, args):
    base = [
        "yt-dlp",
        "--continue",
        "--no-mtime",
        "--merge-output-format",
        "mp4",
        "--newline",
        "-o",
        FILENAME_TEMPLATE,
    ]
    if not args.public:
        base += ["--cookies-from-browser", args.browser]

    if not args.native:                       # aria2c default
        aria_args = "-x 16 -j 16 -k 5M -c"
        base += [
            "--external-downloader",
            "aria2c",
            "--external-downloader-args",
            aria_args,
        ]

    if args.audio:
        primary = ["-f", "bestaudio", "--extract-audio", "--audio-format", "mp3"]
        fallback = primary
    else:
        limit = args.quality
        primary = [
            "-f",
            f"bestvideo[height<={limit}]+bestaudio/best[height<={limit}]",
        ]
        fallback = ["-f", "bestvideo+bestaudio/best"]

    return base, primary, fallback


def download_url(url: str, args, outdir: Path):
    vid = extract_video_id(url)
    if vid and is_fully_downloaded(vid, outdir):
        print(f"⏩  Already downloaded – skipping {vid}")
        return

    base, primary, fallback = build_cmd_sets(url, args)

    try:
        subprocess.run(base + primary + [url], check=True)
    except subprocess.CalledProcessError:
        print("⚠️  Requested quality not available — retrying with best …")
        subprocess.run(base + fallback + [url], check=True)


def parse_cli():
    p = argparse.ArgumentParser(
        description="Batch YouTube downloader (aria2c default) "
        "with skip/resume logic."
    )
    p.add_argument("listfile", help="Text file with YouTube URLs")
    p.add_argument("-a", "--audio", action="store_true", help="Audio‑only (MP3)")
    p.add_argument("-q", "--quality", default="720", help="Max height (default 720)")
    p.add_argument(
        "-b",
        "--browser",
        default="chrome",
        help="Browser for cookies (chrome/safari/firefox/edge/brave)",
    )
    p.add_argument("-p", "--public", action="store_true", help="Disable cookies")
    p.add_argument(
        "-n",
        "--native",
        action="store_true",
        help="Use yt‑dlp's native downloader (disable aria2c)",
    )
    p.add_argument(
        "-o",
        "--out",
        default=".",
        help="Output directory (default current folder)",
    )
    return p.parse_args()


def main():
    args = parse_cli()
    outdir = Path(args.out).expanduser().resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    list_path = Path(args.listfile).expanduser()
    if not list_path.is_file():
        sys.exit(f"File not found: {list_path}")

    urls = [u.strip() for u in list_path.read_text().splitlines() if u.strip()]

    for url in urls:
        print(f"\n==> {url}")
        try:
            download_url(url, args, outdir)
        except subprocess.CalledProcessError as err:
            print(f"⛔  Download failed: {err}", file=sys.stderr)


if __name__ == "__main__":
    main()
