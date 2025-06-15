#!/bin/bash

# A robust script to download M3U8 streams using aria2c and ffmpeg.
# Updated to handle master playlists, support download resuming, and send a Referer header.

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
## MODIFIED: Added HTTP_REFERER as an argument
download_stream() {
    local M3U8_URL="$1"
    local OUTPUT_FILE="$2"
    local TEMP_DIR="$3"
    local HTTP_REFERER="$4" ## ADDED
    local BASE_URL=$(dirname "$M3U8_URL")

    echo -e "${BLUE}Downloading stream:${NC} $M3U8_URL"
    if [ -n "$HTTP_REFERER" ]; then
        echo -e "${BLUE}Using Referer:${NC} $HTTP_REFERER"
    fi
    echo -e "${BLUE}Temporary files will be stored in:${NC} $TEMP_DIR"

    ## ADDED: Build curl options array for robustness
    local curl_opts=("-H" "User-Agent: $USER_AGENT" "-s")
    if [ -n "$HTTP_REFERER" ]; then
        curl_opts+=("-H" "Referer: $HTTP_REFERER")
    fi

    # 1. Fetch playlist, filter for segment files, and create a list of full URLs
    echo -e "\n${YELLOW}Step 1: Fetching playlist and parsing segments...${NC}"
    # MODIFIED: Use curl_opts array
    curl "${curl_opts[@]}" "$M3U8_URL" | grep -v "^#" | awk -v base="$BASE_URL" 'NF > 0 {if ($0 ~ /^http/) {print} else {print base"/"$0}}' > "$TEMP_DIR/urllist.txt"

    if [ ! -s "$TEMP_DIR/urllist.txt" ]; then
        echo -e "${RED}Error: Could not extract any segment URLs from the media playlist.${NC}"
        echo -e "${YELLOW}This could be due to a 403 Forbidden error. Try using the --referer option.${NC}"
        return 1
    fi
    
    local SEGMENT_COUNT=$(wc -l < "$TEMP_DIR/urllist.txt")
    echo -e "${GREEN}Found $SEGMENT_COUNT segments to download.${NC}"

    ## ADDED: Build aria2c options array for robustness
    local aria_opts=("-c" "--console-log-level=warn" "--user-agent=$USER_AGENT" "-x$CONNECTIONS" "-d$TEMP_DIR" "-i$TEMP_DIR/urllist.txt")
    if [ -n "$HTTP_REFERER" ]; then
        aria_opts+=("--header=Referer: $HTTP_REFERER")
    fi

    # 2. Download all segments in parallel using aria2c
    echo -e "\n${YELLOW}Step 2: Downloading all segments with aria2c...${NC}"
    # MODIFIED: Use aria_opts array
    aria2c "${aria_opts[@]}"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: aria2c failed to download segments.${NC}"
        echo -e "${YELLOW}You can try running the script again to resume.${NC}"
        return 1
    fi

    # 3. Create a file list for FFmpeg's concat demuxer
    rm -f "$TEMP_DIR/concat_list.txt"
    find "$TEMP_DIR" -maxdepth 1 -name '*.ts' -o -name '*.aac' -o -name '*.mp4' | sort -V | while read -r line; do
        filename=$(basename "$line")
        echo "file '$filename'" >> "$TEMP_DIR/concat_list.txt"
    done

    # 4. Stitch files together with FFmpeg
    echo -e "\n${YELLOW}Step 3: Stitching segments with FFmpeg...${NC}"
    ffmpeg -f concat -safe 0 -i "$TEMP_DIR/concat_list.txt" -c copy -bsf:a aac_adtstoasc "$OUTPUT_FILE" -y -hide_banner -loglevel error

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Success! File saved as: $OUTPUT_FILE${NC}"
        echo -e "${YELLOW}Cleanup: You can now manually delete the temporary directory:${NC} $TEMP_DIR"
    else
        echo -e "\n${RED}Error: FFmpeg failed to stitch the files.${NC}"
        echo -e "${YELLOW}Temporary files were kept in $TEMP_DIR for debugging.${NC}"
        return 1
    fi
}

# --- Function to print usage ---
## ADDED: Usage function for clarity
usage() {
    echo -e "${YELLOW}A robust script to download M3U8 streams.${NC}"
    echo -e "\n${GREEN}Usage:${NC} $0 [options] \"<M3U8_URL>\" \"<OUTPUT_FILENAME>\""
    echo -e "\n${GREEN}Options:${NC}"
    echo -e "  -r, --referer <URL>    Specify a custom HTTP Referer header."
    echo -e "  -h, --help               Display this help message."
    exit 1
}

# --- Main Script Logic ---
main() {
    ## ADDED: Robust argument parsing
    local INITIAL_URL=""
    local OUTPUT_FILE=""
    local HTTP_REFERER=""

    # Parse command-line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--referer)
                HTTP_REFERER="$2"
                shift # past argument
                shift # past value
                ;;
            -h|--help)
                usage
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
            *)
                if [ -z "$INITIAL_URL" ]; then
                    INITIAL_URL="$1"
                elif [ -z "$OUTPUT_FILE" ]; then
                    OUTPUT_FILE="$1"
                fi
                shift # past argument
                ;;
        esac
    done

    if [ -z "$INITIAL_URL" ] || [ -z "$OUTPUT_FILE" ]; then
        usage
    fi

    local BASE_URL=$(dirname "$INITIAL_URL")

    echo -e "${BLUE}Analyzing URL:${NC} $INITIAL_URL"

    local OUTPUT_BASENAME
    OUTPUT_BASENAME=$(basename "$OUTPUT_FILE")
    local TEMP_DIR="./.${OUTPUT_BASENAME}.tmp"
    mkdir -p "$TEMP_DIR"

    ## ADDED: Build curl options array for robustness
    local curl_opts=("-H" "User-Agent: $USER_AGENT" "-s")
    if [ -n "$HTTP_REFERER" ]; then
        curl_opts+=("-H" "Referer: $HTTP_REFERER")
    fi

    local MASTER_PLAYLIST_CONTENT
    ## MODIFIED: Use curl_opts array
    MASTER_PLAYLIST_CONTENT=$(curl "${curl_opts[@]}" "$INITIAL_URL")

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
        
        ## MODIFIED: Pass HTTP_REFERER to the function
        download_stream "$CHOSEN_URL" "$OUTPUT_FILE" "$TEMP_DIR" "$HTTP_REFERER"

    else
        echo -e "${GREEN}Media playlist detected. Proceeding directly with download...${NC}"
        ## MODIFIED: Pass HTTP_REFERER to the function
        download_stream "$INITIAL_URL" "$OUTPUT_FILE" "$TEMP_DIR" "$HTTP_REFERER"
    fi
}

# --- Start Execution ---
check_deps
main "$@"