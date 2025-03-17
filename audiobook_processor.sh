#!/bin/bash

# Audiobook Batch Processor for macOS
# This script processes a folder of audiobooks:
# - Sets proper metadata
# - Detects chapters
# - Converts to m4b format

# Prerequisites:
# brew install ffmpeg mp4v2 fd jq mediainfo python3
# pip3 install requests beautifulsoup4 fuzzywuzzy

# Usage: ./audiobook_processor.sh /path/to/audiobooks/folder

set -e

AUDIOBOOKS_DIR="$1"
OUTPUT_DIR="${2:-"$AUDIOBOOKS_DIR/processed"}"
LOG_FILE="$AUDIOBOOKS_DIR/processing_log.txt"

# Check if directory was provided
if [ -z "$AUDIOBOOKS_DIR" ]; then
    echo "Please provide the path to your audiobooks directory"
    echo "Usage: ./audiobook_processor.sh /path/to/audiobooks/folder [/path/to/output/folder]"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Create standard folder structure in output directory
mkdir -p "$OUTPUT_DIR/Fiction"
mkdir -p "$OUTPUT_DIR/Fiction/Fantasy"
mkdir -p "$OUTPUT_DIR/Fiction/Science Fiction"
mkdir -p "$OUTPUT_DIR/Fiction/Mystery & Thriller"
mkdir -p "$OUTPUT_DIR/Fiction/Historical"
mkdir -p "$OUTPUT_DIR/Fiction/Romance"
mkdir -p "$OUTPUT_DIR/Fiction/General"
mkdir -p "$OUTPUT_DIR/Non-Fiction"
mkdir -p "$OUTPUT_DIR/Non-Fiction/History"
mkdir -p "$OUTPUT_DIR/Non-Fiction/Science"
mkdir -p "$OUTPUT_DIR/Non-Fiction/Self-Help"
mkdir -p "$OUTPUT_DIR/Non-Fiction/Biography"
mkdir -p "$OUTPUT_DIR/Non-Fiction/Business"
mkdir -p "$OUTPUT_DIR/Non-Fiction/General"
mkdir -p "$OUTPUT_DIR/Children"
mkdir -p "$OUTPUT_DIR/Series"
mkdir -p "$OUTPUT_DIR/Unsorted"

# Initialize log file
echo "Audiobook Processing Log - $(date)" > "$LOG_FILE"

