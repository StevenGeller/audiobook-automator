#!/bin/bash
# Audiobook Processor - Converts audio files to m4b format with proper metadata

# Default behavior: remove original files after successful conversion
KEEP_ORIGINAL_FILES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-original-files)
            KEEP_ORIGINAL_FILES=true
            shift
            ;;
        *)
            # First non-flag argument is the audiobooks directory
            if [ -z "$AUDIOBOOKS_DIR" ]; then
                AUDIOBOOKS_DIR="$1"
            fi
            shift
            ;;
    esac
done

# Check if directory was provided
if [ -z "$AUDIOBOOKS_DIR" ]; then
    echo "Please provide the path to your audiobooks directory"
    echo "Usage: ./audiobook_processor.sh /path/to/audiobooks/folder [--keep-original-files]"
    exit 1
fi

# Ensure the audiobooks directory exists
if [ ! -d "$AUDIOBOOKS_DIR" ]; then
    echo "Error: The directory $AUDIOBOOKS_DIR does not exist"
    exit 1
fi

# Create the log file in the audiobooks directory
LOG_FILE="$AUDIOBOOKS_DIR/processing_log.txt"

# Check if we can write to the directory
if [ ! -w "$AUDIOBOOKS_DIR" ]; then
    echo "Warning: No write permission to $AUDIOBOOKS_DIR"
    echo "Using temporary log file in home directory instead"
    LOG_FILE="$HOME/audiobook_processing_log.txt"
fi

# We will process files in place, no need for a separate output directory
OUTPUT_DIR="$AUDIOBOOKS_DIR"

# Initialize log file
if ! echo "Audiobook Processing Log - $(date)" > "$LOG_FILE" 2>/dev/null; then
    echo "Warning: Could not create log file at $LOG_FILE"
    echo "Continuing without logging to file"
    # Create a dummy log function that does nothing
    log() { :; }
else
    # Create a log function that both displays and logs
    log() {
        echo "$@"
        echo "$@" >> "$LOG_FILE"
    }
fi

# Function to sanitize filenames for cross-platform compatibility
sanitize_filename() {
    # Replace problematic characters with underscores
    # Keep alphanumeric, spaces, dots, hyphens, and underscores
    # Convert spaces to spaces (we'll keep them for readability)
    local sanitized
    sanitized=$(echo "$1" | sed -e 's/[^a-zA-Z0-9 ._-]/_/g')
    
    # Remove leading and trailing spaces
    sanitized=$(echo "$sanitized" | sed -e 's/^ *//' -e 's/ *$//')
    
    # Return the sanitized filename
    echo "$sanitized"
}

# Function to format time in HH:MM:SS
format_time() {
    local total_seconds=$1
    printf "%02d:%02d:%02d" $((total_seconds/3600)) $((total_seconds%3600/60)) $((total_seconds%60))
}

# Function to extract author and title from filename or directory name
extract_filename_metadata() {
    local input="$1"
    local basename=$(basename "$input")
    
    # Remove file extension if present
    local nameonly="${basename%.*}"
    
    # Check if the name follows the pattern "Author - Title" or similar
    if [[ "$nameonly" == *" - "* ]]; then
        local author=$(echo "$nameonly" | sed -E 's/^(.*) - .*$/\1/g' | xargs)
        local title=$(echo "$nameonly" | sed -E 's/^.* - (.*)$/\1/g' | xargs)
        echo "author=$author"
        echo "title=$title"
    # Check if name follows pattern "Title by Author"
    elif [[ "$nameonly" == *" by "* ]]; then
        local title=$(echo "$nameonly" | sed -E 's/^(.*) by .*$/\1/g' | xargs)
        local author=$(echo "$nameonly" | sed -E 's/^.* by (.*)$/\1/g' | xargs)
        echo "author=$author"
        echo "title=$title"
    # Check if name follows "Title (Author)" pattern
    elif [[ "$nameonly" =~ (.*)\((.*)\) ]]; then
        local title=$(echo "$nameonly" | sed -E 's/^(.*)\(.*\)$/\1/g' | xargs)
        local author=$(echo "$nameonly" | sed -E 's/^.*\((.*)\)$/\1/g' | xargs)
        echo "author=$author"
        echo "title=$title"
    else
        # Just use as title
        echo "title=$nameonly"
    fi
}

