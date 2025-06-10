#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vimeo Private Downloader (Bulletproof Edition)

This version uses a fully integrated, resumable native downloader that
impersonates a browser to bypass advanced CDN protections. It is designed
to be as simple and robust as possible for the end-user.

Key features
------------
* **Fully Integrated Browser Impersonation:** Uses a single, smart session
  (curl_cffi) for all network requests, eliminating handoff errors.
* **Built-in Resumable Downloads:** If the download is interrupted, it will
  resume from the last fully downloaded segment automatically.
* **Fully Automated:** No need for manual cookie files or referer flags.
* **Simple Usage:** Just provide the manifest and output file.
* Lossless muxing with ffmpeg.

Author :  github.com/your-nick
License :  MIT
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse

from curl_cffi.requests import Session as CurlCffiSession
from tqdm import tqdm

# A modern browser User-Agent
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36"


# ---------------------------------------------------------------------
# Smart Networking & Rendition Selection
# ---------------------------------------------------------------------
def _get_smart_session() -> CurlCffiSession:
    """Return a session that impersonates a modern browser."""
    return CurlCffiSession(impersonate="chrome110", headers={"User-Agent": USER_AGENT})


def _load_json_smart(src: str, session: CurlCffiSession) -> tuple[dict, str]:
    """Return (parsed_json, absolute_manifest_url)."""
    if urlparse(src).scheme in ("http", "https"):
        resp = session.get(src, timeout=15)
        resp.raise_for_status()
        return resp.json(), src
    p = Path(src)
    return json.loads(p.read_text("utf-8")), p.resolve().as_uri()


def _best(streams: list[dict], *, video: bool = True) -> dict:
    key = (lambda v: (v.get("height", 0), v.get("width", 0), v.get("bitrate", 0))) if video else (lambda a: a.get("bitrate", 0))
    return max(streams, key=key)


# ---------------------------------------------------------------------
# Bulletproof Resumable Downloader
# ---------------------------------------------------------------------
def _download_resumable(
    rep: dict, base_url: str, out_file: str, session: CurlCffiSession
) -> None:
    """
    Downloads all segments resumably, inside a single smart session.
    If the output file exists, it calculates where to resume from.
    """
    init_data = base64.b64decode(rep["init_segment"])
    init_size = len(init_data)
    segments = rep["segments"]
    total_segments = len(segments)
    
    start_index = 0
    mode = "wb"
    
    # --- Resume Logic ---
    if os.path.exists(out_file):
        current_size = os.path.getsize(out_file)
        if current_size > init_size:
            print(f"File '{out_file}' exists. Attempting to resume...")
            mode = "ab"  # Append mode
            
            downloaded_media_bytes = current_size - init_size
            cumulative_bytes = 0
            
            for i, seg in enumerate(segments):
                cumulative_bytes += seg['size']
                if cumulative_bytes > downloaded_media_bytes:
                    # This segment is the one to start from.
                    # We assume the previous segment completed fully.
                    start_index = i
                    print(f"Resuming from segment {start_index + 1} of {total_segments}.")
                    break
            else:
                # This means all segments were downloaded.
                print("File appears to be fully downloaded. Skipping.")
                return
        else:
            print(f"File '{out_file}' is incomplete. Starting over.")

    # --- Download Loop ---
    with open(out_file, mode) as fp, tqdm(
        total=total_segments,
        initial=start_index,
        desc=f"Downloading {Path(out_file).name}",
        unit="seg"
    ) as pbar:
        
        if start_index == 0 and mode == "wb":
            fp.write(init_data)

        for i in range(start_index, total_segments):
            seg_url = urljoin(base_url, segments[i]["url"])
            try:
                resp = session.get(seg_url, timeout=20)
                resp.raise_for_status()
                fp.write(resp.content)
                pbar.update(1)
            except Exception as e:
                print(f"\nError downloading segment {i+1}: {e}", file=sys.stderr)
                print(f"To resume, simply run the command again.", file=sys.stderr)
                sys.exit(1)


def _mux(video_f: str, audio_f: str, out_f: str) -> None:
    """Losslessly mux *video_f* and *audio_f* into *out_f*."""
    print("🎬 Muxing video and audio with ffmpeg...")
    subprocess.check_call(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", video_f, "-i", audio_f, "-c", "copy", out_f]
    )


# ---------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------
def main() -> None:
    ap = argparse.ArgumentParser(
        description="Vimeo Private Downloader (Smart & Automated).",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    ap.add_argument("manifest", help="Manifest URL or local file path")
    ap.add_argument("output", help="Target file name (e.g., movie.mp4)")
    ap.add_argument(
        "--audio-only", action="store_true", help="Download audio track only"
    )
    args = ap.parse_args()

    # Create a single, powerful session to be used for everything.
    session = _get_smart_session()
    data, manifest_url = _load_json_smart(args.manifest, session)

    # Automatically set the Referer for the session
    auto_referer = data.get("vimeo_api", {}).get("embed_code_url")
    if auto_referer:
        session.headers["Referer"] = auto_referer
    else:
        # Fallback if the specific embed URL isn't in the manifest
        parsed_uri = urlparse(manifest_url)
        session.headers["Referer"] = f"{parsed_uri.scheme}://{parsed_uri.netloc}/"
    
    tmp_files = []

    if "video" in data and "audio" in data:
        clip_base_url = urljoin(manifest_url, data.get("base_url", ""))

        if args.audio_only:
            audio_rep = _best(data["audio"], video=False)
            rendition_base_url = urljoin(clip_base_url, audio_rep.get("base_url", ""))
            _download_resumable(audio_rep, rendition_base_url, args.output, session)
        else:
            video_f, audio_f = "tmp_video.mp4", "tmp_audio.m4a"
            tmp_files.extend([video_f, audio_f])

            video_rep = _best(data["video"], video=True)
            audio_rep = _best(data["audio"], video=False)

            video_base_url = urljoin(clip_base_url, video_rep.get("base_url", ""))
            audio_base_url = urljoin(clip_base_url, audio_rep.get("base_url", ""))

            # Download video and audio
            _download_resumable(video_rep, video_base_url, video_f, session)
            _download_resumable(audio_rep, audio_base_url, audio_f, session)
            
            _mux(video_f, audio_f, args.output)
    else:
        sys.exit("Unknown manifest structure! This script supports modern `playlist.json` manifests.")

    print(f"\n✔ Download complete! Saved to: {Path(args.output).resolve()}")

    # Final cleanup
    for f in tmp_files:
        if os.path.exists(f):
            os.remove(f)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n🚫 Download cancelled by user.", file=sys.stderr)
        sys.exit(130)
    except Exception as exc:
        sys.exit(f"⚠️ An error occurred: {exc}")