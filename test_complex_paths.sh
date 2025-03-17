#!/bin/bash
#
# Test script for audiobook-automator with complex paths
# Creates test audiobook directories with spaces, special characters, and nested structures
#

set -e  # Exit on error

# Output colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test directory
TEST_DIR="$(pwd)/test_audiobooks"

# Function to create a test audiobook directory with mp3 files
create_test_audiobook() {
    local dir_name="$1"
    local file_count="$2"
    local dir_path="$TEST_DIR/$dir_name"
    
    echo -e "${BLUE}Creating test audiobook: $dir_name${NC}"
    mkdir -p "$dir_path"
    
    # Create cover image file (create a simple text file for testing)
    echo "This is a test cover image for $dir_name" > "$dir_path/cover.jpg"
    
    # Create metadata file
    cat > "$dir_path/cover.txt" << EOF
Title: $(echo "$dir_name" | sed 's/.*- //g')
Author: $(echo "$dir_name" | sed 's/ -.*//g')
Narrator: Test Narrator
Series: Test Series
Book: 1
Year: 2023
Genre: Science Fiction
Description: This is a test audiobook created for testing the audiobook-automator script with complex paths.
EOF
    
    # Create test mp3 files (empty files, just for testing)
    for i in $(seq -w 1 $file_count); do
        echo "This is test audio file $i for $dir_name" > "$dir_path/$i.mp3"
    done
    
    echo -e "${GREEN}Created test audiobook with $file_count files${NC}"
}

# Create different test cases

create_complex_test_cases() {
    echo -e "\n${BLUE}Creating complex test cases...${NC}"
    
    # Case 1: Directory with spaces
    create_test_audiobook "Author With Spaces - Book With Spaces" 5
    
    # Case 2: Directory with special characters
    create_test_audiobook "Special_Char's! - Book@Title#" 3
    
    # Case 3: Very long directory name
    create_test_audiobook "Very Long Author Name That Goes On And On - Extremely Long Book Title That Never Seems To End And Just Keeps Going" 2
    
    # Case 4: Nested structure - create manually with subdirectories
    local nested_dir="$TEST_DIR/Nested/Structure/Author - Book"
    mkdir -p "$nested_dir"
    echo "This is a test cover image" > "$nested_dir/cover.jpg"
    echo "Title: Book\nAuthor: Author" > "$nested_dir/cover.txt"
    for i in $(seq -w 1 4); do
        echo "This is test audio file $i" > "$nested_dir/$i.mp3"
    done
    
    # Case 5: Unicode characters
    create_test_audiobook "Αυτόρ Ñãmé - Βοοκ Τίτλé" 3
    
    # Case 6: Directory with brackets and parentheses
    create_test_audiobook "Author (with brackets) - Book [with brackets]" 3
    
    # Create validation file to verify output later
    echo "Test cases created at $(date)" > "$TEST_DIR/validation.txt"
    ls -R "$TEST_DIR" >> "$TEST_DIR/validation.txt"
}

# Function to create organized output directory structure
create_output_structure() {
    echo -e "\n${BLUE}Creating output directory structure...${NC}"
    
    # Create main output structure
    mkdir -p "$TEST_DIR/processed/Fiction/Fantasy"
    mkdir -p "$TEST_DIR/processed/Fiction/Science Fiction"
    mkdir -p "$TEST_DIR/processed/Fiction/Mystery & Thriller"
    mkdir -p "$TEST_DIR/processed/Fiction/Historical"
    mkdir -p "$TEST_DIR/processed/Fiction/Romance"
    mkdir -p "$TEST_DIR/processed/Fiction/General"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/History"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/Science"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/Self-Help"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/Biography"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/Business"
    mkdir -p "$TEST_DIR/processed/Non-Fiction/General"
    mkdir -p "$TEST_DIR/processed/Children"
    mkdir -p "$TEST_DIR/processed/Series"
    mkdir -p "$TEST_DIR/processed/Unsorted"
    
    echo -e "${GREEN}Output directory structure created${NC}"
}

# Function to run automatic tests
run_tests() {
    echo -e "\n${BLUE}Running automated tests...${NC}"
    
    # First test: Run the sanitize filenames script
    echo -e "\n1. Testing organize_filenames.sh..."
    ./organize_filenames.sh "$TEST_DIR"
    
    # Second test: Run the main processor script with the test directory
    # Using the --keep-original-files flag to preserve test files
    echo -e "\n2. Testing audiobook_processor.sh..."
    ./audiobook_processor.sh "$TEST_DIR" --keep-original-files
    
    # Check test results
    echo -e "\n${BLUE}Verifying test results...${NC}"
    if [ -f "$TEST_DIR/processing_log.txt" ]; then
        echo -e "${GREEN}Log file created${NC}"
        echo "Processing results:" 
        grep "Processing completed for" "$TEST_DIR/processing_log.txt" | wc -l | xargs echo "Audiobooks processed:"
    else
        echo -e "${RED}No log file found${NC}"
    fi
    
    # Count m4b files created
    echo "\nChecking for M4B files created:"
    find "$TEST_DIR" -name "*.m4b" | wc -l | xargs echo "M4B files found:"
    
    # List created files
    echo "\nListing created M4B files:"
    find "$TEST_DIR" -name "*.m4b" -exec ls -lh {} \;
}

# Main function
main() {
    echo -e "${BLUE}===== Audiobook Automator Test Script =====${NC}"
    
    # Check if test directory exists and offer to recreate it
    if [ -d "$TEST_DIR" ]; then
        echo -e "${RED}Test directory already exists: $TEST_DIR${NC}"
        read -p "Do you want to delete and recreate it? (y/n): " answer
        if [ "$answer" = "y" ]; then
            rm -rf "$TEST_DIR"
            echo "Test directory deleted"
        else
            echo "Using existing test directory"
        fi
    fi
    
    # Create test directory if it doesn't exist
    if [ ! -d "$TEST_DIR" ]; then
        mkdir -p "$TEST_DIR"
        echo "Created test directory: $TEST_DIR"
        create_complex_test_cases
        create_output_structure
    fi
    
    # Ask if user wants to run the tests
    read -p "Do you want to run the automated tests? (y/n): " run_answer
    if [ "$run_answer" = "y" ]; then
        run_tests
    else
        echo -e "\nTest files created in $TEST_DIR"
        echo "You can manually run tests with:"
        echo "  ./organize_filenames.sh $TEST_DIR"
        echo "  ./audiobook_processor.sh $TEST_DIR --keep-original-files"
    fi
    
    echo -e "\n${GREEN}Test script completed!${NC}"
}

main