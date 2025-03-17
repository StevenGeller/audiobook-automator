#!/bin/bash
#
# audiobook-automator: Organize audiobook filenames
# usage: ./organize_filenames.sh /path/to/audiobook/directory
#
# This script helps organize audiobook files by:
# 1. Renaming files to remove special characters
# 2. Simplifying directory names
# 3. Creating a consistent naming structure
#

set -e  # exit on error

# Output formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to sanitize a filename
sanitize_filename() {
  local filename="$1"
  # Replace problematic characters with underscores
  echo "$filename" | sed -e 's/[^a-zA-Z0-9 ._-]/_/g' | sed -e 's/^ *//' -e 's/ *$//'
}

# Function to process a directory
process_directory() {
  local directory="$1"
  local dir_name=$(basename "$directory")
  
  echo -e "${BLUE}Processing directory: $dir_name${NC}"
  
  # Sanitize directory name
  local new_dir_name=$(sanitize_filename "$dir_name")
  if [ "$dir_name" != "$new_dir_name" ]; then
    local parent_dir=$(dirname "$directory")
    local new_path="$parent_dir/$new_dir_name"
    
    echo -e "Renaming directory:\n  From: $dir_name\n  To: $new_dir_name"
    
    # Check if the new directory already exists
    if [ -d "$new_path" ]; then
      echo -e "${RED}Error: Cannot rename directory - destination already exists: $new_path${NC}"
    else
      # Rename the directory
      mv "$directory" "$new_path"
      echo -e "${GREEN}Directory renamed successfully${NC}"
      # Update directory path for further processing
      directory="$new_path"
    fi
  fi
  
  # Process audio files in the directory
  echo "Processing audio files..."
  local file_count=0
  local renamed_count=0
  
  # Find audio files
  find "$directory" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" -o -name "*.wav" -o -name "*.aac" \) | while read file; do
    file_count=$((file_count + 1))
    local file_basename=$(basename "$file")
    local file_extension="${file_basename##*.}"
    local file_name="${file_basename%.*}"
    
    # Sanitize filename
    local new_file_name=$(sanitize_filename "$file_name")
    
    # If the file needs renaming
    if [ "$file_name" != "$new_file_name" ]; then
      renamed_count=$((renamed_count + 1))
      local new_file_path="$directory/${new_file_name}.${file_extension}"
      
      echo "  Renaming file: $file_basename -> ${new_file_name}.${file_extension}"
      mv "$file" "$new_file_path"
    fi
  done
  
  echo -e "${GREEN}Processed $file_count files, renamed $renamed_count files${NC}"
  
  # Process subdirectories
  find "$directory" -mindepth 1 -maxdepth 1 -type d | while read subdir; do
    process_directory "$subdir"
  done
}

# Main function
main() {
  if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/audiobook/directory"
    exit 1
  fi
  
  local target_dir="$1"
  
  if [ ! -d "$target_dir" ]; then
    echo -e "${RED}Error: Directory not found: $target_dir${NC}"
    exit 1
  fi
  
  echo -e "${BLUE}Starting audiobook filename organization in: $target_dir${NC}"
  process_directory "$target_dir"
  echo -e "${GREEN}All done! Audiobook files have been organized.${NC}"
}

main "$@"