# Function to sanitize filenames
sanitize_filename() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Function to extract metadata from filename patterns
extract_filename_metadata() {
    local filename="$1"
    local metadata=()
    
    # Remove file extension
    filename=$(basename "$filename")
    filename="${filename%.*}"
    
    # Common patterns to check:
    
    # Pattern 1: Author - Title (Year)
    if [[ "$filename" =~ (.+)\ -\ (.+)\ \(([0-9]{4})\) ]]; then
        metadata[0]="${BASH_REMATCH[1]}" # Author
        metadata[1]="${BASH_REMATCH[2]}" # Title
        metadata[2]="${BASH_REMATCH[3]}" # Year
        return 0
    fi
    
    # Pattern 2: Author - Series Name #X - Title
    if [[ "$filename" =~ (.+)\ -\ (.+)\ #([0-9]+(\.[0-9]+)?)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[1]}" # Author
        metadata[1]="${BASH_REMATCH[5]}" # Title
        metadata[3]="${BASH_REMATCH[2]}" # Series
        metadata[4]="${BASH_REMATCH[3]}" # Series part
        return 0
    fi
    
    # Pattern 3: Author - Series Name Book X - Title
    if [[ "$filename" =~ (.+)\ -\ (.+)\ Book\ ([0-9]+(\.[0-9]+)?)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[1]}" # Author
        metadata[1]="${BASH_REMATCH[5]}" # Title
        metadata[3]="${BASH_REMATCH[2]}" # Series
        metadata[4]="${BASH_REMATCH[3]}" # Series part
        return 0
    fi
    
    # Pattern 4: Title - Author - Narrator
    if [[ "$filename" =~ (.+)\ -\ (.+)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[2]}" # Author
        metadata[1]="${BASH_REMATCH[1]}" # Title
        metadata[5]="${BASH_REMATCH[3]}" # Narrator
        return 0
    fi
    
    # Pattern 5: Title (Year) - Author
    if [[ "$filename" =~ (.+)\ \(([0-9]{4})\)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[3]}" # Author
        metadata[1]="${BASH_REMATCH[1]}" # Title
        metadata[2]="${BASH_REMATCH[2]}" # Year
        return 0
    fi
    
    # Pattern 6: Author - Series Name - Book X - Title
    if [[ "$filename" =~ (.+)\ -\ (.+)\ -\ Book\ ([0-9]+(\.[0-9]+)?)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[1]}" # Author
        metadata[1]="${BASH_REMATCH[5]}" # Title
        metadata[3]="${BASH_REMATCH[2]}" # Series
        metadata[4]="${BASH_REMATCH[3]}" # Series part
        return 0
    fi
    
    # Pattern 7: Title - The Series Name X - Author
    if [[ "$filename" =~ (.+)\ -\ The\ (.+)\ ([0-9]+(\.[0-9]+)?)\ -\ (.+) ]]; then
        metadata[0]="${BASH_REMATCH[5]}" # Author
        metadata[1]="${BASH_REMATCH[1]}" # Title
        metadata[3]="The ${BASH_REMATCH[2]}" # Series
        metadata[4]="${BASH_REMATCH[3]}" # Series part
        return 0
    fi
    
    # Pattern 8: "NN - Title - Author - Year" (for collections like "Top 100 Science Fiction")
    if [[ "$filename" =~ ^([0-9]+)\ -\ (.+)\ -\ (.+)\ -\ ([0-9]{4})$ ]]; then
        metadata[0]="${BASH_REMATCH[3]}" # Author
        metadata[1]="${BASH_REMATCH[2]}" # Title
        metadata[2]="${BASH_REMATCH[4]}" # Year
        return 0
    fi
    
    # If no pattern matches, return 1 (false)
    return 1
}

# Function to process a single audiobook folder
process_audiobook() {
    local book_dir="$1"
    local book_name=$(basename "$book_dir")
    
    echo "Processing: $book_name" | tee -a "$LOG_FILE"
    
    # Create a temporary directory for processing
    local temp_dir="$book_dir/temp_processing"
    
    # Check if temp directory already exists (from a previous failed run)
    if [ -d "$temp_dir" ]; then
        echo "Found existing temp directory, cleaning up first..." | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
    fi
    
    mkdir -p "$temp_dir"
    
    # Step 1: Gather audiobook files (mp3, m4a, flac, etc.)
    echo "Gathering audio files..." | tee -a "$LOG_FILE"
    # Use a temp file to store the file list to avoid issues with newlines and spaces
    local files_temp="$temp_dir/audio_files_list.txt"
    fd -e mp3 -e m4a -e flac -e wav -e aac . "$book_dir" --exclude "$temp_dir" | sort > "$files_temp"
    local audio_files=$(cat "$files_temp")
    
    # Debug audio files found
    echo "Debug - Audio files found: $(wc -l < "$files_temp") files" | tee -a "$LOG_FILE"
    
    if [ -z "$audio_files" ]; then
        echo "No audio files found in $book_dir" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return
    fi
    
    # Step 2: Extract metadata from various sources
    echo "=== PHASE 1: METADATA EXTRACTION ===" | tee -a "$LOG_FILE"
    
    # Initialize metadata variables
    local author=""
    local title=""
    local narrator=""
    local series=""
    local series_part=""
    local year=""
    local genre="Audiobook"
    local description=""
    local cover_art=""
    
    # Track metadata sources for logging
    local author_source=""
    local title_source=""
    local series_source=""
    local narrator_source=""
    
    # 2.1: First attempt - directory name
    echo "Checking directory name pattern: $book_name" | tee -a "$LOG_FILE"
    
    # Special pattern for numbered collections (e.g., "51 - Battlefield Earth - L Ron Hubbard - 1982")
    if [[ "$book_name" =~ ^([0-9]+)\ -\ (.+)\ -\ (.+)\ -\ ([0-9]{4})$ ]]; then
        title="${BASH_REMATCH[2]}"
        author="${BASH_REMATCH[3]}"
        year="${BASH_REMATCH[4]}"
        title_source="directory name (collection)"
        author_source="directory name (collection)"
        echo "- Found title from collection directory: $title" | tee -a "$LOG_FILE"
        echo "- Found author from collection directory: $author" | tee -a "$LOG_FILE"
        echo "- Found year from collection directory: $year" | tee -a "$LOG_FILE"
    # Handle regular directory name patterns with dashes
    elif [[ "$book_name" == *" - "* ]]; then
        # Handle cases where directory name might contain series information
        if [[ "$book_name" =~ (.+)\ -\ (.+)\ -\ (.+) ]]; then
            # Pattern matches Author - Series - Title or similar
            author=$(echo "$book_name" | cut -d '-' -f 1 | xargs)
            series=$(echo "$book_name" | cut -d '-' -f 2 | xargs)
            title=$(echo "$book_name" | cut -d '-' -f 3- | xargs)
            author_source="directory name"
            title_source="directory name"
            series_source="directory name"
            echo "- Found author from directory: $author" | tee -a "$LOG_FILE"
            echo "- Found series from directory: $series" | tee -a "$LOG_FILE"
            echo "- Found title from directory: $title" | tee -a "$LOG_FILE"
        elif [[ "$book_name" =~ (.+)\ -\ (.+) ]]; then
            # Simple Author - Title pattern
            author=$(echo "$book_name" | cut -d '-' -f 1 | xargs)
            title=$(echo "$book_name" | cut -d '-' -f 2- | xargs)
            author_source="directory name"
            title_source="directory name"
            echo "- Found author from directory: $author" | tee -a "$LOG_FILE"
            echo "- Found title from directory: $title" | tee -a "$LOG_FILE"
            
            # Check if title might actually be a series name without a specific title
            if [[ "$title" =~ (Series|Cycle|Trilogy|Universe|Verse)$ ]]; then
                echo "- Title appears to be a series name without a specific book title" | tee -a "$LOG_FILE"
                series="$title"
                title="$title Complete Series" # Set a default title for series-only names
                series_source="directory name"
                echo "- Treating as series: $series" | tee -a "$LOG_FILE"
                echo "- Setting default title: $title" | tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    # 2.2: Second attempt - Advanced pattern matching on filenames
    local first_file=$(echo "$audio_files" | head -n 1)
    local filename=$(basename "$first_file")
    
    echo "Checking filename pattern: $filename" | tee -a "$LOG_FILE"
    
    # Try to extract metadata from filename patterns
    local file_metadata=()
    if extract_filename_metadata "$filename"; then
        if [ -n "${file_metadata[0]}" ] && ([ -z "$author" ] || [ "$author_source" != "user input" ]); then 
            author="${file_metadata[0]}"
            author_source="filename pattern"
            echo "- Found author from filename: $author" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "${file_metadata[1]}" ] && ([ -z "$title" ] || [ "$title_source" != "user input" ]); then 
            title="${file_metadata[1]}" 
            title_source="filename pattern"
            echo "- Found title from filename: $title" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "${file_metadata[2]}" ]; then 
            year="${file_metadata[2]}"
            echo "- Found year from filename: $year" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "${file_metadata[3]}" ]; then 
            series="${file_metadata[3]}"
            series_source="filename pattern"
            echo "- Found series from filename: $series" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "${file_metadata[4]}" ]; then 
            series_part="${file_metadata[4]}"
            echo "- Found series part from filename: $series_part" | tee -a "$LOG_FILE"
        fi
        
        if [ -n "${file_metadata[5]}" ]; then 
            narrator="${file_metadata[5]}"
            narrator_source="filename pattern"
            echo "- Found narrator from filename: $narrator" | tee -a "$LOG_FILE"
        fi
    else
        echo "- No filename pattern matched" | tee -a "$LOG_FILE"
    fi
    
    # 2.3: Check file metadata tags
    echo "Checking file metadata tags from: $first_file" | tee -a "$LOG_FILE"
    local file_tags=$(ffprobe -v quiet -print_format json -show_format "$first_file")
    
    # Only replace if our values are empty or from a lower priority source
    if [ -z "$author" ] || [ "$author_source" == "directory name" ]; then
        local tag_author=$(echo "$file_tags" | jq -r '.format.tags.artist // .format.tags.ARTIST // .format.tags.Author // ""')
        if [ -n "$tag_author" ]; then 
            author="$tag_author"
            author_source="file tags"
            echo "- Found author from tags: $author" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$title" ] || [ "$title_source" == "directory name" ]; then
        local tag_title=$(echo "$file_tags" | jq -r '.format.tags.title // .format.tags.TITLE // .format.tags.album // .format.tags.ALBUM // ""')
        if [ -n "$tag_title" ]; then 
            title="$tag_title"
            title_source="file tags"
            echo "- Found title from tags: $title" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$narrator" ]; then
        local tag_narrator=$(echo "$file_tags" | jq -r '.format.tags.composer // .format.tags.COMPOSER // ""')
        if [ -n "$tag_narrator" ]; then 
            narrator="$tag_narrator"
            narrator_source="file tags"
            echo "- Found narrator from tags: $narrator" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$series" ]; then
        local tag_series=$(echo "$file_tags" | jq -r '.format.tags.show // .format.tags.SHOW // ""')
        if [ -n "$tag_series" ]; then 
            series="$tag_series"
            series_source="file tags"
            echo "- Found series from tags: $series" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$series_part" ]; then
        local tag_series_part=$(echo "$file_tags" | jq -r '.format.tags.episode_id // .format.tags.EPISODE_ID // ""')
        if [ -n "$tag_series_part" ]; then 
            series_part="$tag_series_part"
            echo "- Found series part from tags: $series_part" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$year" ]; then
        local tag_year=$(echo "$file_tags" | jq -r '.format.tags.date // .format.tags.DATE // ""')
        if [ -n "$tag_year" ]; then 
            year="$tag_year"
            echo "- Found year from tags: $year" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ -z "$genre" ] || [ "$genre" == "Audiobook" ]; then
        local tag_genre=$(echo "$file_tags" | jq -r '.format.tags.genre // .format.tags.GENRE // ""')
        if [ -n "$tag_genre" ] && [ "$tag_genre" != "Audiobook" ]; then
            genre="$tag_genre"
            echo "- Found genre from tags: $genre" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Check parent directory for additional context (like collection or genre information)
    local parent_dir=$(dirname "$book_dir")
    local parent_name=$(basename "$parent_dir")
    echo "Checking parent directory: $parent_name" | tee -a "$LOG_FILE"
    
    # If the parent directory is a collection (e.g., "Top 100 Science Fiction")
    if [[ "$parent_name" =~ [Tt]op|[Bb]est|[Cc]ollection|[Cc]ompilation|[Aa]nthology ]]; then
        echo "- Parent directory appears to be a collection: $parent_name" | tee -a "$LOG_FILE"
        
        # Try to extract genre information from parent directory name
        if [[ "$parent_name" =~ [Ss]cience[[:space:]]*[Ff]iction ]]; then
            genre="Science Fiction"
            echo "- Found genre from parent directory: $genre" | tee -a "$LOG_FILE"
        elif [[ "$parent_name" =~ [Ff]antasy ]]; then
            genre="Fantasy"
            echo "- Found genre from parent directory: $genre" | tee -a "$LOG_FILE"
        elif [[ "$parent_name" =~ [Mm]ystery|[Tt]hriller|[Dd]etective ]]; then
            genre="Mystery & Thriller"
            echo "- Found genre from parent directory: $genre" | tee -a "$LOG_FILE"
        elif [[ "$parent_name" =~ [Hh]orror ]]; then
            genre="Horror"
            echo "- Found genre from parent directory: $genre" | tee -a "$LOG_FILE"
        elif [[ "$parent_name" =~ [Hh]istorical|[Hh]istory ]]; then
            genre="Historical"
            echo "- Found genre from parent directory: $genre" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Special handling for directories that might just be series names or authors
    
    # First check for the specific case "Author - SeriesName" (like "Charles Stross - Freyaverse")
    if [[ "$book_name" =~ ^([^-]+)\ -\ ([^-]+)$ ]] && [ -z "$title" ]; then
        # This is likely an "Author - Series" format with no book title
        potential_author=$(echo "$book_name" | cut -d '-' -f 1 | xargs)
        potential_series=$(echo "$book_name" | cut -d '-' -f 2 | xargs)
        
        echo "- Detected potential Author - Series pattern: $potential_author - $potential_series" | tee -a "$LOG_FILE"
        
        # Use this metadata if we don't already have author/series
        if [ -z "$author" ] || [ "$author_source" != "user input" ]; then
            author="$potential_author"
            author_source="directory pattern analysis"
            echo "- Setting author from directory pattern: $author" | tee -a "$LOG_FILE"
        fi
        
        if [ -z "$series" ] || [ "$series_source" != "user input" ]; then
            series="$potential_series"
            series_source="directory pattern analysis"
            echo "- Setting series from directory pattern: $series" | tee -a "$LOG_FILE"
        fi
        
        # Create a default title based on the series
        if [ -z "$title" ]; then
            title="$series Complete Series"
            title_source="derived from series"
            echo "- Setting default title for series: $title" | tee -a "$LOG_FILE"
        fi
    # Also check for series name patterns in the directory name
    elif [ -z "$series" ] && [[ "$book_name" =~ [Vv]erse$|[Cc]ycle$|[Ss]eries$|[Tt]rilogy$|[Ss]aga$ ]]; then
        if [ -n "$author" ]; then
            # If we already have an author but no series, the directory might be a series name
            series="$book_name"
            series_source="directory name analysis"
            echo "- Detected series name from directory: $series" | tee -a "$LOG_FILE"
            
            # If we don't have a title yet, create a default one
            if [ -z "$title" ]; then
                title="$series Complete Series"
                title_source="derived from series"
                echo "- Setting default title for series: $title" | tee -a "$LOG_FILE"
            fi
        fi
    fi

    # If still missing critical metadata, ask user or use defaults for testing
    if [ -z "$author" ]; then
        if [ -n "$AUDIOBOOKS_NON_INTERACTIVE" ]; then
            # In non-interactive mode, use "Unknown Author" as default
            author="Unknown Author"
            author_source="default value"
            echo "- Using default author: $author" | tee -a "$LOG_FILE"
        else
            echo "Could not determine author for $book_name"
            echo "Please enter author name (or press Enter to skip): "
            read author_input
            if [ -n "$author_input" ]; then
                author="$author_input"
                author_source="user input"
                echo "- Author set by user: $author" | tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    if [ -z "$title" ]; then
        # If we have the author but no title, try using directory name minus author
        if [ -n "$author" ] && [[ "$book_name" == *"$author"* ]]; then
            title=$(echo "$book_name" | sed "s/$author//g" | sed 's/^[ \-]*//g' | sed 's/[ \-]*$//g')
            if [ -n "$title" ]; then
                title_source="derived from directory"
                echo "- Derived title from directory: $title" | tee -a "$LOG_FILE"
            fi
        # If we have series but no title, use series as part of title
        elif [ -n "$series" ] && [ -z "$title" ]; then
            title="$series"
            if [ -n "$series_part" ]; then
                title="$series $series_part"
            else
                title="$series Complete Series"
            fi
            title_source="derived from series"
            echo "- Derived title from series: $title" | tee -a "$LOG_FILE"
        fi
        
        # If still no title, prompt user or use default
        if [ -z "$title" ]; then
            if [ -n "$AUDIOBOOKS_NON_INTERACTIVE" ]; then
                # In non-interactive mode, use "Unknown Title" as default
                title="Unknown Title"
                title_source="default value"
                echo "- Using default title: $title" | tee -a "$LOG_FILE"
            else
                echo "Could not determine title for $book_name"
                echo "Please enter title (or press Enter to skip): "
                read title_input
                if [ -n "$title_input" ]; then
                    title="$title_input"
                    title_source="user input"
                    echo "- Title set by user: $title" | tee -a "$LOG_FILE"
                fi
            fi
        fi
    fi
    
    # 2.4: Search for cover art in the directory
    echo "Searching for cover art..." | tee -a "$LOG_FILE"
    for img in $(find "$book_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -not -path "$temp_dir/*"); do
        # Check if filename contains words like cover, folder, front
        if [[ "$(basename "$img" | tr '[:upper:]' '[:lower:]')" =~ (cover|folder|front|artwork) ]]; then
            cover_art="$img"
            echo "- Found cover art with preferred name: $(basename "$cover_art")" | tee -a "$LOG_FILE"
            break
        fi
    done
    
    # If we haven't found cover art with preferred name, just use the first image
    if [ -z "$cover_art" ]; then
        for img in $(find "$book_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -not -path "$temp_dir/*" | head -n 1); do
            if [ -n "$img" ]; then
                cover_art="$img"
                echo "- Found cover art: $(basename "$cover_art")" | tee -a "$LOG_FILE"
                break
            fi
        done
    fi
    
    if [ -z "$cover_art" ]; then
        echo "- No cover art found in directory" | tee -a "$LOG_FILE"
    fi
    
    # We skip online lookups if we have both title and author
    local skip_online=false
    if [ -n "$title" ] && [ -n "$author" ]; then
        echo "Book identity established locally: '$title' by '$author'" | tee -a "$LOG_FILE"
        
        # If we also have series info and cover art, we can skip online
        if ([ -n "$series" ] || [ -z "$series" ] && [ -z "$series_part" ]) && [ -n "$cover_art" ]; then
            skip_online=true
            echo "Sufficient metadata found locally, skipping online lookup" | tee -a "$LOG_FILE"
        fi
    fi
    
    # 2.5: Online metadata lookup (if needed)
    if [ "$skip_online" = false ] && [ -n "$title" ] && [ -n "$author" ]; then
        echo "Fetching improved metadata online..." | tee -a "$LOG_FILE"
        
        # Create Python script for metadata lookup
        cat > "$temp_dir/metadata_lookup.py" << 'EOF'
#!/usr/bin/env python3
import sys
import json
import requests
from bs4 import BeautifulSoup
from fuzzywuzzy import fuzz
import re
import time

def clean_text(text):
    return re.sub(r'\s+', ' ', text).strip()

def fetch_goodreads_metadata(title, author):
    metadata = {
        'title': title,
        'author': author,
        'narrator': '',
        'series': '',
        'series_part': '',
        'year': '',
        'description': '',
        'cover_url': '',
        'genres': []  # Added genre field
    }
    
    try:
        # Form search query
        query = f"{title} {author} audiobook"
        search_url = f"https://www.goodreads.com/search?q={query.replace(' ', '+')}"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'
        }
        
        response = requests.get(search_url, headers=headers)
        
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
        
        # Extract metadata
        # Title (already verified through search)
        metadata['title'] = best_match.text.strip()
        
        # Author
        author_elem = book_soup.select_one('.authorName')
        if author_elem:
            metadata['author'] = author_elem.text.strip()
        
        # Series
        series_elem = book_soup.select_one('.seriesTitle')
        if series_elem:
            series_text = series_elem.text.strip()
            # Extract series name and number
            match = re.search(r'#(\d+(\.\d+)?)', series_text)
            if match:
                series_num = match.group(1)
                series_name = series_text.split('#')[0].strip().rstrip(',')
                metadata['series'] = series_name
                metadata['series_part'] = series_num
        
        # Year
        year_elem = book_soup.select_one('[itemprop="datePublished"]')
        if year_elem:
            year_match = re.search(r'\d{4}', year_elem.text)
            if year_match:
                metadata['year'] = year_match.group(0)
        
        # Description
        desc_elem = book_soup.select_one('#description span:nth-of-type(2)')
        if not desc_elem:
            desc_elem = book_soup.select_one('#description span')
        if desc_elem:
            metadata['description'] = clean_text(desc_elem.text)[:500]  # Limit length
        
        # Cover URL
        cover_elem = book_soup.select_one('#coverImage')
        if cover_elem:
            metadata['cover_url'] = cover_elem.get('src')
            
        # Genres
        genre_elems = book_soup.select('.rightContainer .left a.bookPageGenreLink')
        genres = []
        for genre_elem in genre_elems:
            genre = genre_elem.text.strip()
            if genre and genre not in genres and len(genres) < 3:  # Limit to top 3 genres
                genres.append(genre)
        
        metadata['genres'] = genres
        
        return metadata
        
    except Exception as e:
        print(f"Error fetching metadata: {str(e)}", file=sys.stderr)
        return metadata

def fetch_librivox_metadata(title, author):
    # Simplified implementation for LibriVox search
    metadata = {
        'narrator': '',
        'year': '',
        'description': ''
    }
    
    try:
        query = f"{title} {author}"
        search_url = f"https://librivox.org/search?q={query.replace(' ', '+')}&search_form=advanced"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'
        }
        
        response = requests.get(search_url, headers=headers)
        
        if response.status_code != 200:
            return metadata
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Find narrator information
        reader_elem = soup.select_one('.catalog-result .reader')
        if reader_elem:
            metadata['narrator'] = reader_elem.text.replace('Read by:', '').strip()
        
        # Description
        desc_elem = soup.select_one('.catalog-result .book-description')
        if desc_elem:
            metadata['description'] = clean_text(desc_elem.text)[:500]  # Limit length
        
        return metadata
        
    except Exception:
        return metadata

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: metadata_lookup.py <title> <author>")
        sys.exit(1)
    
    title = sys.argv[1]
    author = sys.argv[2]
    
    # First try Goodreads
    metadata = fetch_goodreads_metadata(title, author)
    
    # Try to supplement with LibriVox data if we're missing narrator
    if not metadata.get('narrator'):
        librivox_data = fetch_librivox_metadata(title, author)
        if librivox_data.get('narrator'):
            metadata['narrator'] = librivox_data['narrator']
        if not metadata.get('description') and librivox_data.get('description'):
            metadata['description'] = librivox_data['description']
    
    # Output as JSON
    print(json.dumps(metadata))
EOF
        
        chmod +x "$temp_dir/metadata_lookup.py"
        
        # Run the metadata lookup
        echo "Looking up metadata for '$title' by '$author'..." | tee -a "$LOG_FILE"
        metadata_json=$("$temp_dir/metadata_lookup.py" "$title" "$author")
        
        # Extract improved metadata if available
        if [ -n "$metadata_json" ]; then
            improved_title=$(echo "$metadata_json" | jq -r '.title // ""')
            improved_author=$(echo "$metadata_json" | jq -r '.author // ""')
            online_narrator=$(echo "$metadata_json" | jq -r '.narrator // ""')
            online_series=$(echo "$metadata_json" | jq -r '.series // ""')
            online_series_part=$(echo "$metadata_json" | jq -r '.series_part // ""')
            online_year=$(echo "$metadata_json" | jq -r '.year // ""')
            online_description=$(echo "$metadata_json" | jq -r '.description // ""')
            online_cover_url=$(echo "$metadata_json" | jq -r '.cover_url // ""')
            
            # Extract genres
            online_genres=$(echo "$metadata_json" | jq -r '.genres[]' 2>/dev/null)
            if [ -n "$online_genres" ]; then
                # Set primary genre based on first genre from Goodreads
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
                series_source="online"
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
            
            if [ -z "$description" ] && [ -n "$online_description" ]; then
                description="$online_description"
                echo "- Found description from online" | tee -a "$LOG_FILE"
            fi
            
            # Download cover art if we have a URL and no local cover
            if [ -n "$online_cover_url" ] && [ -z "$cover_art" ]; then
                echo "- Downloading cover art..." | tee -a "$LOG_FILE"
                cover_art="$temp_dir/cover.jpg"
                curl -s -o "$cover_art" "$online_cover_url"
                if [ -f "$cover_art" ]; then
                    echo "- Cover art downloaded successfully" | tee -a "$LOG_FILE"
                else
                    echo "- Failed to download cover art" | tee -a "$LOG_FILE"
                    cover_art=""
                fi
            fi
        fi
    fi
    
    # Final check for critical metadata
    if [ -z "$author" ] || [ -z "$title" ]; then
        echo "ERROR: Could not determine required metadata for $book_name" | tee -a "$LOG_FILE"
        echo "Skipping this audiobook" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return
    fi
    
    # Sanitize metadata for file naming
    author=$(sanitize_filename "$author")
    title=$(sanitize_filename "$title")
    
    echo "=== METADATA SUMMARY ===" | tee -a "$LOG_FILE"
    echo "Author: $author (from $author_source)" | tee -a "$LOG_FILE"
    echo "Title: $title (from $title_source)" | tee -a "$LOG_FILE"
    if [ -n "$narrator" ]; then echo "Narrator: $narrator (from $narrator_source)" | tee -a "$LOG_FILE"; fi
    if [ -n "$series" ]; then 
        echo "Series: $series (from $series_source)" | tee -a "$LOG_FILE"
        if [ -n "$series_part" ]; then echo "Series part: $series_part" | tee -a "$LOG_FILE"; fi
    fi
    if [ -n "$year" ]; then echo "Year: $year" | tee -a "$LOG_FILE"; fi
    if [ -n "$genre" ]; then echo "Genre: $genre" | tee -a "$LOG_FILE"; fi
    if [ -n "$cover_art" ]; then echo "Cover art: $(basename "$cover_art")" | tee -a "$LOG_FILE"; fi
    
    # Step 3: Create concatenated audio file and detect chapters
    echo "=== PHASE 2: BUILDING M4B FILE ===" | tee -a "$LOG_FILE"
    echo "Concatenating files and detecting chapters..." | tee -a "$LOG_FILE"
    
    # Create a file list for ffmpeg
    local file_list="$temp_dir/filelist.txt"
    > "$file_list"
    
    # Create a chapters file
    local chapters_file="$temp_dir/chapters.txt"
    echo ";FFMETADATA1" > "$chapters_file"
    
    local current_time=0
    local track_num=1
    local valid_files_count=0
    
    # Process each file to get duration and build chapters
    # First save the IFS value and change it to handle paths with spaces correctly
    local OLD_IFS="$IFS"
    IFS=$'\n'
    for audio_file in $audio_files; do
        # Print the audio file for debugging
        echo "Processing audio file: '$audio_file'" | tee -a "$LOG_FILE"
        
        # Add to file list for concat with proper escaping (use fully qualified path)
        if [[ -f "$audio_file" ]]; then
            audio_file_abs=$(realpath "$audio_file")
            echo "file '$audio_file_abs'" >> "$file_list"
            echo "Added file to list: '$audio_file_abs'" | tee -a "$LOG_FILE"
            valid_files_count=$((valid_files_count + 1))
        else
            echo "Warning: File not found: '$audio_file'" | tee -a "$LOG_FILE"
            continue
        fi
        
        # Get duration in seconds
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file")
        
        # Check if duration was determined correctly
        if [ -z "$duration" ]; then
            echo "Warning: Could not determine duration for file: '$audio_file'" | tee -a "$LOG_FILE"
            duration=0
        else
            duration=${duration%.*} # truncate decimal part
        fi
        
        # Get chapter title from filename
        local chapter_title=$(basename "$audio_file" | sed 's/\.[^.]*$//')
        
        # If chapter title is just a number, add "Chapter" prefix
        if [[ "$chapter_title" =~ ^[0-9]+$ ]]; then
            chapter_title="Chapter $chapter_title"
        fi
        
        # Write chapter information
        echo "[CHAPTER]" >> "$chapters_file"
        echo "TIMEBASE=1/1000" >> "$chapters_file"
        echo "START=$((current_time * 1000))" >> "$chapters_file"
        echo "END=$(((current_time + duration) * 1000))" >> "$chapters_file"
        echo "title=$chapter_title" >> "$chapters_file"
        
        # Update current time
        current_time=$((current_time + duration))
        track_num=$((track_num + 1))
    done
    
    # Restore original IFS
    IFS="$OLD_IFS"
    
    # Check if we have any valid files to process
    if [ $valid_files_count -eq 0 ]; then
        echo "ERROR: No valid audio files found for processing" | tee -a "$LOG_FILE"
        echo "Skipping this audiobook" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return
    fi
    
    # Debug info about the files list
    echo "Total valid audio files found: $valid_files_count" | tee -a "$LOG_FILE"
    
    # Step 4: Prepare for creating m4b file
    echo "Preparing m4b file creation..." | tee -a "$LOG_FILE"
    
    # Determine appropriate output directory (but don't move files yet)
    local target_folder="$OUTPUT_DIR/Unsorted"
    
    # If it's part of a series, put it in the Series folder
    if [ -n "$series" ]; then
        # Create series-specific subfolder
        series_folder=$(sanitize_filename "$series")
        target_folder="$OUTPUT_DIR/Series/$series_folder"
    # Otherwise organize by genre
    elif [ -n "$genre" ]; then
        case "$genre" in
            *Fantasy*|*Magic*|*Dragons*|*Wizards*)
                target_folder="$OUTPUT_DIR/Fiction/Fantasy"
                ;;
            *Science*Fiction*|*Sci-Fi*|*SciFi*|*Dystopian*|*Space*|*Aliens*)
                target_folder="$OUTPUT_DIR/Fiction/Science Fiction"
                ;;
            *Mystery*|*Thriller*|*Suspense*|*Detective*|*Crime*)
                target_folder="$OUTPUT_DIR/Fiction/Mystery & Thriller"
                ;;
            *Historical*|*History*)
                if [[ "$genre" == *Fiction* ]]; then
                    target_folder="$OUTPUT_DIR/Fiction/Historical"
                else
                    target_folder="$OUTPUT_DIR/Non-Fiction/History"
                fi
                ;;
            *Romance*|*Love*)
                target_folder="$OUTPUT_DIR/Fiction/Romance"
                ;;
            *Biography*|*Memoir*|*Autobiography*)
                target_folder="$OUTPUT_DIR/Non-Fiction/Biography"
                ;;
            *Science*|*Physics*|*Biology*|*Chemistry*)
                target_folder="$OUTPUT_DIR/Non-Fiction/Science"
                ;;
            *Self*Help*|*Personal*Development*|*Motivation*)
                target_folder="$OUTPUT_DIR/Non-Fiction/Self-Help"
                ;;
            *Business*|*Economics*|*Finance*|*Management*)
                target_folder="$OUTPUT_DIR/Non-Fiction/Business"
                ;;
            *Children*|*Kids*|*Young*Reader*)
                target_folder="$OUTPUT_DIR/Children"
                ;;
            *Fiction*)
                target_folder="$OUTPUT_DIR/Fiction/General"
                ;;
            *Non*Fiction*)
                target_folder="$OUTPUT_DIR/Non-Fiction/General"
                ;;
        esac
    fi
    
    # Prepare author subfolder
    if [ -n "$author" ]; then
        author_folder=$(sanitize_filename "$author")
        target_folder="$target_folder/$author_folder"
    fi
    
    # If it's part of a series, add series and part to filename
    local output_filename="${author} - ${title}"
    if [ -n "$series" ] && [ -n "$series_part" ]; then
        output_filename="${author} - ${series} ${series_part} - ${title}"
    elif [ -n "$series" ]; then
        output_filename="${author} - ${series} - ${title}"
    fi
    
    local output_file="$temp_dir/${output_filename}.m4b"
    
    # Step 5: Create m4b file with metadata, chapters, and cover art
    echo "Creating m4b file..." | tee -a "$LOG_FILE"
    
    # Log if we will be adding cover art
    if [ -n "$cover_art" ] && [ -f "$cover_art" ]; then
        echo "Adding cover art from: $cover_art" | tee -a "$LOG_FILE"
    else
        echo "No cover art will be added" | tee -a "$LOG_FILE"
    fi
    
    # Log metadata that will be used
    echo "Using metadata:" | tee -a "$LOG_FILE"
    echo "- Title: $title" | tee -a "$LOG_FILE"
    echo "- Author: $author" | tee -a "$LOG_FILE"
    echo "- Genre: $genre" | tee -a "$LOG_FILE"
    if [ -n "$narrator" ]; then echo "- Narrator: $narrator" | tee -a "$LOG_FILE"; fi
    if [ -n "$series" ]; then 
        echo "- Series: $series" | tee -a "$LOG_FILE"
        if [ -n "$series_part" ]; then echo "- Series Part: $series_part" | tee -a "$LOG_FILE"; fi
    fi
    if [ -n "$year" ]; then echo "- Year: $year" | tee -a "$LOG_FILE"; fi
    
    # Truncate description if too long
    if [ -n "$description" ]; then
        if [ ${#description} -gt 255 ]; then
            description="${description:0:252}..."
        fi
        echo "- Description: (truncated to 255 chars)" | tee -a "$LOG_FILE"
    fi
    
    # We're going to run ffmpeg directly instead of building a command string
    
    # Execute the command
    echo "Running ffmpeg command..." | tee -a "$LOG_FILE"
    
    # Check if the output directory is writable
    if [ ! -w "$(dirname "$output_file")" ]; then
        echo "ERROR: Output directory is not writable: $(dirname "$output_file")" | tee -a "$LOG_FILE"
        echo "Skipping this audiobook" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return
    fi
    
    # Execute the command and capture the result
    set +e  # Disable exit on error temporarily
    # Redirect stderr to a file for analysis
    local stderr_file="$temp_dir/ffmpeg_stderr.log"
    # Create a debug log file
    touch "$temp_dir/ffmpeg_debug.log"
    # Run ffmpeg directly without using eval to avoid issues with line numbers
    ffmpeg -y -nostdin -f concat -safe 0 -i "$file_list" -i "$chapters_file" \
        $([[ -n "$cover_art" && -f "$cover_art" ]] && echo "-i $cover_art") \
        -map_metadata 1 \
        $([[ -n "$cover_art" && -f "$cover_art" ]] && echo "-map 0:a -map 2:v -disposition:v:0 attached_pic" || echo "-map 0:a") \
        -c:a aac -b:a 64k -movflags +faststart \
        -metadata title="$title" \
        -metadata artist="$author" \
        -metadata album="$title" \
        -metadata genre="$genre" \
        $([[ -n "$narrator" ]] && echo "-metadata composer=\"$narrator\" -metadata comment=\"Narrator: $narrator\"") \
        $([[ -n "$series" ]] && echo "-metadata show=\"$series\"") \
        $([[ -n "$series" && -n "$series_part" ]] && echo "-metadata episode_id=\"$series_part\"") \
        $([[ -n "$year" ]] && echo "-metadata date=\"$year\"") \
        $([[ -n "$description" ]] && echo "-metadata description=\"${description:0:255}\"") \
        "$output_file" 2>"$stderr_file"
        
    local ffmpeg_result=$?
    set -e  # Re-enable exit on error
    
    # Check for common error patterns in stderr
    if [ -f "$stderr_file" ]; then
        # Check for the "Enter command" prompt which indicates ffmpeg is waiting for input
        if grep -q "Enter command:" "$stderr_file"; then
            echo "ERROR: ffmpeg is waiting for input, which is not possible in a script" | tee -a "$LOG_FILE"
            echo "This usually happens when there's a problem with the input files or chapters" | tee -a "$LOG_FILE"
            echo "Skipping this audiobook" | tee -a "$LOG_FILE"
            rm -rf "$temp_dir"
            return
        fi
        
        # Log the stderr for debugging (but don't output to terminal to avoid line number confusion)
        echo "FFmpeg stderr output saved to log file" | tee -a "$LOG_FILE"
        cat "$stderr_file" >> "$LOG_FILE"
    fi
    
    # Check if the command was successful
    if [ $ffmpeg_result -ne 0 ]; then
        echo "ERROR: ffmpeg command failed with exit code $ffmpeg_result" | tee -a "$LOG_FILE"
        echo "This might be due to permission issues or existing files in the temp directory" | tee -a "$LOG_FILE"
        echo "Skipping this audiobook" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return
    fi
    
    # Check if output file was created
    if [ -f "$output_file" ]; then
        echo "Successfully created: $output_file" | tee -a "$LOG_FILE"
        
        # Create target directory if it doesn't exist
        mkdir -p "$target_folder"
        
        # Move the file to target directory
        local final_file="$target_folder/${output_filename}.m4b"
        mv "$output_file" "$final_file"
        
        echo "Moved file to: $final_file" | tee -a "$LOG_FILE"
        
        # Get file info
        local file_info=$(mediainfo "$final_file")
        echo "File info:" | tee -a "$LOG_FILE"
        echo "$file_info" | grep -E "Complete name|Format|Duration|Title|Performer|Album" | tee -a "$LOG_FILE"
    else
        echo "Failed to create $output_file" | tee -a "$LOG_FILE"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    echo "Processing completed for: $book_name" | tee -a "$LOG_FILE"
    echo "-------------------------------------------" | tee -a "$LOG_FILE"
}

# Main script execution
echo "Starting batch processing of audiobooks in $AUDIOBOOKS_DIR" | tee -a "$LOG_FILE"
echo "Output directory structure created in: $OUTPUT_DIR" | tee -a "$LOG_FILE"
echo "Directory structure:" | tee -a "$LOG_FILE"
find "$OUTPUT_DIR" -type d -mindepth 1 -maxdepth 2 | sort | tee -a "$LOG_FILE"
echo "-------------------------------------------" | tee -a "$LOG_FILE"

# Find all potential audiobook directories (containing audio files)
find "$AUDIOBOOKS_DIR" -type d -not -path "$OUTPUT_DIR*" -not -path "*/temp_processing*" | while read -r dir; do
    # Skip the main directory itself
    if [ "$dir" = "$AUDIOBOOKS_DIR" ]; then
        continue
    fi
    
    # Debug info
    echo "Checking directory: $dir" | tee -a "$LOG_FILE"
    
    # Check if directory contains audio files using a more robust approach
    if fd -e mp3 -e m4a -e flac -e wav -e aac . "$dir" --max-depth 1 | grep -q .; then
        echo "Found audio files in $dir" | tee -a "$LOG_FILE"
        process_audiobook "$dir"
    else
        echo "No audio files found directly in $dir, checking if it's a series/author directory..." | tee -a "$LOG_FILE"
        # Check if there are subdirectories that might contain audio files
        if find "$dir" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
            echo "Found subdirectories in $dir, treating as a collection directory" | tee -a "$LOG_FILE"
            # Don't process this directory directly, as it's likely just a container for multiple audiobooks
        else
            echo "No subdirectories or audio files found in $dir, skipping" | tee -a "$LOG_FILE"
        fi
    fi
done

echo "Batch processing completed. Check $LOG_FILE for details." | tee -a "$LOG_FILE"

# Generate summary report
echo "-------------------------------------------" | tee -a "$LOG_FILE"
echo "Processing Summary:" | tee -a "$LOG_FILE"
echo "Total audiobooks processed: $(grep -c "Processing completed for:" "$LOG_FILE")" | tee -a "$LOG_FILE"
echo "Books organized by category:" | tee -a "$LOG_FILE"
echo "- Fiction/Fantasy: $(find "$OUTPUT_DIR/Fiction/Fantasy" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Fiction/Science Fiction: $(find "$OUTPUT_DIR/Fiction/Science Fiction" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Fiction/Mystery & Thriller: $(find "$OUTPUT_DIR/Fiction/Mystery & Thriller" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Fiction/Historical: $(find "$OUTPUT_DIR/Fiction/Historical" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Fiction/Romance: $(find "$OUTPUT_DIR/Fiction/Romance" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Fiction/General: $(find "$OUTPUT_DIR/Fiction/General" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/History: $(find "$OUTPUT_DIR/Non-Fiction/History" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/Science: $(find "$OUTPUT_DIR/Non-Fiction/Science" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/Self-Help: $(find "$OUTPUT_DIR/Non-Fiction/Self-Help" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/Biography: $(find "$OUTPUT_DIR/Non-Fiction/Biography" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/Business: $(find "$OUTPUT_DIR/Non-Fiction/Business" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Non-Fiction/General: $(find "$OUTPUT_DIR/Non-Fiction/General" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Children: $(find "$OUTPUT_DIR/Children" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Series: $(find "$OUTPUT_DIR/Series" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "- Unsorted: $(find "$OUTPUT_DIR/Unsorted" -type f -name "*.m4b" | wc -l)" | tee -a "$LOG_FILE"
echo "-------------------------------------------" | tee -a "$LOG_FILE"
echo "Finished. Audio books organized in: $OUTPUT_DIR" | tee -a "$LOG_FILE"