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
    
    # Search for common audio file extensions with debug info
    # First count files to see if we should find anything
    local count=0
    if [ "$recursive" -eq 0 ]; then
        count=$(find "$dir" -maxdepth 1 -type f -name "*.mp3" -o -name "*.m4a" -o -name "*.m4b" -o -name "*.aac" -o -name "*.ogg" -o -name "*.opus" -o -name "*.flac" -o -name "*.wav" -o -name "*.wma" 2>/dev/null | wc -l)
    else
        count=$(find "$dir" -type f -name "*.mp3" -o -name "*.m4a" -o -name "*.m4b" -o -name "*.aac" -o -name "*.ogg" -o -name "*.opus" -o -name "*.flac" -o -name "*.wav" -o -name "*.wma" 2>/dev/null | wc -l)
    fi
    
    echo "DEBUG: Found $count potential audio files in $dir" | tee -a "$LOG_FILE"
    
    # Now get the actual files, with special handling for directories with spaces
    if [ "$recursive" -eq 0 ]; then
        find "$dir" -maxdepth 1 -type f -name "*.mp3" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.m4a" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.m4b" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.aac" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.ogg" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.opus" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.flac" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.wav" 2>/dev/null
        find "$dir" -maxdepth 1 -type f -name "*.wma" 2>/dev/null
    else
        find "$dir" -type f -name "*.mp3" 2>/dev/null
        find "$dir" -type f -name "*.m4a" 2>/dev/null
        find "$dir" -type f -name "*.m4b" 2>/dev/null
        find "$dir" -type f -name "*.aac" 2>/dev/null
        find "$dir" -type f -name "*.ogg" 2>/dev/null
        find "$dir" -type f -name "*.opus" 2>/dev/null
        find "$dir" -type f -name "*.flac" 2>/dev/null
        find "$dir" -type f -name "*.wav" 2>/dev/null
        find "$dir" -type f -name "*.wma" 2>/dev/null
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
    local found_dirs=()
    
    # Log start of scanning
    echo "Starting directory scan in: $root_dir" >> "$LOG_FILE"
    
    # First check directories one level deep
    find "$root_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
        # Get basename for cleaner logging
        local dirname=$(basename "$dir")
        
        # Count audio files in this directory using separate find commands to handle spaces properly
        local file_count=0
        local audio_extensions=("mp3" "m4a" "m4b" "aac" "ogg" "opus" "flac" "wav" "wma")
        
        for ext in "${audio_extensions[@]}"; do
            local count=$(find "$dir" -maxdepth 1 -type f -name "*.$ext" 2>/dev/null | wc -l)
            count=$(echo "$count" | tr -d ' ')  # Trim whitespace
            file_count=$((file_count + count))
        done
        
        echo "DEBUG: Directory '$dirname' has $file_count audio files" | tee -a "$LOG_FILE"
        
        if [ "$file_count" -gt 0 ]; then
            # This directory has audio files
            found_dirs+=("$dir")
            echo "Found audiobook with audio files: $dirname" | tee -a "$LOG_FILE"
        else
            # Check for subdirectories with audio files
            local subdirs=0
            subdirs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            subdirs=$(echo "$subdirs" | tr -d ' ')  # Trim whitespace
            
            echo "Scanning folder: $dirname ($(printf "%8d" "$subdirs") subdirectories)" | tee -a "$LOG_FILE"
            
            # Look for existing processed files
            local processed_count=0
            for ext in "${audio_extensions[@]}"; do
                processed_count=$((processed_count + $(find "$dir" -type f -name "*.$ext" 2>/dev/null | wc -l | tr -d ' ')))
            done
            
            if [ "$processed_count" -gt 0 ]; then
                echo "Directory has $processed_count processed audio files" | tee -a "$LOG_FILE"
            fi
            
            # Check each subdirectory using find to handle spaces properly
            local sub_found=0
            find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r subdir; do
                # Check for audio files in this subdirectory
                local subfile_count=0
                
                for ext in "${audio_extensions[@]}"; do
                    local count=$(find "$subdir" -maxdepth 1 -type f -name "*.$ext" 2>/dev/null | wc -l)
                    count=$(echo "$count" | tr -d ' ')  # Trim whitespace
                    subfile_count=$((subfile_count + count))
                done
                
                echo "DEBUG: Subdirectory '$(basename "$subdir")' has $subfile_count audio files" | tee -a "$LOG_FILE"
                
                if [ "$subfile_count" -gt 0 ]; then
                    # Explicitly add the full path to found_dirs
                    found_dirs+=("$subdir")
                    echo "Found audiobook with audio files: $(basename "$subdir")" | tee -a "$LOG_FILE"
                    sub_found=1
                fi
            done
            
            # If no subdirectories with audio files, check if the directory itself should be included
            if [ "$sub_found" -eq 0 ]; then
                # Check for deeper audio files
                local deep_count=0
                for ext in "${audio_extensions[@]}"; do
                    deep_count=$((deep_count + $(find "$dir" -type f -name "*.$ext" 2>/dev/null | wc -l | tr -d ' ')))
                done
                
                echo "DEBUG: Deep scan of '$dirname' found $deep_count audio files" | tee -a "$LOG_FILE"
                
                if [ "$deep_count" -gt 0 ]; then
                    found_dirs+=("$dir")
                    echo "Found audiobook with nested audio files: $dirname" | tee -a "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Make sure we found something
    echo "DEBUG: Found ${#found_dirs[@]} directories with audio files" | tee -a "$LOG_FILE"
    
    # Return the array as a newline-separated list with proper escaping
    for dir in "${found_dirs[@]}"; do
        # Make sure the path is properly quoted
        printf "%s\n" "$dir"
    done
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