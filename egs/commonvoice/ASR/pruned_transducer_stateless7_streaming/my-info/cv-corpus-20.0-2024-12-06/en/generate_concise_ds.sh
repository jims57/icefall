#!/bin/bash
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# See ../../../../LICENSE for clarification regarding multiple authors
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

# Usage:
#
# This script creates a concise version of the CommonVoice dataset by:
# - Creating backup copies of TSV files
# - Trimming the dataset to a small number of samples
# - Removing unused MP3 files to save disk space
#
# Basic usage:
# bash generate_concise_ds.sh
#
# Parameters:
#   --dev-samples: Number of samples to keep in dev set (default: 101)
#   --test-samples: Number of samples to keep in test set (default: 101)
#   --train-samples: Number of samples to keep in train set (default: 1001)
#   --clips-dir: Directory containing MP3 files (default: "clips")
#
# Example:
# bash generate_concise_ds.sh --dev-samples 50 --test-samples 50 --train-samples 500

# Default values for parameters
dev_samples=101
test_samples=101
train_samples=1001
clips_dir="clips"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --dev-samples)
            dev_samples="$2"
            shift 2
            ;;
        --test-samples)
            test_samples="$2"
            shift 2
            ;;
        --train-samples)
            train_samples="$2"
            shift 2
            ;;
        --clips-dir)
            clips_dir="$2"
            shift 2
            ;;
        *)
            # Unknown option
            echo "Unknown option: $1"
            echo "Usage: $0 [--dev-samples N] [--test-samples N] [--train-samples N] [--clips-dir DIR]"
            exit 1
            ;;
    esac
done

# Check if we're in the correct directory
if [ ! -f "dev.tsv" ] || [ ! -f "test.tsv" ] || [ ! -f "train.tsv" ]; then
    echo "Error: Cannot find dev.tsv, test.tsv, or train.tsv in the current directory."
    echo "Please run this script from the CommonVoice dataset directory containing the TSV files."
    exit 1
fi

# Check if clips directory exists
if [ ! -d "$clips_dir" ]; then
    echo "Error: Clips directory '$clips_dir' not found."
    exit 1
fi

echo "====================================================================="
echo "Creating a concise version of the CommonVoice dataset:"
echo "- Dev samples: $dev_samples"
echo "- Test samples: $test_samples"
echo "- Train samples: $train_samples"
echo "- Clips directory: $clips_dir"
echo "====================================================================="

# Step 1: Create backup copies of the TSV files
echo "Step 1: Creating backup copies of TSV files..."
cp dev.tsv dev-copy.tsv
cp test.tsv test-copy.tsv
cp train.tsv train-copy.tsv
if [ -f "validated.tsv" ]; then
    cp validated.tsv validated-copy.tsv
    echo "✓ Backed up validated.tsv to validated-copy.tsv"
fi
echo "✓ Backed up dev.tsv to dev-copy.tsv"
echo "✓ Backed up test.tsv to test-copy.tsv"
echo "✓ Backed up train.tsv to train-copy.tsv"

# Step 2: Trim the TSV files to keep only the specified number of samples
echo -e "\nStep 2: Trimming TSV files to create concise dataset..."

# Function to trim a TSV file to keep only the header and N data rows
trim_tsv_file() {
    local file="$1"
    local num_rows="$2"
    local temp_file=$(mktemp)
    
    # Extract header (first line)
    head -n 1 "$file" > "$temp_file"
    
    # Extract the specified number of data rows (skip header)
    tail -n +2 "$file" | head -n "$num_rows" >> "$temp_file"
    
    # Replace original file with trimmed version
    mv "$temp_file" "$file"
    
    # Count the actual number of data rows (excluding header)
    local actual_rows=$(wc -l < "$file")
    actual_rows=$((actual_rows - 1))
    
    echo "✓ Trimmed $file to keep $actual_rows rows (plus header)"
}

trim_tsv_file "dev.tsv" "$dev_samples"
trim_tsv_file "test.tsv" "$test_samples"
trim_tsv_file "train.tsv" "$train_samples"

# Step 3: Identify MP3 files to keep based on the trimmed TSV files
echo -e "\nStep 3: Identifying MP3 files to keep based on trimmed TSV files..."

# Create a Python script to extract MP3 filenames from TSV files and clean up the clips directory
cat > extract_mp3_files.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import csv