# Main function to process an audiobook directory
process_audiobook() {
    local book_dir="$1"
    local book_name=$(basename "$book_dir")
    
    # Show book number out of total in array
    local book_count=${#processed_books[@]}
    echo "Processing audiobook $book_count: $book_name"
    
    # Check if we've already processed this book
    if is_book_processed "$book_dir"; then
        echo "Skipping already processed book: $book_name" | tee -a "$LOG_FILE"
        return
    fi
    
    # Add to processed list before processing to prevent reprocessing
    processed_books+=("$book_dir")
    
    # Create a unique temp directory for processing
    local timestamp=$(date +%s)
    local temp_dir="$book_dir/temp_processing_$timestamp"
    mkdir -p "$temp_dir" || {
        echo "Error: Failed to create temp directory: $temp_dir" | tee -a "$LOG_FILE"
        echo "Skipping this audiobook" | tee -a "$LOG_FILE"
        return
    }
    
    # Create processed subdirectory if it doesn't exist
    local processed_dir="$AUDIOBOOKS_DIR/processed"
    if [ ! -d "$processed_dir" ]; then
        mkdir -p "$processed_dir" || {
            echo "Error: Failed to create processed directory: $processed_dir" | tee -a "$LOG_FILE"
            echo "Will use original location instead" | tee -a "$LOG_FILE"
            processed_dir="$AUDIOBOOKS_DIR"
        }
    fi
    
    echo "=====================================" | tee -a "$LOG_FILE"
    echo "Processing: $book_name" | tee -a "$LOG_FILE"
    echo "------------------------------------" >> "$LOG_FILE"
    echo "Source directory: $book_dir" >> "$LOG_FILE"
    echo "Temp directory: $temp_dir" >> "$LOG_FILE"
    
    # Check if we already have an m4b file in the directory (more reliable search)
    local existing_m4b=""
    if find "$book_dir" -maxdepth 1 -type f -name "*.m4b" 2>/dev/null | grep -q .; then
        existing_m4b=$(find "$book_dir" -maxdepth 1 -type f -name "*.m4b" | head -n 1)
        echo "Found existing m4b file: $(basename "$existing_m4b")" | tee -a "$LOG_FILE"
    fi
    
    # Initialize variables for metadata
    local title=""
    local author=""
    local narrator=""
    local year=""
    local genre="Audiobook"
    local series=""
    local series_part=""
    local description=""
    
    # Track where we got the metadata from (for debugging)
    local title_source=""
    local author_source=""
    local narrator_source=""
    
    # First try to get metadata from directory name
    if [[ "$book_name" == *" - "* ]]; then
        author=$(echo "$book_name" | sed -E 's/^(.*) - .*$/\1/g' | xargs)
        title=$(echo "$book_name" | sed -E 's/^.* - (.*)$/\1/g' | xargs)
        author_source="directory name"
        title_source="directory name"
        echo "- Extracted author from directory name: $author" | tee -a "$LOG_FILE"
        echo "- Extracted title from directory name: $title" | tee -a "$LOG_FILE"
    fi
    
    # Look for metadata in cover.txt if it exists
    if [ -f "$book_dir/cover.txt" ]; then
        echo "- Found cover.txt, extracting metadata" | tee -a "$LOG_FILE"
        while IFS= read -r line; do
            if [[ "$line" == "Title:"* ]] && [ -z "$title" ]; then
                title=$(echo "$line" | sed 's/^Title: *//' | xargs)
                title_source="cover.txt"
                echo "- Extracted title from cover.txt: $title" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Author:"* ]] && [ -z "$author" ]; then
                author=$(echo "$line" | sed 's/^Author: *//' | xargs)
                author_source="cover.txt"
                echo "- Extracted author from cover.txt: $author" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Narrator:"* ]] && [ -z "$narrator" ]; then
                narrator=$(echo "$line" | sed 's/^Narrator: *//' | xargs)
                narrator_source="cover.txt"
                echo "- Extracted narrator from cover.txt: $narrator" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Series:"* ]] && [ -z "$series" ]; then
                series=$(echo "$line" | sed 's/^Series: *//' | xargs)
                echo "- Extracted series from cover.txt: $series" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Book:"* ]] && [ -z "$series_part" ]; then
                series_part=$(echo "$line" | sed 's/^Book: *//' | xargs)
                echo "- Extracted book number from cover.txt: $series_part" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Year:"* ]] && [ -z "$year" ]; then
                year=$(echo "$line" | sed 's/^Year: *//' | xargs)
                echo "- Extracted year from cover.txt: $year" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Genre:"* ]] && [ "$genre" == "Audiobook" ]; then
                genre=$(echo "$line" | sed 's/^Genre: *//' | xargs)
                echo "- Extracted genre from cover.txt: $genre" | tee -a "$LOG_FILE"
            elif [[ "$line" == "Description:"* ]] && [ -z "$description" ]; then
                description=$(echo "$line" | sed 's/^Description: *//' | xargs)
                echo "- Extracted description from cover.txt: $description" | tee -a "$LOG_FILE"
            fi
        done < "$book_dir/cover.txt"
    fi
    
    # Try to find cover art
    local cover_image=""
    
    # First check for cover.jpg in main directory
    if [ -f "$book_dir/cover.jpg" ]; then
        cover_image="$book_dir/cover.jpg"
        echo "- Found cover image: cover.jpg" | tee -a "$LOG_FILE"
    elif [ -f "$book_dir/cover.png" ]; then
        cover_image="$book_dir/cover.png"
        echo "- Found cover image: cover.png" | tee -a "$LOG_FILE"
    elif [ -f "$book_dir/folder.jpg" ]; then
        cover_image="$book_dir/folder.jpg"
        echo "- Found cover image: folder.jpg" | tee -a "$LOG_FILE"
    elif [ -d "$book_dir/cover_art" ]; then
        # Check for any image in the cover_art directory
        cover_image=$(find "$book_dir/cover_art" -type f -name "*.jpg" -o -name "*.png" | head -n 1)
        if [ -n "$cover_image" ]; then
            echo "- Found cover image in cover_art directory: $(basename "$cover_image")" | tee -a "$LOG_FILE"
        fi
    fi
    
    # If we have enough info (title and author), try to look up better metadata online
    if [ -n "$title" ] && [ -n "$author" ]; then
        echo "- Attempting to lookup metadata online for: $title by $author" | tee -a "$LOG_FILE"
        
        # Create a Python script for metadata lookup
        cat > "$temp_dir/metadata_lookup.py" << 'EOF'
#!/usr/bin/env python3
import sys
import json
import requests
import urllib.parse
from bs4 import BeautifulSoup
from urllib.parse import quote_plus
from difflib import SequenceMatcher
try:
    from fuzzywuzzy import fuzz
except ImportError:
    # If fuzzywuzzy is not available, create a simple ratio function
    class fuzz:
        @staticmethod
        def ratio(a, b):
            def similar(a, b):
                return SequenceMatcher(None, a, b).ratio()
            return similar(a.lower(), b.lower()) * 100

def lookup_book_metadata(title, author):
    metadata = {}
    
    # Prepare search query
    query = f"{title} {author} book"
    
    # Try Goodreads for basic info
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    
    search_url = f"https://www.goodreads.com/search?q={quote_plus(query)}"
    
    try:
        response = requests.get(search_url, headers=headers, timeout=10)
        
        if response.status_code != 200:
            return metadata
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Find the first result with good title match
        best_match = None
        best_score = 0
        
        results = soup.select('.bookTitle')
        for result in results[:5]:  # Check first 5 results
            result_title = result.text.strip()
            score = fuzz.ratio(title.lower(), result_title.lower())
            
            if score > best_score and score > 70:  # Require at least 70% match
                best_score = score
                best_match = result
        
        if not best_match:
            return metadata
            
        # Get book page URL
        book_url = "https://www.goodreads.com" + best_match.get('href')
        
        # Fetch book page
        book_response = requests.get(book_url, headers=headers)
        if book_response.status_code != 200:
            return metadata
            
        book_soup = BeautifulSoup(book_response.text, 'html.parser')
        
        # Extract title (more accurate than search result)
        title_elem = book_soup.select_one('h1#bookTitle')
        if title_elem:
            metadata['title'] = title_elem.text.strip()
            
        # Extract author
        author_elem = book_soup.select_one('.authorName span[itemprop="name"]')
        if author_elem:
            metadata['author'] = author_elem.text.strip()
            
        # Extract series info
        series_elem = book_soup.select_one('#bookSeries a')
        if series_elem:
            series_text = series_elem.text.strip()
            if series_text:
                # Format is typically "(Series Name #X)"
                series_text = series_text.strip('()')
                if '#' in series_text:
                    series_name, series_num = series_text.split('#', 1)
                    metadata['series'] = series_name.strip()
                    metadata['series_part'] = series_num.strip()
                else:
                    metadata['series'] = series_text
        
        # Extract publication year
        pub_elem = book_soup.select_one('#details [itemprop="datePublished"]')
        if pub_elem:
            pub_text = pub_elem.text.strip()
            # Try to extract just the year
            import re
            year_match = re.search(r'\b(19|20)\d{2}\b', pub_text)
            if year_match:
                metadata['year'] = year_match.group(0)
                
        # Extract genres
        genres = []
        genre_elems = book_soup.select('.left .elementList .bookPageGenreLink')
        for genre_elem in genre_elems[:3]:  # Get top 3 genres
            genre = genre_elem.text.strip()
            if genre and genre not in genres:
                genres.append(genre)
                
        if genres:
            metadata['genres'] = genres
            
        # Extract description
        desc_elem = book_soup.select_one('#description span[style="display:none"]')
        if not desc_elem:
            desc_elem = book_soup.select_one('#description span')
            
        if desc_elem:
            metadata['description'] = desc_elem.text.strip()
            
        # Try to find narrator info in description
        if 'description' in metadata:
            desc = metadata['description'].lower()
            narrator_markers = ['narrated by', 'narrator:', 'voice of', 'read by']
            for marker in narrator_markers:
                if marker in desc:
                    # Get text after marker up to next punctuation or line break
                    idx = desc.find(marker) + len(marker)
                    narrator_text = desc[idx:idx+100]  # Look at next 100 chars
                    
                    # Clean up - get text up to punctuation
                    import re
                    narrator_match = re.search(r'[^a-zA-Z\s]', narrator_text)
                    if narrator_match:
                        narrator_text = narrator_text[:narrator_match.start()]
                        
                    narrator_text = narrator_text.strip()
                    if len(narrator_text) > 0 and len(narrator_text) < 50:  # Reasonable length for a name
                        metadata['narrator'] = narrator_text.title()  # Convert to title case
                        break
            
    except Exception as e:
        # Just silently return what we have
        pass
        
    return metadata

# Main execution
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python metadata_lookup.py 'title' 'author'")
        sys.exit(1)
        
    title = sys.argv[1]
    author = sys.argv[2]
    
    result = lookup_book_metadata(title, author)
    print(json.dumps(result))
EOF
        
        # Make the script executable
        chmod +x "$temp_dir/metadata_lookup.py"
        
        # Run the metadata lookup if python3 is available
        if command -v python3 &>/dev/null; then
            echo "Running metadata lookup..." >> "$LOG_FILE"
            
            # Run the metadata lookup script
            metadata_result=$(python3 "$temp_dir/metadata_lookup.py" "$title" "$author" 2>/dev/null)
            
            # Check if we got valid JSON
            if [ -n "$metadata_result" ] && [ "$(echo "$metadata_result" | grep -c "{")" -gt 0 ]; then
                echo "- Received metadata from online lookup" | tee -a "$LOG_FILE"
                
                # Extract potential improvements from the result
                improved_title=$(echo "$metadata_result" | grep -o '"title":"[^"]*"' | sed 's/"title":"//;s/"$//')
                improved_author=$(echo "$metadata_result" | grep -o '"author":"[^"]*"' | sed 's/"author":"//;s/"$//')
                online_series=$(echo "$metadata_result" | grep -o '"series":"[^"]*"' | sed 's/"series":"//;s/"$//')
                online_series_part=$(echo "$metadata_result" | grep -o '"series_part":"[^"]*"' | sed 's/"series_part":"//;s/"$//')
                online_year=$(echo "$metadata_result" | grep -o '"year":"[^"]*"' | sed 's/"year":"//;s/"$//')
                online_narrator=$(echo "$metadata_result" | grep -o '"narrator":"[^"]*"' | sed 's/"narrator":"//;s/"$//')
                description=$(echo "$metadata_result" | grep -o '"description":"[^"]*"' | sed 's/"description":"//;s/"$//' | sed 's/\\"/"/g' | head -c 500)
                
                # Extract genres
                online_genres=$(echo "$metadata_result" | grep -o '"genres":\[[^]]*\]' | sed 's/"genres":\[//;s/\]$//' | tr -d '"' | tr ',' '\n')
                
                # Use the first genre as our primary
                if [ -n "$online_genres" ]; then
                    primary_genre=$(echo "$online_genres" | head -n 1)
                    if [ -n "$primary_genre" ]; then
                        genre="$primary_genre"
                        echo "- Found primary genre: $genre" | tee -a "$LOG_FILE"
                    fi
                    
                    # Log all genres
                    echo "- Found genres: $(echo "$online_genres" | tr '\n' ', ')" | tee -a "$LOG_FILE"
                fi
                
                # Use improved metadata if we got it - but respect user input
                if [ -n "$improved_title" ] && [ "$title_source" != "user input" ]; then
                    title="$improved_title"
                    title_source="online"
                    echo "- Using improved title from online: $title" | tee -a "$LOG_FILE"
                fi
                
                if [ -n "$improved_author" ] && [ "$author_source" != "user input" ]; then
                    author="$improved_author"
                    author_source="online"
                    echo "- Using improved author from online: $author" | tee -a "$LOG_FILE"
                fi
                
                if [ -z "$narrator" ] && [ -n "$online_narrator" ]; then
                    narrator="$online_narrator"
                    narrator_source="online"
                    echo "- Found narrator from online: $narrator" | tee -a "$LOG_FILE"
                fi
                
                if [ -z "$series" ] && [ -n "$online_series" ]; then
                    series="$online_series"
                    echo "- Found series from online: $series" | tee -a "$LOG_FILE"
                    
                    if [ -z "$series_part" ] && [ -n "$online_series_part" ]; then
                        series_part="$online_series_part"
                        echo "- Found series part from online: $series_part" | tee -a "$LOG_FILE"
                    fi
                fi
                
                if [ -z "$year" ] && [ -n "$online_year" ]; then
                    year="$online_year"
                    echo "- Found year from online: $year" | tee -a "$LOG_FILE"
                fi
                
                if [ -n "$description" ]; then
                    echo "- Found description from online" | tee -a "$LOG_FILE"
                fi
            else
                echo "- No metadata found online" | tee -a "$LOG_FILE"
            fi
        else
            echo "- Python3 not available, skipping online metadata lookup" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Create progress file for tracking
    local progress_file="${temp_dir}/progress.txt"
    touch "$progress_file"
    
    # If we have an existing m4b, we'll use that instead of creating a new one
    if [ -n "$existing_m4b" ]; then
        echo "Found existing M4B file: $(basename "$existing_m4b")" | tee -a "$LOG_FILE"
        echo "Will use this file instead of creating a new one" | tee -a "$LOG_FILE"
        
        # Extract metadata from the m4b file if available
        if command -v mediainfo &>/dev/null; then
            local m4b_info=$(mediainfo "$existing_m4b")
            
            # Extract title if we don't have it
            if [ -z "$title" ]; then
                local m4b_title=$(echo "$m4b_info" | grep -i "^Title " | head -n 1 | cut -d: -f2- | xargs)
                if [ -n "$m4b_title" ]; then
                    title="$m4b_title"
                    title_source="existing m4b"
                    echo "- Extracted title from m4b: $title" | tee -a "$LOG_FILE"
                fi
            fi
            
            if [ -z "$author" ]; then
                local m4b_author=$(echo "$m4b_info" | grep -i "Performer" | head -n 1 | cut -d: -f2- | xargs)
                if [ -n "$m4b_author" ]; then
                    author="$m4b_author"
                    author_source="existing m4b"
                    echo "- Extracted author from m4b: $author" | tee -a "$LOG_FILE"
                fi
            fi
        fi
        
        # If we still don't have enough metadata, use the filename
        if [ -z "$title" ] || [ -z "$author" ]; then
            local m4b_basename=$(basename "$existing_m4b" .m4b)
            
            if [[ "$m4b_basename" == *" - "* ]]; then
                if [ -z "$author" ]; then
                    author=$(echo "$m4b_basename" | cut -d'-' -f1 | xargs)
                    author_source="m4b filename"
                    echo "- Extracted author from m4b filename: $author" | tee -a "$LOG_FILE"
                fi
                
                if [ -z "$title" ]; then
                    title=$(echo "$m4b_basename" | cut -d'-' -f2- | xargs)
                    title_source="m4b filename"
                    echo "- Extracted title from m4b filename: $title" | tee -a "$LOG_FILE"
                fi
            fi
        fi
        
        # If we still don't have enough metadata, use fallbacks
        if [ -z "$title" ]; then
            title=$(basename "$book_dir")
            title_source="directory name"
            echo "- Using directory name as title: $title" | tee -a "$LOG_FILE"
        fi
        
        if [ -z "$author" ]; then
            author="Unknown Author"
            author_source="default"
            echo "- Using default author: $author" | tee -a "$LOG_FILE"
        fi
        
        # Set dummy variables for processing to continue
        local ffmpeg_result=0
        # Skip to the moving stage
        echo "Skipping ffmpeg conversion, using existing m4b file" | tee -a "$LOG_FILE"
        touch "${progress_file}.done" 2>/dev/null
    else
        echo "Creating m4b file..." >> "$LOG_FILE"
        
        # Find all audio files in the directory
        echo "Searching for audio files in $book_name..." >> "$LOG_FILE"
        
        # Get list of audio files using find instead of fd for better compatibility
        audio_files=$(find "$book_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" -o -name "*.wav" -o -name "*.aac" \) | sort)
        
        # Ensure we found audio files
        if [ -z "$audio_files" ]; then
            echo "Error: No audio files found in $book_dir" | tee -a "$LOG_FILE"
            echo "Skipping this directory" | tee -a "$LOG_FILE"
            rm -rf "$temp_dir"
            return
        fi
        
        # Count files
        file_count=$(echo "$audio_files" | wc -l)
        echo "Found $file_count audio files" | tee -a "$LOG_FILE"
        
        # Extract metadata from first audio file if needed
        first_file=$(echo "$audio_files" | head -n 1)
        
        if command -v mediainfo &>/dev/null; then
            echo "Extracting metadata from audio files..." >> "$LOG_FILE"
            
            # Get info from first file
            media_info=$(mediainfo "$first_file")
            
            # Extract title if we don't have it yet
            if [ -z "$title" ] && grep -q "Title" <<< "$media_info"; then
                title=$(echo "$media_info" | grep -i "^Title " | head -n 1 | cut -d: -f2- | xargs)
                title_source="media info"
                echo "- Extracted title from audio: $title" | tee -a "$LOG_FILE"
            fi
            
            # Extract artist/author if we don't have it yet
            if [ -z "$author" ]; then
                # Try Performer tag first (more likely for audiobooks)
                if grep -q "Performer" <<< "$media_info"; then
                    author=$(echo "$media_info" | grep -i "Performer" | head -n 1 | cut -d: -f2- | xargs)
                    author_source="media info (performer)"
                    echo "- Extracted author from audio (performer): $author" | tee -a "$LOG_FILE"
                # Then try Artist tag
                elif grep -q "Artist" <<< "$media_info"; then
                    author=$(echo "$media_info" | grep -i "Artist" | head -n 1 | cut -d: -f2- | xargs)
                    author_source="media info (artist)"
                    echo "- Extracted author from audio (artist): $author" | tee -a "$LOG_FILE"
                # Then try Album Artist tag
                elif grep -q "Album/Performer" <<< "$media_info"; then
                    author=$(echo "$media_info" | grep -i "Album/Performer" | head -n 1 | cut -d: -f2- | xargs)
                    author_source="media info (album artist)"
                    echo "- Extracted author from audio (album artist): $author" | tee -a "$LOG_FILE"
                fi
            fi
            
            # Try to get album if we don't have a title
            if [ -z "$title" ] && grep -q "Album" <<< "$media_info"; then
                title=$(echo "$media_info" | grep -i "Album" | head -n 1 | cut -d: -f2- | xargs)
                title_source="media info (album)"
                echo "- Extracted title from audio (album): $title" | tee -a "$LOG_FILE"
            fi
            
            # If we have a title but not an author, try to extract from title
            if [ -n "$title" ] && [ -z "$author" ] && [[ "$title" == *" - "* ]]; then
                author=$(echo "$title" | sed -E 's/^(.*) - .*$/\1/g' | xargs)
                title=$(echo "$title" | sed -E 's/^.* - (.*)$/\1/g' | xargs)
                author_source="derived from title"
                echo "- Extracted author from title: $author" | tee -a "$LOG_FILE"
                echo "- Updated title: $title" | tee -a "$LOG_FILE"
            fi
        fi
        
        # If we still don't have metadata, try extracting from filename
        if [ -z "$title" ] || [ -z "$author" ]; then
            echo "Attempting to extract metadata from filenames..." >> "$LOG_FILE"
            
            # Try the first file
            local filename_meta=$(extract_filename_metadata "$first_file")
            
            # Extract title
            if [ -z "$title" ] && grep -q "title=" <<< "$filename_meta"; then
                title=$(echo "$filename_meta" | grep "title=" | cut -d= -f2-)
                title_source="filename"
                echo "- Extracted title from filename: $title" | tee -a "$LOG_FILE"
            fi
            
            # Extract author
            if [ -z "$author" ] && grep -q "author=" <<< "$filename_meta"; then
                author=$(echo "$filename_meta" | grep "author=" | cut -d= -f2-)
                author_source="filename"
                echo "- Extracted author from filename: $author" | tee -a "$LOG_FILE"
            fi
        fi
        
        # If we still don't have a title, use the directory name
        if [ -z "$title" ]; then
            title="$book_name"
            title_source="directory name"
            echo "- Using directory name as title: $title" | tee -a "$LOG_FILE"
        fi
        
        # If we still don't have an author, use default
        if [ -z "$author" ]; then
            author="Unknown Author"
            author_source="default"
            echo "- Using default author: $author" | tee -a "$LOG_FILE"
        fi
        
        # Generate final output filename from metadata
        local sanitized_author=$(sanitize_filename "$author")
        local sanitized_title=$(sanitize_filename "$title")
        local output_filename="${sanitized_author} - ${sanitized_title}.m4b"
        
        # Start progress indicator in background
        start_time=$(date +%s)
        {
            # Function to show spinner
            progress_indicator() {
                local symbols=("-" "\\" "|" "/")
                local delay=0.2
                local i=0
                
                while [ ! -e "${progress_file}.done" ]; do
                    symbol=${symbols[$i]}
                    echo -ne "\rProcessing... $symbol"
                    i=$(( (i+1) % 4 ))
                    sleep $delay
                done
                echo -e "\rProcessing... Done!"
            }
            
            # Set up trap to ensure we clean up when done
            cleanup_progress() {
                # Remove flag file
                rm -f "${progress_file}.done" 2>/dev/null
                echo -e "\rProcessing... Cancelled"
                exit
            }
            
            # Set up trap for most common signals
            trap cleanup_progress EXIT INT TERM
            
            # Run progress indicator
            progress_indicator
            
            # Remove the trap when we're done
            trap - EXIT INT TERM
            exit 0
        } &
        progress_pid=$!
        
        # Calculate audio duration if possible (used for progress estimate)
        echo "Calculating total audio duration..." >> "$LOG_FILE"
        total_duration_seconds=0
        
        # Create file list for ffmpeg
        echo "Creating file list for ffmpeg..." >> "$LOG_FILE"
        echo "# File list for ffmpeg" > "$temp_dir/filelist.txt"
        
        # Process each audio file
        i=0
        for file in $audio_files; do
            i=$((i+1))
            echo "[$i/$file_count] Processing $(basename "$file")" >> "$LOG_FILE"
            
            # Get duration of this file if possible
            if command -v mediainfo &>/dev/null; then
                duration_str=$(mediainfo --Inform="Audio;%Duration%" "$file" 2>/dev/null)
                if [ -n "$duration_str" ]; then
                    # Convert to seconds (mediainfo returns milliseconds)
                    duration_seconds=$(echo "$duration_str / 1000" | bc 2>/dev/null)
                    if [ -n "$duration_seconds" ]; then
                        total_duration_seconds=$(echo "$total_duration_seconds + $duration_seconds" | bc)
                    fi
                fi
            fi
            
            # Add to file list with proper escaping
            # Make sure to properly quote the entire path
            printf "file '%s'\n" "$file" >> "$temp_dir/filelist.txt"
        done
        
        # Format the total duration
        if [ "$total_duration_seconds" -gt 0 ]; then
            formatted_duration=$(format_time "$total_duration_seconds")
            echo "Total audio duration: $formatted_duration" >> "$LOG_FILE"
        else
            echo "Warning: Could not determine audio duration" >> "$LOG_FILE"
        fi
        
        # Set up paths
        local temp_output_file="$temp_dir/output.m4b"
        
        # Create stderr file for capturing ffmpeg output
        local stderr_file="$temp_dir/ffmpeg_stderr.txt"
        
        # Run ffmpeg to combine all files
        echo "Running ffmpeg to create m4b file..." >> "$LOG_FILE"
        
        # Create a more robust ffmpeg command with proper quoting and escaping
        # Use a simpler approach with fewer options to avoid command line issues
        local ffmpeg_cmd="ffmpeg -f concat -safe 0 -i \"$temp_dir/filelist.txt\" -c:a aac -b:a 64k -f mp4 -map_metadata -1"
        
        # Add cover image if available
        if [ -n "$cover_image" ]; then
            ffmpeg_cmd="$ffmpeg_cmd -i \"$cover_image\" -map 0:a -map 1:v -disposition:v attached_pic"
        fi
        
        # Add basic metadata
        ffmpeg_cmd="$ffmpeg_cmd -metadata title=\"$title\" -metadata artist=\"$author\" -metadata album=\"$title\" -metadata genre=\"$genre\""
        
        # Add optional metadata
        if [ -n "$narrator" ]; then
            ffmpeg_cmd="$ffmpeg_cmd -metadata composer=\"$narrator\" -metadata comment=\"Narrator: $narrator\""
        fi
        
        if [ -n "$series" ]; then
            ffmpeg_cmd="$ffmpeg_cmd -metadata show=\"$series\""
            if [ -n "$series_part" ]; then
                ffmpeg_cmd="$ffmpeg_cmd -metadata episode_id=\"$series_part\""
            fi
        fi
        
        if [ -n "$year" ]; then
            ffmpeg_cmd="$ffmpeg_cmd -metadata date=\"$year\""
        fi
        
        if [ -n "$description" ]; then
            # Truncate description to avoid issues
            local short_desc="${description:0:255}"
            ffmpeg_cmd="$ffmpeg_cmd -metadata description=\"$short_desc\""
        fi
        
        # Add output file
        ffmpeg_cmd="$ffmpeg_cmd \"$temp_output_file\""
        
        # Log the command
        echo "Executing: $ffmpeg_cmd" >> "$LOG_FILE"
        
        # Create a simpler alternative approach as backup
        echo "Preparing backup approach in case primary method fails..." >> "$LOG_FILE"
        
        # Try the primary approach first
        eval "$ffmpeg_cmd" 2>"$stderr_file"
        ffmpeg_result=$?
        
        # If the primary approach fails, try a more direct approach
        if [ $ffmpeg_result -ne 0 ]; then
            echo "First approach failed with code $ffmpeg_result, trying backup method..." | tee -a "$LOG_FILE"
            
            # Create a simpler list format - extract the paths from between single quotes
            # Using perl for more reliable processing of quotes
            perl -ne "if (/'([^']+)'/) { print \"\$1\n\"; }" "$temp_dir/filelist.txt" > "$temp_dir/simplelist.txt"
            
            # Try to copy files to temp dir with sequential names to avoid special character issues
            echo "Copying files to temp directory with sequential names..." >> "$LOG_FILE"
            mkdir -p "$temp_dir/simple"
            counter=1
            
            while IFS= read -r file; do
                # Create padded counter (001, 002, etc.)
                padded_counter=$(printf "%03d" $counter)
                # Get file extension
                ext="${file##*.}"
                # Copy with simple name
                cp "$file" "$temp_dir/simple/$padded_counter.$ext" 2>/dev/null
                echo "Copied $file to $temp_dir/simple/$padded_counter.$ext" >> "$LOG_FILE"
                counter=$((counter + 1))
            done < "$temp_dir/simplelist.txt"
            
            # Try a much simpler ffmpeg command with the renamed files
            echo "Running simplified ffmpeg command..." | tee -a "$LOG_FILE"
            
            # Create a new file list with the renamed files
            find "$temp_dir/simple" -type f | sort > "$temp_dir/simple/filelist.txt"
            
            # Run a simpler ffmpeg command with minimal options
            # Create a simplified file list
            find "$temp_dir/simple" -type f -name "*.*" | sort | while read -r f; do
                printf "file '%s'\n" "$f"
            done > "$temp_dir/simple/concat_list.txt"
            
            # Use the simplified list
            ffmpeg -f concat -safe 0 -i "$temp_dir/simple/concat_list.txt" \
                  -c:a aac -b:a 64k \
                  -metadata title="$title" \
                  -metadata artist="$author" \
                  -metadata album="$title" \
                  "$temp_output_file" 2>>"$stderr_file"
                  
            # Update result
            ffmpeg_result=$?
            
            if [ $ffmpeg_result -eq 0 ]; then
                echo "Backup method succeeded!" | tee -a "$LOG_FILE"
            else
                # If that also fails, try an even simpler approach with direct file inputs
                echo "Second approach failed, trying final method..." | tee -a "$LOG_FILE"
                
                # Get all audio files in the temp dir, sort them into a properly formatted list
                find "$temp_dir/simple" -type f -name "*.*" | sort > "$temp_dir/simple/final_list.txt"
                
                # Run the simplest possible ffmpeg command with direct inputs
                echo "Trying direct conversion with each file individually..." | tee -a "$LOG_FILE"
                
                # First convert all files to one format (mp3) to ensure compatibility
                mkdir -p "$temp_dir/converted"
                
                # For each file in the simple directory, convert to standard format
                find "$temp_dir/simple" -type f | sort | while read -r file; do
                    base_name=$(basename "$file")
                    ffmpeg -i "$file" -c:a libmp3lame -q:a 4 "$temp_dir/converted/$base_name.mp3" 2>/dev/null
                    echo "Converted $(basename "$file") to standard format" >> "$LOG_FILE"
                done
                
                # Now combine the standardized files
                echo "Combining standardized files..." | tee -a "$LOG_FILE"
                find "$temp_dir/converted" -type f -name "*.mp3" | sort > "$temp_dir/converted/list.txt"
                
                # Use mp3wrap or direct ffmpeg as last resort
                if command -v mp3wrap &>/dev/null; then
                    echo "Using mp3wrap to combine files..." | tee -a "$LOG_FILE"
                    mp3wrap "$temp_dir/combined.mp3" $(cat "$temp_dir/converted/list.txt")
                else
                    echo "Using ffmpeg to append files sequentially..." | tee -a "$LOG_FILE"
                    # Process files one by one
                    cp "$(head -n 1 "$temp_dir/converted/list.txt")" "$temp_dir/combined.mp3"
                    
                    # Skip the first file since we already copied it
                    tail -n +2 "$temp_dir/converted/list.txt" | while read -r file; do
                        # Create a temporary file for the concatenation
                        ffmpeg -i "$temp_dir/combined.mp3" -i "$file" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" \
                               -c:a libmp3lame -q:a 4 "$temp_dir/combined_temp.mp3" 2>/dev/null
                        # Replace the combined file with the new one
                        mv "$temp_dir/combined_temp.mp3" "$temp_dir/combined.mp3"
                    done
                fi
                
                # Convert the combined file to m4b
                # Create a direct list first
                echo "file '$temp_dir/combined.mp3'" > "$temp_dir/final_input.txt"
                
                # Try with the concat demuxer first (most reliable)
                ffmpeg -f concat -safe 0 -i "$temp_dir/final_input.txt" \
                       -c:a aac -b:a 64k \
                       -metadata title="$title" \
                       -metadata artist="$author" \
                       "$temp_output_file" 2>>"$stderr_file"
                
                # If that fails, try direct input as last resort
                if [ $? -ne 0 ]; then
                    echo "Final method attempt one failed, trying direct input..." | tee -a "$LOG_FILE"
                    ffmpeg -i "$temp_dir/combined.mp3" \
                           -c:a aac -b:a 64k \
                           -metadata title="$title" \
                           -metadata artist="$author" \
                           "$temp_output_file" 2>>"$stderr_file"
                fi
                       
                # Update result
                ffmpeg_result=$?
            fi
        fi
        
        # Final result already stored in ffmpeg_result variable
        
        # Signal progress indicator to stop
        touch "${progress_file}.done" 2>/dev/null
        
        # Wait for progress indicator to exit
        wait $progress_pid 2>/dev/null
        progress_pid=""
        
        # Check ffmpeg result
        if [ $ffmpeg_result -ne 0 ]; then
            echo "ERROR: ffmpeg command failed with exit code $ffmpeg_result" | tee -a "$LOG_FILE"
            
            # Show more detailed error information to help diagnose issues
            if [ -f "$stderr_file" ]; then
                echo "----- ffmpeg error output -----" | tee -a "$LOG_FILE"
                tail -n 20 "$stderr_file" | tee -a "$LOG_FILE"
                echo "----- end ffmpeg error output -----" | tee -a "$LOG_FILE"
            fi
            
            # Check for common issues
            if grep -q "Permission denied" "$stderr_file" 2>/dev/null; then
                echo "ERROR: Permission issues detected. Make sure you have write access to the output directory." | tee -a "$LOG_FILE"
            elif grep -q "No such file or directory" "$stderr_file" 2>/dev/null; then
                echo "ERROR: Some files or directories could not be accessed. This may be due to special characters in filenames." | tee -a "$LOG_FILE"
            elif grep -q "Invalid data found when processing input" "$stderr_file" 2>/dev/null; then
                echo "ERROR: Some audio files may be corrupted or in an unsupported format." | tee -a "$LOG_FILE"
            fi
            
            echo "RECOMMENDATION: Try processing this audiobook manually or rename the files to remove special characters." | tee -a "$LOG_FILE"
            echo "Skipping this audiobook" | tee -a "$LOG_FILE"
            rm -rf "$temp_dir"
            return
        fi
    fi
    
    # Prepare final output path in the processed directory
    local sanitized_author=$(sanitize_filename "$author")
    local sanitized_title=$(sanitize_filename "$title")
    local output_filename="${sanitized_author} - ${sanitized_title}.m4b"
    
    # For existing m4b file, use that as the source
    local final_output_file="$processed_dir/$output_filename"
    if [ -n "$existing_m4b" ]; then
        temp_output_file="$existing_m4b"
    fi
    
    # Check if output file was created
    if [ -f "$temp_output_file" ]; then
        echo "Successfully created: $temp_output_file" >> "$LOG_FILE"
        
        # Ensure output directory exists
        local final_output_dir=$(dirname "$final_output_file")
        if [ ! -d "$final_output_dir" ]; then
            mkdir -p "$final_output_dir" || {
                echo "Error: Failed to create output directory: $final_output_dir" | tee -a "$LOG_FILE"
                echo "Will try to save in the original directory instead" | tee -a "$LOG_FILE"
                final_output_file="$book_dir/$(basename "$final_output_file")"
            }
        fi
        
        # Move the file to final location
        mv "$temp_output_file" "$final_output_file" || {
            echo "Error: Failed to move output file to $final_output_file" | tee -a "$LOG_FILE"
            echo "Output file remains at: $temp_output_file" | tee -a "$LOG_FILE"
            final_output_file="$temp_output_file"
        }
        
        echo "Created: $final_output_file"
        echo "Moved file to: $final_output_file" >> "$LOG_FILE"
        
        # Get file info
        local file_info=$(mediainfo "$final_output_file")
        echo "File info:" | tee -a "$LOG_FILE"
        echo "$file_info" | grep -E "Complete name|Format|Duration|Title|Performer|Album" | tee -a "$LOG_FILE"
        
        # Clean up original files if requested
        if [ "$KEEP_ORIGINAL_FILES" = false ]; then
            echo "Cleaning up original audio files..." >> "$LOG_FILE"
            # Store the files we'll delete in a variable for safety (using standard find for better compatibility)
            local original_files=$(find "$book_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" -o -name "*.wav" -o -name "*.aac" \) 2>/dev/null)
            
            # Debug info about files
            echo "DEBUG: Found these audio files:" >> "$LOG_FILE"
            echo "$original_files" >> "$LOG_FILE"
            
            # Count files to delete (ignore empty lines)
            local file_count=0
            if [ -n "$original_files" ]; then
                file_count=$(echo "$original_files" | grep -v '^$' | wc -l)
            fi
            echo "Found $file_count original audio files to clean up" | tee -a "$LOG_FILE"
            
            # Only delete if we have a successful m4b AND at least one original file
            if [ -f "$final_output_file" ] && [ "$file_count" -gt 0 ]; then
                # Verify the m4b file has a reasonable size compared to original files
                local m4b_size=0
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    m4b_size=$(stat -f %z "$final_output_file" 2>/dev/null || echo 0)
                else
                    m4b_size=$(stat -c %s "$final_output_file" 2>/dev/null || echo 0)
                fi
                
                local total_original_size=0
                for file in $original_files; do
                    if [ -n "$file" ] && [ -f "$file" ]; then
                        local file_size=0
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            file_size=$(stat -f %z "$file" 2>/dev/null || echo 0)
                            echo "DEBUG: File $file size: $file_size bytes" >> "$LOG_FILE"
                        else
                            file_size=$(stat -c %s "$file" 2>/dev/null || echo 0)
                            echo "DEBUG: File $file size: $file_size bytes" >> "$LOG_FILE"
                        fi
                        total_original_size=$((total_original_size + file_size))
                    elif [ -n "$file" ]; then
                        echo "DEBUG: Found in list but not a file: $file" >> "$LOG_FILE"
                    fi
                done
                
                # Ensure the m4b is at least 50% the size of the original files
                # This is a failsafe to prevent deleting originals if the m4b is corrupted
                if [ $m4b_size -gt 0 ] && [ $total_original_size -gt 0 ] && [ $m4b_size -gt $((total_original_size / 2)) ]; then
                    echo "M4B file size ($m4b_size bytes) is reasonable compared to originals ($total_original_size bytes)" | tee -a "$LOG_FILE"
                    echo "Removing original audio files..." | tee -a "$LOG_FILE"
                    
                    # Delete each file individually for better control
                    echo "Removing original files..." 
                    local deleted_count=0
                    for file in $original_files; do
                        if [ -f "$file" ]; then
                            if rm "$file" 2>/dev/null; then
                                echo "Deleted: $file" >> "$LOG_FILE"
                                deleted_count=$((deleted_count + 1))
                            else
                                echo "Failed to delete: $file" >> "$LOG_FILE"
                            fi
                        fi
                    done
                    
                    if [ $deleted_count -gt 0 ]; then
                        echo "Original files cleaned up successfully ($deleted_count files deleted)" >> "$LOG_FILE"
                    else
                        echo "Warning: Failed to delete any original files" >> "$LOG_FILE"
                    fi
                    
                    # Optionally, try to remove the directory if it's empty
                    if [ "$book_dir" != "$AUDIOBOOKS_DIR" ]; then
                        if [ -z "$(ls -A "$book_dir")" ]; then
                            echo "Directory is now empty, attempting to remove it" >> "$LOG_FILE"
                            rmdir "$book_dir" 2>/dev/null && echo "Removed empty directory: $book_dir" >> "$LOG_FILE"
                        fi
                    fi
                else
                    echo "WARNING: M4B file size ($m4b_size bytes) is too small compared to originals ($total_original_size bytes)" | tee -a "$LOG_FILE"
                    echo "Keeping original files as a precaution" | tee -a "$LOG_FILE"
                fi
            else
                echo "No original files to clean up, or m4b file not found" | tee -a "$LOG_FILE"
            fi
        else
            echo "Keeping original files (--keep-original-files flag is set)" | tee -a "$LOG_FILE"
        fi
    else
        echo "Failed to create $temp_output_file" | tee -a "$LOG_FILE"
    fi
    
    # Clean up temporary directory
    chmod -R +w "$temp_dir" 2>/dev/null
    rm -rf "$temp_dir" 2>/dev/null
    
    # If the directory still exists, try a more forceful approach
    if [ -d "$temp_dir" ]; then
        echo "Warning: Could not remove temp directory using standard method, trying alternative..." >> "$LOG_FILE"
        find "$temp_dir" -type f -exec rm -f {} \; 2>/dev/null
        find "$temp_dir" -type d -empty -delete 2>/dev/null
        rmdir "$temp_dir" 2>/dev/null
        
        # If still exists, just warn but continue
        if [ -d "$temp_dir" ]; then
            echo "Warning: Temp directory could not be fully cleaned up: $temp_dir" >> "$LOG_FILE"
        fi
    fi
    echo "Processing completed for: $book_name" | tee -a "$LOG_FILE"
    echo "-------------------------------------------" | tee -a "$LOG_FILE"
}

