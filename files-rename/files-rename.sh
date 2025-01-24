#!/bin/bash

# Enable debugging
# set -x

# Directory containing the video files
video_dir="./"

# Supported video file extensions
video_extensions=("mp4" "webm")

# Find all .txt files in the current directory
txt_files=(*.txt)

# Check if there are any .txt files
if [ ${#txt_files[@]} -eq 0 ]; then
  echo "No .txt files found in the current directory."
  exit 1
fi

# If there is more than one .txt file, ask the user to select one
if [ ${#txt_files[@]} -gt 1 ]; then
  echo "Multiple .txt files found. Please select one:"
  for i in "${!txt_files[@]}"; do
    echo "$((i+1)). ${txt_files[$i]}"
  done
  read -p "Enter the number of the file you want to use: " selection
  if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#txt_files[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
  fi
  titles_file="${txt_files[$((selection-1))]}"
else
  titles_file="${txt_files[0]}"
fi

# Confirm the selected file
echo "You have selected: $titles_file"
read -p "Is this correct? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborting."
  exit 1
fi

# Get the list of video files in the directory (with numeric suffix)
video_files=()
for ext in "${video_extensions[@]}"; do
  # Use a loop to match files with numeric suffix (e.g., lesson1.mp4, lesson2.webm)
  for file in "$video_dir"/lesson[0-9]*."$ext"; do
    if [ -f "$file" ]; then
      video_files+=("$file")
    fi
  done
done

  # Sort files in natural order (numerical order)
  video_files=($(printf '%s\n' "${video_files[@]}" | sort -V))



# Debug: Print the list of video files
echo "Found video files:"
printf '%s\n' "${video_files[@]}"

# Count the number of video files
num_videos=${#video_files[@]}

# Check if any video files were found
if [ "$num_videos" -eq 0 ]; then
  echo "Error: No video files matching 'lesson[0-9]*.{${video_extensions[*]}}' found in '$video_dir'."
  exit 1
fi

# Read the titles from the text file into an array
titles=()
while IFS= read -r line || [[ -n "$line" ]]; do
  titles+=("$line")
done < "$titles_file"

# Count the number of titles
num_titles=${#titles[@]}

# Check if the number of videos matches the number of titles
if [ "$num_videos" -ne "$num_titles" ]; then
  echo "Error: Number of videos ($num_videos) does not match number of titles ($num_titles)."
  exit 1
fi

# Function to sanitize and format the title
sanitize_title() {
  local title="$1"
  
  # Remove invalid characters (keep only alphanumeric, spaces, and hyphens)
  title=$(echo "$title" | tr -cd '[:alnum:][:space:]-' | tr ' ' ' ')
  
  # Trim leading and trailing spaces
  title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  
  # Replace multiple spaces with a single space
  title=$(echo "$title" | tr -s ' ')
  
  # Capitalize the first letter of each word
  title=$(echo "$title" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')
  
  echo "$title"
}

# Determine the padding for the numbering
if [ "$num_videos" -gt 99 ]; then
  padding=3
elif [ "$num_videos" -gt 9 ]; then
  padding=2
else
  padding=1
fi

# Rename the video files
  for video_file in "${video_files[@]}"; do
   # Extract the number from the filename using regex
    if [[ "$video_file" =~ lesson([0-9]+)\. ]]; then
      lesson_number="${BASH_REMATCH[1]}"
    else
      echo "Error: Could not extract number from filename '$video_file'."
      continue
    fi

    # Get the corresponding title
    title="${titles[$((lesson_number-1))]}"

    # Sanitize and format the title
    clean_title=$(sanitize_title "$title")
    
    # Get the file extension
    extension="${video_file##*.}"
    
    # Generate the new filename
    new_number=$(printf "%02d" "$lesson_number")  # Pad with leading zeros if necessary
    new_filename="${video_dir}/${new_number}-${clean_title}.${extension}"

  # Rename the file
  mv "$video_file" "$new_filename"
  echo "Renamed: $video_file -> $new_filename"
done

echo "Renaming completed successfully."

