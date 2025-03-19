#!/bin/bash
# lib_file_ops.sh - File operations for audiobook processing

# Find audio files in a directory
# Arguments:
#   $1: Directory path to search
#   $2: Option to search recursively (0 or 1)
# Returns:
#   Array of audio file paths
find_audio_files() {
    local dir="$1"
    local recursive="${2:-0}"
    local depth_arg=""
    
    # Set depth for find command
    if [ "$recursive" -eq 0 ]; then
        depth_arg="-maxdepth 1"
    fi
    
    # Debug output
    echo "DEBUG: Searching for audio files in: $dir" | tee -a "$LOG_FILE"
    
    # Check if directory exists
    if [ ! -d "$dir" ]; then
        echo "ERROR: Directory does not exist or is not a directory: $dir" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # List all files in the directory for debugging
    echo "DEBUG: Directory listing of $dir:" | tee -a "$LOG_FILE"
    ls -la "$dir" | tee -a "$LOG_FILE"
    
    # Search for common audio file extensions with debug info
    local audio_extensions=("mp3" "m4a" "m4b" "aac" "ogg" "opus" "flac" "wav" "wma")
    
    # Print debug info for each extension
    for ext in "${audio_extensions[@]}"; do
        # Use ls first to see files with a particular extension for debugging
        echo "DEBUG: Looking for *.$ext files in $dir:" | tee -a "$LOG_FILE"
        ls -la "$dir"/*.$ext 2>/dev/null | tee -a "$LOG_FILE" || true
    done
    
    # Now get the actual files with find, one extension at a time to handle special characters better
    if [ "$recursive" -eq 0 ]; then
        # Non-recursive search
        for ext in "${audio_extensions[@]}"; do
            # Use the -iname flag for case-insensitive matching (important for finding "Elon Musk.mp3" vs "*.MP3")
            find "$dir" -maxdepth 1 -type f -iname "*.$ext" 2>/dev/null || true
        done
    else
        # Recursive search
        for ext in "${audio_extensions[@]}"; do
            find "$dir" -type f -iname "*.$ext" 2>/dev/null || true
        done
    fi
}

# Find directories containing audio files
# Arguments:
#   $1: Root directory to search
#   $2: Log file path
# Returns:
#   Array of directory paths
find_audiobook_directories() {
    local root_dir="$1"
    local LOG_FILE="$2"
    local temp_found_dirs_file=$(mktemp) # Use a temp file to collect directories
    
    # Log start of scanning
    echo "Starting directory scan in: $root_dir" | tee -a "$LOG_FILE"
    
    # List all files in the root directory for debugging
    echo "DEBUG: Contents of root directory ($root_dir):" | tee -a "$LOG_FILE"
    ls -la "$root_dir" | tee -a "$LOG_FILE"
    
    # First check directories one level deep
    find "$root_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
        # Get basename for cleaner logging
        local dirname=$(basename "$dir")
        
        # Count audio files in this directory using separate find commands with case insensitivity
        local file_count=0
        local audio_extensions=("mp3" "m4a" "m4b" "aac" "ogg" "opus" "flac" "wav" "wma")
        
        echo "DEBUG: Checking directory for audio files: $dir" | tee -a "$LOG_FILE"
        
        # List all files in this directory for debugging
        ls -la "$dir" | tee -a "$LOG_FILE" || true
        
        for ext in "${audio_extensions[@]}"; do
            # Use case-insensitive search and better error handling
            local count=$(find "$dir" -maxdepth 1 -type f -iname "*.$ext" 2>/dev/null | wc -l)
            count=$(echo "$count" | tr -d ' ')  # Trim whitespace
            file_count=$((file_count + count))
        done
        
        echo "DEBUG: Directory '$dirname' has $file_count audio files" | tee -a "$LOG_FILE"
        
        if [ "$file_count" -gt 0 ]; then
            # This directory has audio files
            echo "$dir" >> "$temp_found_dirs_file"
            echo "Found audiobook with audio files: $dirname" | tee -a "$LOG_FILE"
        else
            # Check for subdirectories with audio files
            local subdirs=0
            subdirs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            subdirs=$(echo "$subdirs" | tr -d ' ')  # Trim whitespace
            
            echo "Scanning folder: $dirname ($(printf "%8d" "$subdirs") subdirectories)" | tee -a "$LOG_FILE"
            
            # Check each subdirectory using find to handle spaces properly
            local sub_found=0
            find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r subdir; do
                # Check for audio files in this subdirectory with case insensitivity
                local subfile_count=0
                
                # List subdirectory contents for debugging
                echo "DEBUG: Checking subdirectory for audio files: $subdir" | tee -a "$LOG_FILE"
                ls -la "$subdir" | tee -a "$LOG_FILE" || true
                
                for ext in "${audio_extensions[@]}"; do
                    local count=$(find "$subdir" -maxdepth 1 -type f -iname "*.$ext" 2>/dev/null | wc -l)
                    count=$(echo "$count" | tr -d ' ')  # Trim whitespace
                    subfile_count=$((subfile_count + count))
                done
                
                echo "DEBUG: Subdirectory '$(basename "$subdir")' has $subfile_count audio files" | tee -a "$LOG_FILE"
                
                if [ "$subfile_count" -gt 0 ]; then
                    # Write to temp file instead of array
                    echo "$subdir" >> "$temp_found_dirs_file"
                    echo "Found audiobook with audio files: $(basename "$subdir")" | tee -a "$LOG_FILE"
                    sub_found=1
                fi
            done
            
            # If no subdirectories with audio files, do a deep scan
            if [ "$sub_found" -eq 0 ]; then
                # Look for any audio files with a recursive search (better for finding single files like "Elon Musk.mp3")
                local deep_count=0
                for ext in "${audio_extensions[@]}"; do
                    # Show a few specific files found (for debugging)
                    echo "DEBUG: Looking for *.$ext files in $dir (recursive):" | tee -a "$LOG_FILE"
                    find "$dir" -type f -iname "*.$ext" 2>/dev/null | head -n 3 | tee -a "$LOG_FILE" || true
                    
                    # Count all files
                    deep_count=$((deep_count + $(find "$dir" -type f -iname "*.$ext" 2>/dev/null | wc -l | tr -d ' ')))
                done
                
                echo "DEBUG: Deep scan of '$dirname' found $deep_count audio files" | tee -a "$LOG_FILE"
                
                if [ "$deep_count" -gt 0 ]; then
                    echo "$dir" >> "$temp_found_dirs_file"
                    echo "Found audiobook with nested audio files: $dirname" | tee -a "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Read the collected directories from the temp file
    cat "$temp_found_dirs_file" | sort | uniq
    
    # Clean up temp file
    rm -f "$temp_found_dirs_file"
}

# Safely delete original files after successful conversion
# Arguments:
#   $1: Array of original file paths
#   $2: Output M4B file path
#   $3: Log file path
#   $4: Whether to actually delete (1) or just verify (0)
# Returns:
#   0 on success, 1 if preconditions not met
clean_up_original_files() {
    local original_files_str="$1"
    local output_file="$2"
    local LOG_FILE="$3"
    local should_delete="${4:-0}"
    
    # Convert space-separated string to array
    local original_files=()
    
    # Use read to properly split the string
    IFS=' ' read -r -a original_files <<< "$original_files_str"
    
    # Log file count
    echo "Checking ${#original_files[@]} original files for cleanup" >> "$LOG_FILE"
    
    # Safety checks
    if [ ! -f "$output_file" ]; then
        echo "ERROR: Output file does not exist, keeping originals" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Get total size of originals
    local original_size=0
    for file in "${original_files[@]}"; do
        if [ -f "$file" ]; then
            local file_size
            file_size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)
            original_size=$((original_size + file_size))
        fi
    done
    
    # Get size of output
    local output_size
    output_size=$(stat -f %z "$output_file" 2>/dev/null || stat -c %s "$output_file" 2>/dev/null)
    
    # Basic size validation (output should be at least 50% of original size for compressed audio)
    if [ "$output_size" -lt "$((original_size / 2))" ]; then
        echo "WARNING: M4B file size ($output_size bytes) is too small compared to originals ($original_size bytes)" | tee -a "$LOG_FILE"
        echo "Keeping original files as a precaution" | tee -a "$LOG_FILE"
        return 1
    fi
    
    if [ "$should_delete" -eq 1 ]; then
        echo "Removing original files..." | tee -a "$LOG_FILE"
        for file in "${original_files[@]}"; do
            if [ -f "$file" ]; then
                rm "$file"
            fi
        done
    else
        echo "Found $(echo "${original_files[@]}" | wc -w) original audio files to clean up" | tee -a "$LOG_FILE"
    fi
    
    return 0
}