# Main script execution
echo "Starting recursive audiobook processing in $AUDIOBOOKS_DIR"
echo "Starting recursive audiobook processing in $AUDIOBOOKS_DIR" >> "$LOG_FILE"
if [ "$KEEP_ORIGINAL_FILES" = true ]; then
    echo "Original files will be kept after processing (--keep-original-files flag is set)"
    echo "Original files will be kept after processing (--keep-original-files flag is set)" >> "$LOG_FILE"
else
    echo "Original files will be removed after successful m4b conversion"
    echo "Original files will be removed after successful m4b conversion" >> "$LOG_FILE"
fi
echo "Will search all nested directories for audio files automatically"
echo "Will search all nested directories for audio files automatically" >> "$LOG_FILE"
echo "-------------------------------------------" >> "$LOG_FILE"

# Shared array to keep track of processed books
declare -a processed_books

# Function to check if a directory has already been processed
is_book_processed() {
    local check_dir="$1"
    local check_dir_canonical=$(cd "$check_dir" 2>/dev/null && pwd -P)
    
    # If we can't get canonical path, use original
    if [ -z "$check_dir_canonical" ]; then
        check_dir_canonical="$check_dir"
    fi
    
    # Check if we're already processing this directory in this run
    # (prevents infinite recursion but allows multiple books per run)
    for dir in "${processed_books[@]}"; do
        local dir_canonical=$(cd "$dir" 2>/dev/null && pwd -P)
        if [ -z "$dir_canonical" ]; then
            dir_canonical="$dir"
        fi
        
        if [ "$dir_canonical" = "$check_dir_canonical" ]; then
            echo "Directory already processed in this run: $(basename "$check_dir")" >> "$LOG_FILE"
            return 0 # Already processed
        fi
    done
    
    # Check for already processed m4b file in the processed directory
    local dir_name=$(basename "$check_dir")
    if ls "$AUDIOBOOKS_DIR/processed/$dir_name.m4b" 2>/dev/null || ls "$AUDIOBOOKS_DIR/processed/${dir_name}*.m4b" 2>/dev/null; then
        echo "Directory already has a processed m4b file in the output directory" >> "$LOG_FILE"
        return 0 # Mark as processed to prevent reprocessing
    fi
    
    return 1 # Not processed yet
}

