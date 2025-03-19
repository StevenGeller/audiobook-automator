#!/bin/bash
# cleanup_processed.sh - Clean up and organize the processed audiobooks

echo "Cleaning up processed directories..."

# First, remove any temporary processing directories
find "$(pwd)" -type d -name "temp_processing_*" | while read dir; do
  echo "Removing temporary directory: $dir"
  rm -rf "$dir"
done

# Clean up the processed directory
PROCESSED_DIR="processed"
if [ -d "$PROCESSED_DIR" ]; then
  echo "Ensuring flat structure in the processed directory..."
  
  # Create processed directory if it doesn't exist
  mkdir -p "$PROCESSED_DIR"
  
  # Find any m4b files in subdirectories and move them to processed directory
  find "$PROCESSED_DIR" -type f -name "*.m4b" -not -path "$PROCESSED_DIR/*" | while read file; do
    filename=$(basename "$file")
    echo "Moving $file to $PROCESSED_DIR/$filename"
    mv "$file" "$PROCESSED_DIR/$filename"
  done
  
  # Clean up empty directories in processed
  find "$PROCESSED_DIR" -type d -empty -not -path "$PROCESSED_DIR" | while read dir; do
    echo "Removing empty directory: $dir"
    rmdir "$dir" 2>/dev/null
  done
  
  echo "Cleanup complete!"
else
  echo "Processed directory not found."
fi