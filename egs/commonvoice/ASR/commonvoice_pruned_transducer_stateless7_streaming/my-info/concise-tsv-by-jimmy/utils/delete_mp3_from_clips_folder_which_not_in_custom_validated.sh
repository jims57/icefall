#!/bin/bash
# Copyright (c) 2023 Jimmy
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script deletes MP3 files from the clips folder that don't have 
# corresponding records in custom_validated.tsv

set -e  # Exit on error
set -u  # Error on undefined variables

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default paths (relative to the current working directory, not the script)
CUSTOM_VALIDATED_TSV="./custom_validated.tsv"
CLIPS_DIR="./clips"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --custom-validated-tsv)
      CUSTOM_VALIDATED_TSV="$2"
      shift 2
      ;;
    --clips-dir)
      CLIPS_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--custom-validated-tsv PATH] [--clips-dir PATH]"
      exit 1
      ;;
  esac
done

# Check if files/directories exist
if [ ! -f "$CUSTOM_VALIDATED_TSV" ]; then
  echo "Error: Custom validated TSV file not found at $CUSTOM_VALIDATED_TSV"
  exit 1
fi

if [ ! -d "$CLIPS_DIR" ]; then
  echo "Error: Clips directory not found at $CLIPS_DIR"
  exit 1
fi

echo "Creating list of MP3 files in custom_validated.tsv..."
# Extract the second column (path) from TSV, skip header, and get just the filename
# The path column (index 1) contains the mp3 filename
awk -F'\t' 'NR>1 {print $2}' "$CUSTOM_VALIDATED_TSV" | xargs -I{} basename {} > valid_mp3s.txt

echo "Counting MP3 files in clips directory..."
find "$CLIPS_DIR" -name "*.mp3" | wc -l

echo "Deleting MP3 files not in custom_validated.tsv..."
# Process files in batches to avoid memory issues
find "$CLIPS_DIR" -name "*.mp3" | while read mp3_file; do
  filename=$(basename "$mp3_file")
  if ! grep -q "^$filename$" valid_mp3s.txt; then
    rm "$mp3_file"
    echo "Deleted: $filename"
  fi
done

# Count remaining files
remaining=$(find "$CLIPS_DIR" -name "*.mp3" | wc -l)
echo "Remaining MP3 files in clips directory: $remaining"

# Clean up
rm valid_mp3s.txt
echo "Done!"
