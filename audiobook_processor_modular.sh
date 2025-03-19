#!/bin/bash
# audiobook_processor_modular.sh - Process audiobooks into m4b format
# Modular rewrite of the original script to improve maintainability

# Import library modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ffmpeg.sh"
source "$SCRIPT_DIR/lib_progress.sh"
source "$SCRIPT_DIR/lib_metadata.sh" 
source "$SCRIPT_DIR/lib_file_ops.sh"

# Configuration
VERSION="1.2.0"
DEFAULT_OUTPUT_DIR="processed"
REMOVE_ORIGINAL=0
RECURSIVE_SEARCH=0
SKIP_EXISTING=1
PROCESSED_DIRS=()

# Create a log file
LOG_FILE="$(pwd)/processing_log.txt"
echo "=== Audiobook Processor v$VERSION - $(date) ===" >> "$LOG_FILE"

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS] DIRECTORY"
    echo "Process audiobooks in DIRECTORY and convert to m4b format"
    echo ""
    echo "Options:"
    echo "  -o, --output DIR      Set output directory (default: processed/)"
    echo "  -r, --remove          Remove original files after successful conversion"
    echo "  -s, --search          Search all nested directories for audio files"
    echo "  -f, --force           Force processing even if output file exists"
    echo "  -h, --help            Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --remove ~/Audiobooks"
}

# Process command line arguments
process_args() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -o|--output)
                DEFAULT_OUTPUT_DIR="$2"
                shift 2
                ;;
            -r|--remove)
                REMOVE_ORIGINAL=1
                shift
                ;;
            -s|--search)
                RECURSIVE_SEARCH=1
                shift
                ;;
            -f|--force)
                SKIP_EXISTING=0
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                INPUT_DIR="$1"
                shift
                ;;
        esac
    done
    
    # Validate input directory
    if [ -z "$INPUT_DIR" ]; then
        echo "ERROR: No input directory specified"
        print_usage
        exit 1
    fi
    
    if [ ! -d "$INPUT_DIR" ]; then
        echo "ERROR: Input directory does not exist: $INPUT_DIR"
        exit 1
    fi
    
    # Ensure output directory exists
    if [ ! -d "$DEFAULT_OUTPUT_DIR" ]; then
        mkdir -p "$DEFAULT_OUTPUT_DIR"
    fi
    
    # Log settings
    echo "Starting recursive audiobook processing in $INPUT_DIR" | tee -a "$LOG_FILE"
    if [ "$REMOVE_ORIGINAL" -eq 1 ]; then
        echo "Original files will be removed after successful m4b conversion" | tee -a "$LOG_FILE"
    fi
    if [ "$RECURSIVE_SEARCH" -eq 1 ]; then
        echo "Will search all nested directories for audio files automatically" | tee -a "$LOG_FILE"
    fi
}

