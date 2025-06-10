# Vimeo Range Downloader (`vimeo_dl.py`)

> **TL;DR**  
> A single-file CLI that downloads private Vimeo videos (or audio-only) from
> `range/playlist.json` manifests _and_ legacy *player config* JSON.  
> It fetches all segments, stitches them together, and—if needed—muxes video +
> audio with `ffmpeg` in **copy** mode (no re-encoding).

---

## Features

- **Range & Config support** – works with the modern `.../range/playlist.json`
  API _and_ the classic `player.vimeo.com/video/<id>/config` JSON.
- **Best rendition auto-selection** – picks the highest resolution video and the
  highest bitrate audio available.
- **Audio-only flag** – `--audio-only` downloads just the audio track.
- **Streamed download** – segments are streamed in 128 KiB chunks; RAM friendly.
- **Tiny footprint** – pure Python + `requests`, `tqdm`, and a system
  `ffmpeg`.

---

## Requirements
pip install "curl_cffi[requests]"
| Dependency | Minimum Version | Install Hint                          |
|------------|-----------------|---------------------------------------|
| Python     | 3.8             | `python -m pip install --upgrade pip` |
| requests   | —               | `pip install requests`                |
| tqdm       | —               | `pip install tqdm`                    |
| requests   | —               | `pip install curl_cffi[requests]`     |
| ffmpeg     | 4.x             | Linux `apt install ffmpeg` / macOS `brew install ffmpeg` / Windows `choco install ffmpeg` |

A convenience file is included:

```bash
# requirements.txt
requests
tqdm
```

Install everything with:

```bash
pip install -r requirements.txt
```

---

## Usage

```bash
# Download full video (best resolution)
python vimeo_dl.py "<playlist.json URL | local path>" output.mp4

# Download audio-only
python vimeo_dl.py "<playlist.json URL | local path>" podcast.m4a --audio-only
```

### Examples

```bash
python vimeo_dl.py \
  "https://vod-adaptive-ak.vimeocdn.com/.../playlist.json?..." \
  lecture.mp4

python vimeo_dl.py playlist.json lecture.m4a --audio-only
```

---

## How it works

1. **Detect manifest type**  
   If the JSON contains `"video"` + `"audio"` arrays it is treated as a
   **range** manifest; otherwise it is parsed as the legacy **config** structure.

2. **Select renditions**  
   The script scores each video rendition by `(height, width, bitrate)` and each
   audio rendition by `bitrate`, picking the maximum.

3. **Download**  
   - The binary `init_segment` (base64) is written first.  
   - Every segment URL is resolved against `base_url` and streamed to disk with
     `requests`, showing a `tqdm` progress bar.

4. **Mux (video mode)**  
   Video & audio files are combined with:

   ```bash
   ffmpeg -i video_tmp.mp4 -i audio_tmp.m4a -c copy output.mp4
   ```

---

## FAQ

- **Why do I get 403/410 errors after a while?**  
  Manifest and segment URLs contain short-lived tokens (`exp=`, `hmac=`). Grab
  a fresh URL from your browser’s DevTools if it expires.

- **Can I pass cookies/headers?**  
  Modify `stream_get()` to forward `cookies=` or `headers=` to `requests`.

- **Is this legal?**  
  Only download content you are authorised to access. This tool is for
  educational and archival purposes **only**.

---

## License

MIT © 2025 — Feel free to fork, modify, and share.
