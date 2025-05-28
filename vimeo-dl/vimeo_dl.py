#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vimeo Private *Range* Downloader

Download private Vimeo videos—or audio-only tracks—from modern
`range/playlist.json` manifests and the legacy player “config” JSON.

Key features
------------
* Accepts a local **file path** *or* **URL** to the manifest.
* Selects the best video (highest resolution) and audio (highest bitrate).
* Streams segments directly to disk (128 KiB chunks, low RAM use).
* Supports `--audio-only`.
* Muxes video + audio losslessly with ffmpeg (`-c copy`).

Author :  github.com/your-nick
License :  MIT
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from tqdm import tqdm

SEG_SIZE = 1 << 17          # 128 KiB


# ---------------------------------------------------------------------
# Networking helpers
# ---------------------------------------------------------------------
def _load_json(src: str) -> tuple[dict, str]:
    """Return (parsed_json, absolute_manifest_url)."""
    if urlparse(src).scheme in ("http", "https"):
        resp = requests.get(src, timeout=10)
        resp.raise_for_status()
        return resp.json(), src
    p = Path(src)
    return json.loads(p.read_text("utf-8")), p.resolve().as_uri()


def _stream_get(url: str, session: requests.Session) -> requests.Response:
    """HTTP GET with streaming enabled and error handling."""
    r = session.get(url, stream=True, timeout=15)
    r.raise_for_status()
    return r


# ---------------------------------------------------------------------
# Rendition selection
# ---------------------------------------------------------------------
def _score_video(v: dict) -> tuple[int, int, int]:
    """Return a sortable score: (height, width, bitrate)."""
    return (
        v.get("height", 0),
        v.get("width", 0),
        v.get("bitrate", v.get("avg_bitrate", 0)),
    )


def _score_audio(a: dict) -> int:
    """Return audio score: bitrate."""
    return a.get("bitrate", a.get("avg_bitrate", 0))


def _best(streams: list[dict], *, video: bool = True) -> dict:
    """Pick the best rendition by the appropriate score."""
    key = _score_video if video else _score_audio
    return max(streams, key=key)


# ---------------------------------------------------------------------
# Download logic
# ---------------------------------------------------------------------
def _write_rendition(rep: dict, base_url: str, out_file: str,
                     session: requests.Session) -> None:
    """Download init_segment + all segments to *out_file*."""
    with open(out_file, "wb") as fp:
        # init_segment is base64-encoded fMP4 header
        fp.write(base64.b64decode(rep["init_segment"]))

        # media segments
        for seg in tqdm(rep["segments"], desc=Path(out_file).name, unit="seg"):
            seg_url = urljoin(base_url, seg["url"])
            for chunk in _stream_get(seg_url, session).iter_content(SEG_SIZE):
                fp.write(chunk)


def _mux(video_f: str, audio_f: str, out_f: str) -> None:
    """Losslessly mux *video_f* and *audio_f* into *out_f*."""
    subprocess.check_call(
        [
            "ffmpeg",
            "-loglevel",
            "error",
            "-y",
            "-i",
            video_f,
            "-i",
            audio_f,
            "-c",
            "copy",
            out_f,
        ]
    )


# ---------------------------------------------------------------------
# Legacy “config” downloader (simpler fallback)
# ---------------------------------------------------------------------
def _download_config(data: dict, output: str, audio_only: bool) -> None:
    """Handle old `player ... /config` manifests via ffmpeg directly."""
    files = data["request"]["files"]

    # helper: pick progressive > HLS > DASH
    def _choose_stream() -> str:
        progressive = files.get("progressive", [])
        if progressive and not audio_only:
            return max(progressive, key=lambda x: int(x.get("height", 0)))["url"]

        for proto in ("hls", "dash"):
            cdns = files.get(proto, {}).get("cdns", {})
            if cdns:
                return next(iter(cdns.values()))["url"]

        raise RuntimeError("No playable stream found in legacy config!")

    stream_url = _choose_stream()

    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-i", stream_url]
    cmd += ["-vn", "-c", "copy", output] if audio_only else ["-c", "copy", output]
    subprocess.check_call(cmd)


# ---------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------
def main() -> None:
    ap = argparse.ArgumentParser(
        description="Download private Vimeo video or audio from "
        "`range/playlist.json` (or legacy config) manifests."
    )
    ap.add_argument("manifest", help="Manifest URL or local file path")
    ap.add_argument("output", help="Target file name (e.g. movie.mp4 / track.m4a)")
    ap.add_argument(
        "--audio-only",
        action="store_true",
        help="Download audio track only (no video)",
    )
    args = ap.parse_args()

    data, manifest_url = _load_json(args.manifest)
    session = requests.Session()

    # -----------------------------------------------------------------
    # Modern range manifest
    # -----------------------------------------------------------------
    if {"video", "audio"}.issubset(data):
        base_url = urljoin(manifest_url, data["base_url"])

        if args.audio_only:
            audio_rep = _best(data["audio"], video=False)
            _write_rendition(audio_rep, base_url, args.output, session)
        else:
            video_rep = _best(data["video"], video=True)
            audio_rep = _best(data["audio"], video=False)
            _write_rendition(video_rep, base_url, "tmp_video.mp4", session)
            _write_rendition(audio_rep, base_url, "tmp_audio.m4a", session)
            _mux("tmp_video.mp4", "tmp_audio.m4a", args.output)
            os.remove("tmp_video.mp4")
            os.remove("tmp_audio.m4a")

    # -----------------------------------------------------------------
    # Legacy player config
    # -----------------------------------------------------------------
    elif data.get("request", {}).get("files"):
        _download_config(data, args.output, args.audio_only)

    else:
        sys.exit("Unknown manifest structure!")

    print("✔ Saved →", Path(args.output).resolve())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:  # pylint: disable=broad-except
        sys.exit(f"⚠️  {exc}")