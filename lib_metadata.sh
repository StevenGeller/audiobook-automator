#!/bin/bash
# lib_metadata.sh - Metadata extraction and handling for audiobooks

# Extract metadata from audio files
# Arguments:
#   $1: Audio file path
#   $2: Log file path
extract_metadata() {
    local audio_file="$1"
    local LOG_FILE="$2"
    
    # Use ffprobe to get metadata
    local author=""
    local title=""
    local album=""
    
    # Extract metadata with ffprobe
    if command -v ffprobe &>/dev/null; then
        # Try to get author from various tag fields
        author=$(ffprobe -v quiet -show_entries format_tags=artist,album_artist,composer,performer -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null | grep -v "^\s*$" | head -n 1)
        
        # Try to get title from title or album tags
        title=$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null | grep -v "^\s*$" | head -n 1)
        album=$(ffprobe -v quiet -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null | grep -v "^\s*$" | head -n 1)
        
        # If title is empty, try album as a fallback
        if [ -z "$title" ]; then
            title="$album"
        fi
        
        # Log the extracted metadata
        if [ -n "$author" ]; then
            echo "- Extracted author from audio (performer): $author" | tee -a "$LOG_FILE"
        else
            echo "- No author found in audio metadata" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "$title" ]; then
            echo "- Extracted title from audio (album): $title" | tee -a "$LOG_FILE"
        else
            echo "- No title found in audio metadata" | tee -a "$LOG_FILE"
        fi
    else
        echo "Warning: ffprobe not found, cannot extract metadata" | tee -a "$LOG_FILE"
    fi
    
    # Format the metadata for return, being careful with special characters
    # Strip any problematic characters from the values
    author=$(echo "$author" | tr -d '\n\r')
    title=$(echo "$title" | tr -d '\n\r')
    
    # Print metadata in a way the caller can safely parse
    # Don't output any log messages mixed with this return value!
    printf "METADATA_START\n%s\n%s\nMETADATA_END\n" "$author" "$title"
}

# Find cover art for an audiobook
# Arguments:
#   $1: Directory path
#   $2: Log file path
# Returns:
#   Path to cover image or empty if not found
find_cover_art() {
    local dir="$1"
    local LOG_FILE="$2"
    
    # Check for common cover art filenames
    local cover_file=""
    
    # Try multiple image formats
    for name in cover folder album artwork art front; do
        for ext in jpg jpeg png gif webp bmp; do
            # Check for files like cover.jpg, folder.png, etc.
            if [ -f "$dir/$name.$ext" ]; then
                cover_file="$dir/$name.$ext"
                break 2
            fi
            
            # Check for files like Cover.jpg, FOLDER.PNG, etc. (case insensitive)
            local found_file=$(find "$dir" -maxdepth 1 -type f -iname "$name.$ext" 2>/dev/null | head -n 1)
            if [ -n "$found_file" ]; then
                cover_file="$found_file"
                break 2
            fi
        done
    done
    
    # If not found by name, check for dedicated cover_art directory
    if [ -z "$cover_file" ] && [ -d "$dir/cover_art" ]; then
        # Look for any image in the cover_art directory
        local found_file=$(find "$dir/cover_art" -maxdepth 1 -type f -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" 2>/dev/null | head -n 1)
        if [ -n "$found_file" ]; then
            cover_file="$found_file"
        fi
    fi
    
    # If still not found, look for any image in the main directory
    if [ -z "$cover_file" ]; then
        local found_file=$(find "$dir" -maxdepth 1 -type f -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" 2>/dev/null | head -n 1)
        if [ -n "$found_file" ]; then
            cover_file="$found_file"
        fi
    fi
    
    echo "$cover_file"
}

# Extract author and title from directory name
# Arguments:
#   $1: Directory name
#   $2: Log file path
# Returns:
#   Associative array with extracted author and title
extract_from_directory_name() {
    local dirname="$1"
    local LOG_FILE="$2"
    local author=""
    local title=""
    
    # Common patterns: "Author - Title", "Author Name - Book Title", etc.
    if [[ "$dirname" =~ (.+)[-_](.+) ]]; then
        author="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[2]}"
        
        # Clean up spaces
        author="$(echo "$author" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        title="$(echo "$title" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        
        echo "- Extracted from directory name: author='$author', title='$title'" >> "$LOG_FILE"
    else
        # If no separator is found, use the whole name as the title
        title="$dirname"
        echo "- No author-title separator found in directory name, using as title: '$title'" >> "$LOG_FILE"
    fi
    
    # Clean values of problematic characters
    author=$(echo "$author" | tr -d '\n\r')
    title=$(echo "$title" | tr -d '\n\r')
    
    # Print metadata in a way the caller can safely parse
    printf "METADATA_START\n%s\n%s\nMETADATA_END\n" "$author" "$title"
}

# Try to parse the embedded year and bitrate from filename
# Arguments:
#   $1: Filename
# Returns:
#   Year and bitrate if found
parse_year_and_bitrate() {
    local filename="$1"
    local year=""
    local bitrate=""
    
    # Look for year in format like 2015, 2015_, (2015), etc.
    if [[ "$filename" =~ [^0-9]*(19|20)[0-9]{2}[^0-9]* ]]; then
        year="${BASH_REMATCH[0]}"
        year=$(echo "$year" | grep -o '[0-9]\{4\}')
    fi
    
    # Look for bitrate pattern like 64k, 128k, etc.
    if [[ "$filename" =~ [^0-9]*([0-9]{2,3})k[^0-9]* ]]; then
        bitrate="${BASH_REMATCH[1]}k"
    fi
    
    printf "METADATA_START\n%s\n%s\nMETADATA_END\n" "$year" "$bitrate"
}

# Normalize author and title for filename
# Arguments:
#   $1: String to normalize
# Returns:
#   Normalized string
normalize_for_filename() {
    local input="$1"
    local output
    
    # Replace problematic characters
    output=$(echo "$input" | tr -d ':"*?<>|' | tr '/' '-')
    
    # Normalize spaces
    output=$(echo "$output" | sed 's/\s\+/ /g' | sed 's/^\s\+//;s/\s\+$//')
    
    echo "$output"
}