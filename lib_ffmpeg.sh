#!/bin/bash
# lib_ffmpeg.sh - FFmpeg handling functions for audiobook processing
# Contains functions for converting audiobooks and handling FFmpeg processes

# Default timeout for ffmpeg operations (in seconds)
DEFAULT_FFMPEG_TIMEOUT=3600

# Run ffmpeg with timeout handling
# Arguments:
#   $1: Log file path
#   $2: Progress file path
#   $3: Stderr file path
#   $4: Timeout in seconds (optional, defaults to DEFAULT_FFMPEG_TIMEOUT)
#   $5+: FFmpeg command arguments
run_ffmpeg_with_timeout() {
    local LOG_FILE="$1"
    local progress_file="$2"
    local stderr_file="$3"
    local ffmpeg_timeout="${4:-$DEFAULT_FFMPEG_TIMEOUT}"
    
    # Remove the first 4 arguments to leave only ffmpeg args
    shift 4
    
    # Log the command
    echo "Running ffmpeg command with ${ffmpeg_timeout}s timeout" >> "$LOG_FILE"
    
    # Start ffmpeg in background
    ffmpeg "$@" 2>"$stderr_file" &
    local ffmpeg_pid=$!
    
    # Start a watchdog process that will terminate ffmpeg if it runs too long
    {
        local i
        for ((i=1; i<=$ffmpeg_timeout; i++)); do
            # Check if ffmpeg is still running
            if ! ps -p $ffmpeg_pid > /dev/null 2>&1; then
                break  # Process already finished
            fi
            
            # Print progress every 60 seconds
            if ((i % 60 == 0)); then
                echo "ffmpeg running for $i seconds..." >> "$LOG_FILE"
            fi
            
            sleep 1
        done
        
        # If ffmpeg is still running after timeout, kill it
        if ps -p $ffmpeg_pid > /dev/null 2>&1; then
            echo "Killing ffmpeg process after $ffmpeg_timeout second timeout..." >> "$LOG_FILE"
            kill -15 $ffmpeg_pid > /dev/null 2>&1  # Try SIGTERM first
            sleep 2
            # If still running, use SIGKILL
            if ps -p $ffmpeg_pid > /dev/null 2>&1; then
                kill -9 $ffmpeg_pid > /dev/null 2>&1
            fi
            # Signal that we're done to the progress monitor
            touch "${progress_file}.done" 2>/dev/null || true
            # Return failure
            return 1
        fi
    } &
    local watchdog_pid=$!
    
    # Wait for ffmpeg to complete
    wait $ffmpeg_pid
    local ffmpeg_result=$?
    
    # Terminate the watchdog
    if [ -n "$watchdog_pid" ] && ps -p $watchdog_pid > /dev/null 2>&1; then
        kill -15 $watchdog_pid > /dev/null 2>&1 || true
    fi
    
    # Return ffmpeg result
    return $ffmpeg_result
}

# Convert multiple audio files to a single m4b file
# Arguments:
#   $1: Output file path
#   $2: Log file path
#   $3: Progress file path
#   $4: Author name
#   $5: Book title
#   $6: Cover image path (optional)
#   $7+: Input audio files
convert_to_m4b() {
    local output_file="$1"
    local LOG_FILE="$2"
    local progress_file="$3"
    local author="$4"
    local title="$5"
    local cover_image="$6"
    
    # Get input files as remaining arguments
    shift 6
    local input_files=()
    
    # Add all remaining arguments as input files
    for file in "$@"; do
        if [ -f "$file" ]; then
            input_files+=("$file")
        fi
    done
    
    # Create temp directory for processing - use /tmp instead of output directory
    local temp_dir="/tmp/audiobook_ffmpeg_$(date +%s)"
    mkdir -p "$temp_dir"
    local temp_output_file="$temp_dir/$(basename "$output_file")"
    local stderr_file="$temp_dir/ffmpeg_errors.txt"
    
    echo "Converting to M4B format..." | tee -a "$LOG_FILE"
    echo "Output: $output_file" >> "$LOG_FILE"
    echo "Author: $author" >> "$LOG_FILE"
    echo "Title: $title" >> "$LOG_FILE"
    echo "Cover: ${cover_image:-None}" >> "$LOG_FILE"
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"
    
    # Base ffmpeg arguments
    local ffmpeg_args=(
        -y  # Overwrite output file if exists
        -nostdin  # Don't expect stdin input
    )
    
    # Add input files
    for file in "${input_files[@]}"; do
        ffmpeg_args+=(-i "$file")
    done
    
    # Add cover art if provided
    if [ -n "$cover_image" ] && [ -f "$cover_image" ]; then
        ffmpeg_args+=(-i "$cover_image")
        local has_cover=1
    else
        local has_cover=0
    fi
    
    # Configure output format and metadata
    ffmpeg_args+=(
        -map 0:a  # Map first input's audio
    )
    
    # Add cover art mapping if present
    if [ $has_cover -eq 1 ]; then
        ffmpeg_args+=(-map "$((${#input_files[@]})):v")
    fi
    
    # Add encoding parameters
    ffmpeg_args+=(
        -c:a aac  # Use AAC audio codec
        -b:a 64k  # 64kbps bitrate
        -c:v copy  # Copy video (cover art) stream
        -f mp4  # Output format: MP4
        -movflags faststart  # Optimize for streaming
        -metadata album="$title"
        -metadata artist="$author"
        -metadata title="$title"
        "$temp_output_file"
    )
    
    # Run ffmpeg with timeout
    run_ffmpeg_with_timeout "$LOG_FILE" "$progress_file" "$stderr_file" 7200 "${ffmpeg_args[@]}"
    local result=$?
    
    # Signal progress indicator to stop
    for i in {1..5}; do
        if touch "${progress_file}.done" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # Check result
    if [ $result -ne 0 ]; then
        echo "ERROR: ffmpeg command failed with exit code $result" | tee -a "$LOG_FILE"
        
        # Show error details
        if [ -f "$stderr_file" ]; then
            echo "----- ffmpeg error output -----" | tee -a "$LOG_FILE"
            tail -n 20 "$stderr_file" | tee -a "$LOG_FILE"
        fi
        
        # Always clean up temp directory on error
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Move to final destination
    mv "$temp_output_file" "$output_file"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    return 0
}