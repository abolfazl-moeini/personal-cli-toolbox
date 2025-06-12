#!/bin/bash

# A robust script to download M3U8 streams using aria2c and ffmpeg.
# Updated to handle master playlists and support download resuming.

# --- Configuration ---
CONNECTIONS=16
# Optional: Set a user agent to mimic a browser
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36"

# --- Color Codes for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Function to check for required commands ---
check_deps() {
    for cmd in ffmpeg aria2c curl; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: Required command '$cmd' is not installed.${NC}"
            echo -e "${YELLOW}Please install it to continue.${NC}"
            exit 1
        fi
    done
}

# --- Function to download and stitch a single media playlist ---
download_stream() {
    local M3U8_URL="$1"
    local OUTPUT_FILE="$2"
    local TEMP_DIR="$3"
    local BASE_URL=$(dirname "$M3U8_URL")

    echo -e "${BLUE}Downloading stream:${NC} $M3U8_URL"
    echo -e "${BLUE}Temporary files will be stored in:${NC} $TEMP_DIR"


    # 1. Fetch playlist, filter for segment files, and create a list of full URLs
    echo -e "\n${YELLOW}Step 1: Fetching playlist and parsing segments...${NC}"
    # MODIFIED: Added 'NF > 0' to awk to prevent processing of empty lines
    curl -H "User-Agent: $USER_AGENT" -s "$M3U8_URL" | grep -v "^#" | awk -v base="$BASE_URL" 'NF > 0 {if ($0 ~ /^http/) {print} else {print base"/"$0}}' > "$TEMP_DIR/urllist.txt"

    if [ ! -s "$TEMP_DIR/urllist.txt" ]; then
        echo -e "${RED}Error: Could not extract any segment URLs from the media playlist.${NC}"
        return 1
    fi
    
    local SEGMENT_COUNT=$(wc -l < "$TEMP_DIR/urllist.txt")
    echo -e "${GREEN}Found $SEGMENT_COUNT segments to download.${NC}"

    # 2. Download all segments in parallel using aria2c
    echo -e "\n${YELLOW}Step 2: Downloading all segments with aria2c...${NC}"
    # MODIFIED: Added -c flag for resuming downloads
    aria2c -c --console-log-level=warn --user-agent="$USER_AGENT" -x"$CONNECTIONS" -d"$TEMP_DIR" -i"$TEMP_DIR/urllist.txt"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: aria2c failed to download segments.${NC}"
        echo -e "${YELLOW}You can try running the script again to resume.${NC}"
        return 1
    fi

    # 3. Create a file list for FFmpeg's concat demuxer
    # Use find and sort -V for robust ordering of segments (e.g., seg1, seg2, seg10)
    # Recreate the concat list every time to ensure it's fresh
    rm -f "$TEMP_DIR/concat_list.txt"
    find "$TEMP_DIR" -maxdepth 1 -name '*.ts' -o -name '*.aac' -o -name '*.mp4' | sort -V | while read -r line; do
        echo "file '$line'" >> "$TEMP_DIR/concat_list.txt"
    done

    # 4. Stitch files together with FFmpeg
    echo -e "\n${YELLOW}Step 3: Stitching segments with FFmpeg...${NC}"
    ffmpeg -f concat -safe 0 -i "$TEMP_DIR/concat_list.txt" -c copy -bsf:a aac_adtstoasc "$OUTPUT_FILE" -y -hide_banner -loglevel error

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Success! File saved as: $OUTPUT_FILE${NC}"
        echo -e "${YELLOW}Cleanup: You can now manually delete the temporary directory:${NC} $TEMP_DIR"
        # Optional: Uncomment the line below to automatically clean up on success
        # rm -rf "$TEMP_DIR"
    else
        echo -e "\n${RED}Error: FFmpeg failed to stitch the files.${NC}"
        echo -e "${YELLOW}Temporary files were kept in $TEMP_DIR for debugging.${NC}"
        return 1
    fi
}

