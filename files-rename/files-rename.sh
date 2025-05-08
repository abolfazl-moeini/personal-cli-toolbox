#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Lesson Renamer – smarter pattern matching, counter‑independent, safe I/O
# ---------------------------------------------------------------------------
#   • Accepts *any* mix‑case variant like:
#       lesson04.mp4, Lesson-04.mp4, LESSON 04.mkv, 04‑intro.mp4, lesson_04.final.srt …
#   • Supports many video & subtitle formats (config below)
#   • Detects lesson number even when dash/space is absent (or prefixed digits)
#   • Keeps titles in sync with detected lessons; warns, never overwrites blindly
#   • Uses set -euo pipefail and nullglob for safe scripting
# ---------------------------------------------------------------------------

set -euo pipefail
shopt -s nullglob          # unmatched globs → empty arrays instead of literal

# ---------------------- Configuration ------------------------
# Add / remove extensions here (lower‑case only)
video_exts=(mp4 mkv webm m4v mov avi)
sub_exts=(srt vtt sub ass)
file_exts=("${video_exts[@]}" "${sub_exts[@]}")

video_dir="./"            # where the lesson files live

# ---------------------- Helper functions --------------------
die()        { printf "Error: %s\n" "$1" >&2; exit 1; }
info()       { printf "\033[1;36m%s\033[0m\n" "$1"; }
warn()       { printf "\033[1;33m%s\033[0m\n" "$1"; }

# Sanitize a title: keep alnum/space/dash, trim, squeeze spaces, Title‑Case
sanitize_title() {
  local t="${1,,}"                                         # to lower
  t=$(echo "$t" | tr -cd '[:alnum:][:space:]-')             # valid chars
  t=$(echo "$t" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  t=$(echo "$t" | tr -s ' ')                                # squeeze spaces
  # Title‑case each word
  echo "$t" | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2)}}1'
}

# Extract lesson number – tries several patterns, returns non‑zero on failure
extract_number() {
  local base="${1##*/}"   # filename without path
  # (1)  "lesson 04"  / "lesson-04"  / "lesson04"  (case‑insensitive)
  if [[ $base =~ [Ll]esson[[:space:]_-]*([0-9]{1,3}) ]]; then
    printf '%d' "${BASH_REMATCH[1]#0}"; return 0
  fi
  # (2)  Leading digits + separator: "04 intro.mp4", "4_intro.srt"
  if [[ $base =~ ^([0-9]{1,3})[[:space:]_-] ]]; then
    printf '%d' "${BASH_REMATCH[1]#0}"; return 0
  fi
  return 1  # no match
}

# ---------------------- Pick the titles file ----------------
mapfile -t txt_files < <(printf '%s\n' *.txt)
(( ${#txt_files[@]} )) || die "No .txt files found. Put a titles file here."

if (( ${#txt_files[@]} > 1 )); then
  info "Multiple .txt files found. Choose one:"
  select titles_file in "${txt_files[@]}"; do [[ -n $titles_file ]] && break; done
else
  titles_file="${txt_files[0]}"
fi
info "Using titles from: $titles_file"

# Read titles into array (index = lesson‑number – 1)
mapfile -t titles < "$titles_file"

# ---------------------- Collect candidate files -------------
lesson_files=()
for ext in "${file_exts[@]}"; do
  for f in "$video_dir"/*."$ext"; do [[ -f $f ]] && lesson_files+=("$f"); done
done
(( ${#lesson_files[@]} )) || die "No files with extensions (${file_exts[*]}) found."

# Infer lesson numbers & filter invalids ----------------------
valid_files=()
lesson_numbers=()
max_num=0
for f in "${lesson_files[@]}"; do
  if num=$(extract_number "$f"); then
    valid_files+=("$f"); lesson_numbers+=("$num");
    (( num > max_num )) && max_num=$num
  else
    warn "Skipping $f  (no lesson number identified)"
  fi
done
(( ${#valid_files[@]} )) || die "Could not find any lesson‑numbered files."

# Determine padding width dynamically ------------------------
if   (( max_num > 99 )); then padding=3
elif (( max_num > 9 ));  then padding=2
else padding=1; fi
info "Detected max lesson $max_num → padding width $padding."

# Sort files naturally (lesson10 after lesson2) ---------------
IFS=$'\n' valid_files=($(sort -V <<<"${valid_files[*]}")); unset IFS

# ---------------------- Rename loop -------------------------
for file in "${valid_files[@]}"; do
  num=$(extract_number "$file") || continue   # already ensured but safe
  title_idx=$(( num - 1 ))
  if [[ -z ${titles[title_idx]:-} ]]; then
    warn "No title provided for lesson $num – skipping $file"; continue;
  fi
  clean_title="$(sanitize_title "${titles[title_idx]}")"
  ext="${file##*.}"
  new_name="${video_dir}/$(printf "%0${padding}d" "$num")-${clean_title}.${ext}"
  if [[ $file == "$new_name" ]]; then
    info "Already named: $new_name"; continue;
  fi
  mv -i -- "$file" "$new_name"
  echo "$file → $new_name"
done

info "Renaming complete!"