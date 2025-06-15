# M3U8 Downloader Script

A powerful Bash script to download HLS (M3U8) streams, with automatic quality selection. It uses `aria2c` for fast, parallel segment downloading and `ffmpeg` for stitching them into a single file.

## Features

- 🚀 **Fast Downloads:** Uses `aria2a` for multi-connection segment downloading.
- 🧠 **Smart:** Automatically detects master playlists and lets you choose the quality.
- 💾 **Lossless:** Copies the video and audio streams without re-encoding, preserving original quality.
- 🧹 **Clean:** Uses a temporary directory for segments and cleans up after itself.
- 🤖 **Robust:** Handles relative/absolute paths and sorts segments correctly before stitching.

---

## TL;DR - Quick Start

**1. Install Dependencies:**

*  **On Debian/Ubuntu:**
    ```bash
    sudo apt update && sudo apt install ffmpeg aria2 curl
    ```
*  **On macOS (with Homebrew):**
    ```bash
    brew install ffmpeg aria2 curl
    ```

**2. Download the script:**
```bash
chmod +x download-m3u8.sh
```

**3. Run it:**
```bash
./download-m3u8.sh "URL_TO_M3U8" "my_video.mp4"
```

---

## Usage

### Syntax

```
./download-m3u8.sh "<M3U8_URL>" "<OUTPUT_FILENAME>"
```

## Options

| Flag | Description |
| ---- | ----------- |
| -r, --referer | Specify a custom HTTP Referer URL to bypass blocks. |
| -h, --help | Display the help message. |

### Parameters

- `M3U8_URL` (Required): The link to the M3U8 file. This can be a master playlist (with multiple quality options) or a direct media playlist.
- `OUTPUT_FILENAME` (Required): The name of the final video file (e.g., `video.mp4`, `lecture.mkv`).

### Example

```bash
# Provide the URL and the desired output file name
./download-m3u8.sh "https://example.com/stream/master.m3u8" "final-video.mp4"
```

If the script detects a master playlist, it will prompt you to choose a quality:

```
Master playlist detected. Parsing available streams...

Please choose a quality to download:
  1) Resolution: 1920x1080, Bandwidth: 6560kbps
  2) Resolution: 1280x720, Bandwidth: 3589kbps
  3) Resolution: 854x480, Bandwidth: 1874kbps
Enter number (1-3): 1
```

The script will then download the 1080p stream and save it as `final-video.mp4`.