# Process a single audiobook directory
process_audiobook() {
    local book_dir="$1"
    local book_idx="$2"
    local output_dir="$DEFAULT_OUTPUT_DIR"
    
    echo "" | tee -a "$LOG_FILE"
    echo "=====================================" | tee -a "$LOG_FILE"
    echo "Processing: $(basename "$book_dir")" | tee -a "$LOG_FILE"
    
    # Check if directory exists and is accessible
    if [ ! -d "$book_dir" ]; then
        echo "ERROR: Directory does not exist or is not accessible: $book_dir" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Skip if already processed
    for dir in "${PROCESSED_DIRS[@]}"; do
        if [ "$dir" = "$book_dir" ]; then
            echo "Skipping already processed book: $(basename "$book_dir")" | tee -a "$LOG_FILE"
            return 0
        fi
    done
    
    # Add to processed directories
    PROCESSED_DIRS+=("$book_dir")
    
    # List directory contents for debugging
    echo "Directory contents:" | tee -a "$LOG_FILE"
    ls -la "$book_dir" | head -n 10 | tee -a "$LOG_FILE"
    
    # Find audio files using direct method for better handling of special characters
    local audio_files=()
    local audio_exts=("mp3" "m4a" "m4b" "aac" "ogg" "opus" "flac" "wav" "wma")
    
    for ext in "${audio_exts[@]}"; do
        while IFS= read -r line; do
            if [ -n "$line" ] && [ -f "$line" ]; then
                audio_files+=("$line")
                echo "Found audio file: $(basename "$line")" | tee -a "$LOG_FILE"
            fi
        done < <(find "$book_dir" $([[ "$RECURSIVE_SEARCH" -eq 1 ]] || echo "-maxdepth 1") -type f -name "*.$ext" 2>/dev/null)
    done
    
    local file_count="${#audio_files[@]}"
    
    if [ "$file_count" -eq 0 ]; then
        echo "No audio files found in $book_dir" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "Found $file_count audio files" | tee -a "$LOG_FILE"
    
    # Extract metadata from first audio file
    local author=""
    local title=""
    
    # Get metadata from the first audio file
    local metadata_raw
    metadata_raw=$(extract_metadata "${audio_files[0]}" "$LOG_FILE")
    
    # Parse the metadata using grep instead of eval
    if echo "$metadata_raw" | grep -q "METADATA_START"; then
        author=$(echo "$metadata_raw" | grep -A 1 "METADATA_START" | tail -n 1)
        title=$(echo "$metadata_raw" | grep -A 2 "METADATA_START" | tail -n 1)
    fi
    
    # If metadata is missing, try to extract from directory name
    if [ -z "$author" ] || [ -z "$title" ]; then
        local dir_metadata
        dir_metadata=$(extract_from_directory_name "$(basename "$book_dir")" "$LOG_FILE")
        
        # Parse the directory metadata
        if echo "$dir_metadata" | grep -q "METADATA_START"; then
            local dir_author=$(echo "$dir_metadata" | grep -A 1 "METADATA_START" | tail -n 1)
            local dir_title=$(echo "$dir_metadata" | grep -A 2 "METADATA_START" | tail -n 1)
            
            # Update variables if we got new values
            if [ -n "$dir_author" ]; then
                author="$dir_author"
            fi
            if [ -n "$dir_title" ]; then
                title="$dir_title"
            fi
        fi
        
        # Use directory name as fallback if still empty
        if [ -z "$title" ]; then
            title="$(basename "$book_dir")"
        fi
    fi
    
    # Normalize author and title for filename
    author=$(normalize_for_filename "$author")
    title=$(normalize_for_filename "$title")
    
    # Show what we've determined
    echo "Using author: $author" | tee -a "$LOG_FILE"
    echo "Using title: $title" | tee -a "$LOG_FILE"
    
    # Find cover art
    local cover_image
    cover_image=$(find_cover_art "$book_dir" "$LOG_FILE")
    
    # Ensure the output directory exists
    mkdir -p "$output_dir"
    
    # Determine output filename - FLAT STRUCTURE as requested
    local output_file
    
    # If author exists, use Author - Title format
    if [ -n "$author" ]; then
        output_file="$output_dir/$author - $title.m4b"
    else
        output_file="$output_dir/$title.m4b"
    fi
    
    echo "Will create output file: $output_file" | tee -a "$LOG_FILE"
    
    # Check if the output file already exists
    if [ -f "$output_file" ] && [ "$SKIP_EXISTING" -eq 1 ]; then
        echo "Output file already exists: $output_file" | tee -a "$LOG_FILE"
        echo "Skipping conversion (use --force to override)" | tee -a "$LOG_FILE"
        return 0
    fi
    
    # Create temp directory for progress tracking
    local temp_dir="/tmp/audiobook_temp_$(date +%s)"
    mkdir -p "$temp_dir"
    local progress_file="$temp_dir/progress"
    
    # Start the progress indicator
    local progress_pid
    progress_pid=$(start_progress_indicator "$progress_file" "Processing..." "$file_count")
    
    # Process audio files
    for ((i=0; i<file_count; i++)); do
        # Update progress
        update_progress "$progress_file" "$((i+1))"
    done
    
    # Signal that we're starting conversion
    signal_conversion_start "$progress_file"
    
    # Convert to m4b - pass each audio file as a separate argument
    if [ ${#audio_files[@]} -gt 0 ]; then
        convert_to_m4b "$output_file" "$LOG_FILE" "$progress_file" "$author" "$title" "$cover_image" "${audio_files[@]}"
        local result=$?
    else
        echo "ERROR: No audio files to process" | tee -a "$LOG_FILE"
        local result=1
    fi
    
    # Stop progress indicator
    stop_progress_indicator "$progress_file" "$progress_pid"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    if [ $result -eq 0 ]; then
        # Print file info
        echo "Created: $output_file" | tee -a "$LOG_FILE"
        echo "File info:" | tee -a "$LOG_FILE"
        ffprobe -v quiet -show_format -show_streams "$output_file" | grep -E "(album|artist|title|performer|duration)" | tee -a "$LOG_FILE"
        
        # Prepare file list for cleanup
        local files_list=$(printf "%s " "${audio_files[@]}")
        
        # Clean up original files if requested
        if [ "$REMOVE_ORIGINAL" -eq 1 ]; then
            clean_up_original_files "$files_list" "$output_file" "$LOG_FILE" 1
        else
            clean_up_original_files "$files_list" "$output_file" "$LOG_FILE" 0
        fi
        
        echo "Processing completed for: $(basename "$book_dir")" | tee -a "$LOG_FILE"
        echo "-------------------------------------------" | tee -a "$LOG_FILE"
        return 0
    else
        echo "Processing failed for: $(basename "$book_dir")" | tee -a "$LOG_FILE"
        echo "-------------------------------------------" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Main function
main() {
    # Process command line arguments
    process_args "$@"
    
    echo "==================== AUDIOBOOK PROCESSOR ====================" | tee -a "$LOG_FILE"
    echo "Starting scan of: $INPUT_DIR" | tee -a "$LOG_FILE"
    echo "Output directory: $DEFAULT_OUTPUT_DIR" | tee -a "$LOG_FILE"
    echo "=============================================================" | tee -a "$LOG_FILE"
    
    # Create output directory if it doesn't exist
    mkdir -p "$DEFAULT_OUTPUT_DIR"
    
    # Find audiobook directories
    echo "Scanning for audiobooks... (this may take a moment)" | tee -a "$LOG_FILE"
    
    # Save the result of the directory scan to a temporary file
    local temp_dir_file=$(mktemp)
    find_audiobook_directories "$INPUT_DIR" "$LOG_FILE" > "$temp_dir_file"
    
    # Read from the file to avoid issues with subshell variables
    local book_dirs=()
    while IFS= read -r line; do
        if [ -n "$line" ] && [ -d "$line" ]; then
            book_dirs+=("$line")
            echo "DEBUG: Added directory to processing list: $line" | tee -a "$LOG_FILE"
        else
            echo "WARNING: Invalid directory entry: $line" | tee -a "$LOG_FILE"
        fi
    done < "$temp_dir_file"
    
    # Clean up temp file
    rm -f "$temp_dir_file"
    
    local dir_count="${#book_dirs[@]}"
    
    echo "=============================================================" | tee -a "$LOG_FILE"
    echo "Found $dir_count top-level directories to process" | tee -a "$LOG_FILE"
    echo "=============================================================" | tee -a "$LOG_FILE"
    
    # Process each audiobook
    local processed_count=0
    local success_count=0
    
    # If no directories found, show a message
    if [ "$dir_count" -eq 0 ]; then
        echo "ERROR: No directories with audio files found. Check the path and try again." | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Process each audiobook
    for ((i=0; i<dir_count; i++)); do
        local book_dir="${book_dirs[$i]}"
        echo "" | tee -a "$LOG_FILE"
        echo "BOOK [$((i+1))/$dir_count]: $(basename "$book_dir")" | tee -a "$LOG_FILE"
        echo "Full path: $book_dir" | tee -a "$LOG_FILE"
        echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
        
        # Process the audiobook
        process_audiobook "$book_dir" "$i"
        local result=$?
        
        if [ $result -eq 0 ]; then
            success_count=$((success_count + 1))
        fi
        processed_count=$((processed_count + 1))
        
        # Show progress after each book
        echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
        echo "PROGRESS: Processed $processed_count/$dir_count books ($success_count successful)" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    done
    
    echo "=============================================================" | tee -a "$LOG_FILE"
    echo "BATCH PROCESSING COMPLETED" | tee -a "$LOG_FILE"
    echo "=============================================================" | tee -a "$LOG_FILE"
    echo "Total books found:     $dir_count" | tee -a "$LOG_FILE"
    echo "Total books processed: $processed_count" | tee -a "$LOG_FILE"
    echo "Successfully created:  $success_count m4b files" | tee -a "$LOG_FILE"
    echo "Output directory:      $DEFAULT_OUTPUT_DIR" | tee -a "$LOG_FILE"
    echo "Log file:              $LOG_FILE" | tee -a "$LOG_FILE"
    echo "=============================================================" | tee -a "$LOG_FILE"
}

# Run the main function
main "$@"