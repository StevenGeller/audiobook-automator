#!/bin/bash
# lib_progress.sh - Progress monitoring functions for audiobook processing

# Show a progress indicator for a long-running process
# Arguments:
#   $1: Progress file path
#   $2: Message prefix
#   $3: Total items (optional)
show_progress_indicator() {
    local progress_file="$1"
    local message_prefix="$2"
    local total_items="${3:-0}"
    
    # Create progress file
    echo "0" > "$progress_file"
    
    # Progress animation characters - more visible
    local chars="▋▍▎▏▏▎▍▋█▓▒░░▒▓█"
    local idx=0
    local start_time=$(date +%s)
    local last_update_time=$start_time
    local last_count=0
    
    # Clear line function
    clear_line() {
        printf "\r\033[K"
    }
    
    # Print banner to ensure progress is always visible
    echo "========== PROGRESS TRACKING STARTED ==========" 
    echo "Book: $message_prefix"
    echo "Starting file processing..."
    
    # Set a maximum wait time (20 minutes) in case the signal file is never created
    local max_wait_seconds=$((20*60))
    local start_wait_time=$(date +%s)
    
    # Loop until signaled to stop or timeout reached
    while [ ! -f "${progress_file}.done" ]; do
        # Check for maximum wait time exceeded
        local current_time=$(date +%s)
        local wait_time=$((current_time - start_wait_time))
        if [ $wait_time -gt $max_wait_seconds ]; then
            echo "WARNING: Progress indicator timed out after waiting $wait_time seconds"
            break
        fi
        
        # Get current progress count
        if [ -f "$progress_file" ]; then
            local count=$(cat "$progress_file" 2>/dev/null || echo "0")
            count=${count:-0}
        else
            local count=0
        fi
        
        # Calculate percentage if total is known
        if [ "$total_items" -gt 0 ] && [ "$count" -gt 0 ]; then
            local percent=$((count * 100 / total_items))
            percent=$((percent > 100 ? 100 : percent))
        else
            local percent="?"
        fi
        
        # Update animation character
        char=${chars:$idx:1}
        idx=$(( (idx + 1) % ${#chars} ))
        
        # Calculate elapsed time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_min=$((elapsed / 60))
        local elapsed_sec=$((elapsed % 60))
        
        # Format elapsed time
        local elapsed_time=$(printf "%02d:%02d:%02d" $((elapsed_min/60)) $((elapsed_min%60)) $elapsed_sec)
        
        # Create progress bar if percentage is known
        local progress_bar=""
        if [ "$percent" != "?" ]; then
            local bar_size=20
            local filled_size=$((percent * bar_size / 100))
            local empty_size=$((bar_size - filled_size))
            
            progress_bar="["
            for ((i=0; i<filled_size; i++)); do
                progress_bar+="█"
            done
            for ((i=0; i<empty_size; i++)); do
                progress_bar+="░"
            done
            progress_bar+="]"
        fi
        
        # Calculate processing rate and ETA if we have multiple updates
        if [ "$count" -gt "$last_count" ] && [ "$current_time" -gt "$last_update_time" ]; then
            local time_diff=$((current_time - last_update_time))
            local count_diff=$((count - last_count))
            
            # Items per second
            if [ "$time_diff" -gt 0 ]; then
                local rate=$(echo "scale=2; $count_diff / $time_diff" | bc)
                
                # Calculate ETA if we have a total
                if [ "$total_items" -gt 0 ] && [ "$rate" != "0" ] && [ ! "$rate" = "0.00" ]; then
                    local remaining=$((total_items - count))
                    local eta_seconds=$(echo "scale=0; $remaining / $rate" | bc)
                    
                    # Format ETA
                    local eta_min=$((eta_seconds / 60))
                    local eta_sec=$((eta_seconds % 60))
                    local eta=$(printf "%02d:%02d:%02d" $((eta_min/60)) $((eta_min%60)) $eta_sec)
                    
                    # Include rate and ETA in the progress display
                    clear_line
                    if [ "$percent" != "?" ]; then
                        printf "STATUS:  %s\nPROGRESS: %s %s%%\nFILES:    %s/%s (%.1f files/sec)\nTIME:     %s elapsed | ETA: %s\n" "$message_prefix" "$progress_bar" "$percent" "$count" "$total_items" "$rate" "$elapsed_time" "$eta"
                    else
                        printf "STATUS:  %s\nPROGRESS: %s\nFILES:    %s processed (%.1f files/sec)\nTIME:     %s elapsed\n" "$message_prefix" "$char" "$count" "$rate" "$elapsed_time"
                    fi
                else
                    # Without ETA
                    clear_line
                    if [ "$percent" != "?" ]; then
                        printf "STATUS:  %s\nPROGRESS: %s %s%%\nFILES:    %s/%s (%.1f files/sec)\nTIME:     %s elapsed\n" "$message_prefix" "$progress_bar" "$percent" "$count" "$total_items" "$rate" "$elapsed_time"
                    else
                        printf "STATUS:  %s\nPROGRESS: %s\nFILES:    %s processed (%.1f files/sec)\nTIME:     %s elapsed\n" "$message_prefix" "$char" "$count" "$rate" "$elapsed_time"
                    fi
                fi
                
                # Update last values for next calculation
                last_update_time=$current_time
                last_count=$count
            else
                # Without rate calculation
                clear_line
                if [ "$percent" != "?" ]; then
                    printf "STATUS:  %s\nPROGRESS: %s %s%%\nFILES:    %s/%s\nTIME:     %s elapsed\n" "$message_prefix" "$progress_bar" "$percent" "$count" "$total_items" "$elapsed_time"
                else
                    printf "STATUS:  %s\nPROGRESS: %s\nFILES:    %s processed\nTIME:     %s elapsed\n" "$message_prefix" "$char" "$count" "$elapsed_time"
                fi
            fi
        else
            # Basic progress display
            clear_line
            if [ "$percent" != "?" ]; then
                printf "STATUS:  %s\nPROGRESS: %s %s%%\nFILES:    %s/%s\nTIME:     %s elapsed\n" "$message_prefix" "$progress_bar" "$percent" "$count" "$total_items" "$elapsed_time"
            else
                printf "STATUS:  %s\nPROGRESS: %s\nFILES:    %s processed\nTIME:     %s elapsed\n" "$message_prefix" "$char" "$count" "$elapsed_time"
            fi
        fi
        
        # Check for ffmpeg conversion start
        if [ -f "${progress_file}.convert" ]; then
            echo -e "\nSTATUS:  Converting audio files to m4b format..."
            echo "         This may take a while depending on the size and number of files."
        fi
        
        # Brief pause
        sleep 1
    done
    
    # Final message
    clear_line
    echo -e "\n========== PROCESS COMPLETED =========="
    echo "$message_prefix FINISHED!"
    echo "Processing time: $elapsed_time"
    echo "Files processed: $count/$total_items"
    echo "======================================="
    
    # Clean up progress files
    rm -f "$progress_file" "${progress_file}.done" "${progress_file}.convert" 2>/dev/null
    
    return 0
}

# Start progress indicator in background
# Arguments:
#   $1: Progress file path
#   $2: Message prefix
#   $3: Total items (optional)
# Returns:
#   PID of progress indicator process
start_progress_indicator() {
    local progress_file="$1"
    local message_prefix="$2"
    local total_items="${3:-0}"
    
    # Start in background
    show_progress_indicator "$progress_file" "$message_prefix" "$total_items" &
    echo $!
}

# Update progress counter
# Arguments:
#   $1: Progress file path
#   $2: New count value (or increment by 1 if omitted)
update_progress() {
    local progress_file="$1"
    
    if [ -z "$2" ]; then
        # Increment existing count
        if [ -f "$progress_file" ]; then
            local current=$(cat "$progress_file" 2>/dev/null || echo "0")
            current=${current:-0}
            echo $((current + 1)) > "$progress_file"
        else
            echo "1" > "$progress_file"
        fi
    else
        # Set to specific value
        echo "$2" > "$progress_file"
    fi
}

# Signal conversion phase
# Arguments:
#   $1: Progress file path
signal_conversion_start() {
    local progress_file="$1"
    touch "${progress_file}.convert" 2>/dev/null
}

# Stop progress indicator
# Arguments:
#   $1: Progress file path
#   $2: Progress indicator PID
stop_progress_indicator() {
    local progress_file="$1"
    local progress_pid="$2"
    
    # Signal to stop
    touch "${progress_file}.done" 2>/dev/null
    
    # Wait for process to exit
    if [ -n "$progress_pid" ]; then
        wait $progress_pid 2>/dev/null || true
    fi
}