# Function to process directories recursively
process_directory() {
    local dir="$1"
    local level="$2"
    local indent=$(printf '%*s' "$level" '')
    
    local dir_name=$(basename "$dir")
    
    # Skip if this directory already processed (avoid duplicate processing)
    if is_book_processed "$dir"; then
        echo "${indent}Directory already processed, skipping: $dir_name" >> "$LOG_FILE"
        return
    fi
    
    # Debug info
    echo "${indent}Checking directory: $dir_name" >> "$LOG_FILE"
    
    # Check if directory contains audio files using standard find (more compatible than fd)
    local has_audio_files=false
    local audio_files_result=$(find "$dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" -o -name "*.wav" -o -name "*.aac" \) 2>/dev/null)
    echo "${indent}DEBUG: Audio files found in $dir_name:" >> "$LOG_FILE"
    echo "$audio_files_result" >> "$LOG_FILE"
    
    if [ -n "$audio_files_result" ] && echo "$audio_files_result" | grep -q .; then
        has_audio_files=true
        echo "${indent}DEBUG: has_audio_files set to true" >> "$LOG_FILE"
    else
        echo "${indent}DEBUG: has_audio_files set to false" >> "$LOG_FILE"
    fi
    
    # Check if directory already has an m4b file
    local has_m4b_files=false
    local m4b_files=""
    if m4b_files=$(find "$dir" -maxdepth 1 -name "*.m4b" 2>/dev/null); then
        echo "${indent}DEBUG: m4b files found in $dir_name:" >> "$LOG_FILE"
        echo "$m4b_files" >> "$LOG_FILE"
        
        if [ -n "$m4b_files" ] && [ -z "${m4b_files//[[:space:]]/}" ]; then
            echo "${indent}DEBUG: m4b_files contains only whitespace" >> "$LOG_FILE"
            m4b_files=""
        fi
        
        if [ -n "$m4b_files" ]; then
            has_m4b_files=true
            echo "${indent}DEBUG: has_m4b_files set to true" >> "$LOG_FILE"
        else
            echo "${indent}DEBUG: has_m4b_files set to false" >> "$LOG_FILE"
        fi
    else
        echo "${indent}DEBUG: find command for m4b files failed" >> "$LOG_FILE"
    fi
    
    # Process if we have audio files OR m4b files
    if [ "$has_audio_files" = true ] || [ "$has_m4b_files" = true ]; then
        if [ "$has_audio_files" = true ]; then
            echo "Found audiobook with audio files: $dir_name"
            echo "${indent}Found audio files in $dir_name" >> "$LOG_FILE"
        elif [ "$has_m4b_files" = true ]; then
            echo "Found existing m4b audiobook: $dir_name"
            echo "${indent}Found existing m4b files in $dir_name" >> "$LOG_FILE"
        fi
        
        # Always process the audiobook, even if it's an m4b
        # The process_audiobook function will handle checking if it's already processed
        process_audiobook "$dir"
    fi
    
    # Always check subdirectories regardless of whether we processed this directory or not
    # This ensures we continue processing all directories in the hierarchy
    if find "$dir" -mindepth 1 -maxdepth 1 -type d -not -path "*/temp_processing*" | grep -q .; then
        local subdirs_count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -path "*/temp_processing*" | wc -l)
        
        # Only show scanning message if we have subdirectories to process
        if [ $subdirs_count -gt 0 ]; then
            echo "Scanning folder: $dir_name ($subdirs_count subdirectories)"
            echo "${indent}Found $subdirs_count subdirectories in $dir_name, processing each..." >> "$LOG_FILE"
            
            # Use find to get subdirectories but process them in a separate loop to prevent subshell issues
            # Compatible approach for older bash versions that don't have readarray
            local subdirs=()
            while IFS= read -r line; do
                subdirs+=("$line")
            done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -path "*/temp_processing*")
            
            for subdir in "${subdirs[@]}"; do
                process_directory "$subdir" $((level + 2))
            done
        else
            echo "${indent}No subdirectories found in $dir_name" >> "$LOG_FILE"
        fi
    else
        echo "${indent}No subdirectories found in $dir_name" >> "$LOG_FILE"
    fi
}

