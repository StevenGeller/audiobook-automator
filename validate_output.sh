#!/bin/bash
#
# validate_output.sh - Validate m4b files created by the audiobook processor
# usage: ./validate_output.sh /path/to/processed/files
#

set -e  # Exit on error

# Output colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default path is processed directory in current location
PROCESSED_DIR="${1:-$(pwd)/test_audiobooks/processed}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate m4b file using mediainfo
validate_m4b() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo -e "\n${BLUE}Validating: $filename${NC}"
    
    # Check file exists and is readable
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo -e "${RED}Error: Cannot access file $file${NC}"
        return 1
    fi
    
    # Check file size (must be > 0)
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [ -z "$size" ] || [ "$size" -eq 0 ]; then
        echo -e "${RED}Error: File is empty or unreadable: $file${NC}"
        return 1
    fi
    
    echo "File size: $(numfmt --to=iec-i --suffix=B --format="%.2f" $size 2>/dev/null || echo "$(($size/1024/1024)) MB")"
    
    # Check file format using mediainfo if available
    if command_exists mediainfo; then
        # Get mediainfo output
        local info=$(mediainfo "$file")
        
        # Extract key info
        local format=$(echo "$info" | grep -i "Format" | head -n 1 | cut -d: -f2- | xargs)
        local duration=$(echo "$info" | grep -i "Duration" | head -n 1 | cut -d: -f2- | xargs)
        local title=$(echo "$info" | grep -i "^Title" | head -n 1 | cut -d: -f2- | xargs)
        local artist=$(echo "$info" | grep -i "Performer" | head -n 1 | cut -d: -f2- | xargs)
        local album=$(echo "$info" | grep -i "Album" | head -n 1 | cut -d: -f2- | xargs)
        
        # Display extracted info
        echo "Format: $format"
        echo "Duration: $duration"
        echo "Title: $title"
        echo "Artist/Author: $artist"
        echo "Album: $album"
        
        # Check for chapters
        local chapter_count=$(echo "$info" | grep -c "Chapter")
        if [ "$chapter_count" -gt 0 ]; then
            echo -e "${GREEN}Chapters: $chapter_count chapters found${NC}"
        else
            echo -e "${RED}Warning: No chapters found${NC}"
        fi
        
        # Check for cover art
        if echo "$info" | grep -q "Cover"; then
            echo -e "${GREEN}Cover art: Present${NC}"
        else
            echo -e "${RED}Warning: No cover art found${NC}"
        fi
        
        # Basic validation checks
        if [ -z "$format" ] || [ -z "$duration" ]; then
            echo -e "${RED}Error: File appears to be invalid or corrupt${NC}"
            return 1
        fi
        
        # Check if it's really an m4b file
        if ! echo "$format" | grep -iq "MPEG-4"; then
            echo -e "${RED}Error: File is not a valid MPEG-4 audio file${NC}"
            return 1
        fi
        
        echo -e "${GREEN}File validation successful${NC}"
        return 0
    else
        echo -e "${RED}Warning: mediainfo not installed, skipping detailed validation${NC}"
        # Basic validation - just check file extension
        if [[ "$file" != *.m4b ]]; then
            echo -e "${RED}Error: File does not have .m4b extension${NC}"
            return 1
        fi
        return 0
    fi
}

# Main function
main() {
    if [ ! -d "$PROCESSED_DIR" ]; then
        echo -e "${RED}Error: Directory not found: $PROCESSED_DIR${NC}"
        echo "Usage: $0 [/path/to/processed/files]"
        exit 1
    fi
    
    echo -e "${BLUE}Validating files in: $PROCESSED_DIR${NC}"
    
    # Check required tools
    if ! command_exists mediainfo; then
        echo -e "${RED}Warning: mediainfo not installed. Limited validation will be performed.${NC}"
        echo "To install mediainfo:"
        echo "  - macOS: brew install mediainfo"
        echo "  - Linux: apt-get install mediainfo / yum install mediainfo"
    fi
    
    # Find all m4b files
    local m4b_files=()
    while IFS= read -r -d '' file; do
        m4b_files+=("$file")
    done < <(find "$PROCESSED_DIR" -type f -name "*.m4b" -print0)
    
    # Check if any files were found
    if [ ${#m4b_files[@]} -eq 0 ]; then
        echo -e "${RED}No .m4b files found in $PROCESSED_DIR${NC}"
        exit 1
    fi
    
    echo "Found ${#m4b_files[@]} .m4b files to validate"
    
    # Initialize counters
    local valid_count=0
    local invalid_count=0
    
    # Validate each file
    for file in "${m4b_files[@]}"; do
        if validate_m4b "$file"; then
            valid_count=$((valid_count + 1))
        else
            invalid_count=$((invalid_count + 1))
        fi
    done
    
    # Print summary
    echo -e "\n${BLUE}Validation Summary:${NC}"
    echo "Total files checked: ${#m4b_files[@]}"
    echo -e "${GREEN}Valid files: $valid_count${NC}"
    if [ $invalid_count -gt 0 ]; then
        echo -e "${RED}Invalid files: $invalid_count${NC}"
        exit 1
    else
        echo -e "\n${GREEN}All files validated successfully!${NC}"
    fi
}

main "$@"