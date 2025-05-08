# ytbatch (aria‑first) — TL;DR

**Batch‑download YouTube videos with `yt‑dlp` + `aria2c` (default)**  
*Quality fallback · Browser‑cookie bypass · Audio‑only option · macOS‑friendly*

---

## 1 . Prerequisites

| Tool | Homebrew | MacPorts | PyPI |
|------|----------|----------|------|
| yt‑dlp | `brew install yt-dlp` | `sudo port install yt-dlp` | `pip install -U yt-dlp` |
| ffmpeg | `brew install ffmpeg` | `sudo port install ffmpeg` | — |
| aria2c | `brew install aria2` | `sudo port install aria2` | — |

> Check that `yt-dlp --version` shows a recent build.

---

## 2 . Save your links

```text
links.txt
https://youtu.be/abc123
https://www.youtube.com/watch?v=def456
```

One URL per line (blank lines ignored).

---

## 3 . Run

```bash
chmod +x yt-dl.py
./yt-dl.py links.txt            # ≤720 p, uses aria2c
```

### Frequently used flags

| Flag | Purpose | Example |
|------|---------|---------|
| `-q 1080` | Set max video height (default 720) | `-q 1080` |
| `-a`, `--audio` | Download audio‑only MP3 | `--audio` |
| `-b safari` | Use Safari cookies (default chrome) | `-b safari` |
| `-p`, `--public` | Skip cookies (public videos only) | `--public` |
| `-n`, `--native` | **Disable aria2c** → use yt‑dlp’s internal downloader | `--native` |

---

## 4 . Examples

```bash
# 1080 p video, cookies from Firefox, fast aria2c
./yt-dl.py links.txt -q 1080 -b firefox

# Audio‑only, no cookies
./yt-dl.py links.txt --audio --public

# Fall back to yt‑dlp internal downloader
./yt-dl.py links.txt --native
```

---

## 5 . Troubleshooting

* **HTTP 429 / CAPTCHA** → use browser cookies (`-b chrome`, etc.) or a VPN.  
* **Format not available** → script auto‑tries best available quality.  
* **Signature errors / 400** → update yt‑dlp: `yt-dlp -U`.

---

Happy downloading! 🎬