# Main directory processing - use array instead of pipe to prevent subshell issues
# Compatible approach for older bash versions that don't have readarray
top_dirs=()
while IFS= read -r line; do
    top_dirs+=("$line")
done < <(find "$AUDIOBOOKS_DIR" -mindepth 1 -maxdepth 1 -type d -not -path "*/temp_processing*")

# Count total top-level directories
echo "Found ${#top_dirs[@]} top-level directories to process"
echo "Found ${#top_dirs[@]} top-level directories to process" >> "$LOG_FILE"

# Process each top directory
for dir in "${top_dirs[@]}"; do
    process_directory "$dir" 0
done

echo "Batch processing completed. Check $LOG_FILE for details."
echo "Batch processing completed. Check $LOG_FILE for details." >> "$LOG_FILE"

# Generate summary report
echo "-------------------------------------------" >> "$LOG_FILE"
echo "Processing Summary:" >> "$LOG_FILE"
processed_count=$(grep -c "Processing completed for:" "$LOG_FILE")
m4b_count=$(find "$AUDIOBOOKS_DIR" -type f -name "*.m4b" | wc -l)
checked_dirs=$(grep -c "Checking directory:" "$LOG_FILE")
echo "Total directories checked: $checked_dirs" >> "$LOG_FILE"
echo "Total audiobooks processed: $processed_count" >> "$LOG_FILE"
echo "Total m4b files: $m4b_count" >> "$LOG_FILE"
echo "-------------------------------------------" >> "$LOG_FILE"
echo "Finished. Audio books processed in: $AUDIOBOOKS_DIR" >> "$LOG_FILE"

# Show concise summary to the user
echo "-------------------------------------------"
echo "Processing Summary: $processed_count audiobooks processed"
echo "Scanned $checked_dirs directories, created $m4b_count m4b files"
echo "Finished. See $LOG_FILE for details."