def extract_mp3_filenames(tsv_files, clips_dir):
    # Set to store MP3 filenames that should be kept
    mp3_to_keep = set()
    
    # Extract MP3 filenames from each TSV file
    for tsv_file in tsv_files:
        if not os.path.exists(tsv_file):
            print(f"Warning: {tsv_file} does not exist, skipping")
            continue
            
        with open(tsv_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            next(reader)  # Skip header
            
            for row in reader:
                if len(row) > 1 and row[1]:  # Check if path column exists and is not empty
                    mp3_filename = row[1]
                    mp3_to_keep.add(mp3_filename)
    
    print(f"Found {len(mp3_to_keep)} MP3 files to keep from TSV files")
    
    # Get all MP3 files in the clips directory
    all_mp3_files = set()
    mp3_count = 0
    for filename in os.listdir(clips_dir):
        if filename.endswith('.mp3'):
            all_mp3_files.add(filename)
            mp3_count += 1
    
    print(f"Found {mp3_count} MP3 files in {clips_dir}")
    
    # Identify MP3 files to delete
    mp3_to_delete = all_mp3_files - mp3_to_keep
    print(f"Will delete {len(mp3_to_delete)} MP3 files that are not referenced in the TSV files")
    
    # Delete unused MP3 files
    deleted_count = 0
    for mp3_file in mp3_to_delete:
        mp3_path = os.path.join(clips_dir, mp3_file)
        try:
            os.remove(mp3_path)
            deleted_count += 1
            if deleted_count % 1000 == 0:
                print(f"Deleted {deleted_count} files so far...")
        except Exception as e:
            print(f"Error deleting {mp3_file}: {e}", file=sys.stderr)
    
    print(f"Deleted {deleted_count} MP3 files that were not referenced in the trimmed TSV files")
    
    # Verify that all MP3 files in mp3_to_keep exist in the clips directory
    missing_count = 0
    for mp3_file in mp3_to_keep:
        mp3_path = os.path.join(clips_dir, mp3_file)
        if not os.path.exists(mp3_path):
            missing_count += 1
            print(f"Warning: {mp3_file} is referenced in TSV but not found in {clips_dir}", file=sys.stderr)
    
    if missing_count > 0:
        print(f"Warning: {missing_count} MP3 files referenced in TSV are missing from {clips_dir}")
    
    # Count remaining MP3 files
    remaining_count = len([f for f in os.listdir(clips_dir) if f.endswith('.mp3')])
    print(f"Clips directory now contains {remaining_count} MP3 files")
    
    if remaining_count != len(mp3_to_keep):
        print(f"Warning: Mismatch between expected ({len(mp3_to_keep)}) and actual ({remaining_count}) MP3 count")
    else:
        print("Success: MP3 count matches expected count from TSV files")
    
    return remaining_count, len(mp3_to_keep)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python extract_mp3_files.py TSV_FILE1 [TSV_FILE2 ...] CLIPS_DIR")
        sys.exit(1)
    
    clips_dir = sys.argv[-1]
    tsv_files = sys.argv[1:-1]
    
    extract_mp3_filenames(tsv_files, clips_dir)
EOL

# Make the script executable
chmod +x extract_mp3_files.py

# Run the script
echo "Running MP3 cleanup script..."
python extract_mp3_files.py dev.tsv test.tsv train.tsv "$clips_dir"

# Step 4: Verify consistency
echo -e "\nStep 4: Verifying dataset consistency..."

# Count total rows in TSV files (excluding headers)
dev_count=$(wc -l < dev.tsv)
dev_count=$((dev_count - 1))
test_count=$(wc -l < test.tsv)
test_count=$((test_count - 1))
train_count=$(wc -l < train.tsv)
train_count=$((train_count - 1))
total_count=$((dev_count + test_count + train_count))

# Count MP3 files
mp3_count=$(find "$clips_dir" -name "*.mp3" | wc -l)

echo "Dataset statistics:"
echo "- Dev set: $dev_count samples"
echo "- Test set: $test_count samples"
echo "- Train set: $train_count samples"
echo "- Total: $total_count samples"
echo "- MP3 files in $clips_dir: $mp3_count"

if [ "$total_count" -eq "$mp3_count" ]; then
    echo "✓ Success: Number of MP3 files matches total number of samples in TSV files"
else
    echo "⚠ Warning: Mismatch between total samples ($total_count) and MP3 files ($mp3_count)"
fi

echo -e "\nConcise dataset creation completed!"
echo "The original files have been backed up as:"
echo "- dev-copy.tsv"
echo "- test-copy.tsv"
echo "- train-copy.tsv"
if [ -f "validated-copy.tsv" ]; then
    echo "- validated-copy.tsv"
fi
echo -e "\nTo restore the original dataset, run:"
echo "cp dev-copy.tsv dev.tsv"
echo "cp test-copy.tsv test.tsv"
echo "cp train-copy.tsv train.tsv"
if [ -f "validated-copy.tsv" ]; then
    echo "cp validated-copy.tsv validated.tsv"
fi
echo -e "\nNote: Restoring the original TSV files will not restore deleted MP3 files."