# --- Main Script Logic ---
main() {
    if [ "$#" -ne 2 ]; then
        echo -e "${RED}Usage: $0 \"<M3U8_URL>\" \"<OUTPUT_FILENAME>\"${NC}"
        exit 1
    fi

    local INITIAL_URL="$1"
    local OUTPUT_FILE="$2"
    local BASE_URL=$(dirname "$INITIAL_URL")

    echo -e "${BLUE}Analyzing URL:${NC} $INITIAL_URL"

    # MODIFIED: Create a temporary directory in the current path based on the output filename
    # This allows for resuming downloads as the directory is not in /tmp and is not cleaned up automatically.
    local OUTPUT_BASENAME
    OUTPUT_BASENAME=$(basename "$OUTPUT_FILE")
    local TEMP_DIR="./.${OUTPUT_BASENAME}.tmp"
    mkdir -p "$TEMP_DIR"

    # MODIFIED: The automatic cleanup trap is disabled to allow resuming.
    # The user will be prompted to delete the folder manually upon success.
    # trap 'echo -e "${YELLOW}Cleaning up temporary files...${NC}"; rm -rf "$TEMP_DIR"' EXIT

    # Fetch the initial playlist content
    local MASTER_PLAYLIST_CONTENT
    MASTER_PLAYLIST_CONTENT=$(curl -H "User-Agent: $USER_AGENT" -s "$INITIAL_URL")

    # Check if it's a master playlist
    if echo "$MASTER_PLAYLIST_CONTENT" | grep -q "#EXT-X-STREAM-INF"; then
        echo -e "${GREEN}Master playlist detected. Parsing available streams...${NC}"
        
        local parsed_streams
        parsed_streams=$(echo "$MASTER_PLAYLIST_CONTENT" | awk '
            /^#EXT-X-STREAM-INF/ {
                info = $0; 
                getline; 
                print info "@@@" $0
            }')

        local streams=()
        local urls=()
        while IFS= read -r line; do
            info_part=$(echo "$line" | cut -d'@' -f1)
            url_part=$(echo "$line" | cut -d'@' -f4)

            resolution=$(echo "$info_part" | grep -o 'RESOLUTION=[^,]*' | cut -d= -f2 | sed 's/\"//g')
            bandwidth=$(echo "$info_part" | grep -o 'BANDWIDTH=[^,]*' | cut -d= -f2)
            bw_kbps=$((bandwidth / 1000))

            streams+=("Resolution: ${resolution:-N/A}, Bandwidth: ${bw_kbps}kbps")
            urls+=("$url_part")
        done <<< "$parsed_streams"

        if [ ${#streams[@]} -eq 0 ]; then
            echo -e "${RED}Error: Could not parse any streams from the master playlist.${NC}"
            exit 1
        fi

        echo -e "\nPlease choose a quality to download:"
        for i in "${!streams[@]}"; do
            echo -e "  ${GREEN}$((i+1))) ${NC}${streams[$i]}"
        done

        local choice
        read -p "Enter number (1-${#streams[@]}): " choice

        # Validate input
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#streams[@]} ]; then
            echo -e "${RED}Invalid selection.${NC}"
            exit 1
        fi

        local selected_playlist_path=${urls[$((choice-1))]}
        local CHOSEN_URL
        if [[ "$selected_playlist_path" == http* ]]; then
            CHOSEN_URL="$selected_playlist_path"
        else
            CHOSEN_URL="$BASE_URL/$selected_playlist_path"
        fi
        
        download_stream "$CHOSEN_URL" "$OUTPUT_FILE" "$TEMP_DIR"

    else
        echo -e "${GREEN}Media playlist detected. Proceeding directly with download...${NC}"
        download_stream "$INITIAL_URL" "$OUTPUT_FILE" "$TEMP_DIR"
    fi
}

# --- Start Execution ---
check_deps
main "$@"