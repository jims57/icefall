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
# Important: Both prepare_people_speech.sh and download_people_speech_parquets_files.py
# must be uploaded to your working folder before running these commands.
#
# Download 10 files (default):
# bash prepare_people_speech.sh
#
# Download a specific number of files:
# bash prepare_people_speech.sh --download-total 20
#
# This script:
# 1. Checks and installs required packages (pandas, pyarrow, requests, tqdm)
# 2. Creates the people_speech_data directory if it doesn't exist
# 3. Downloads People's Speech dataset parquet files

# Default values for parameters
download_total=1
dev_ratio=0.1
test_ratio=0.1
merge_into_dir="../concise-cv-ds-by-jimmy-1"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --download-total)
      download_total="$2"
      shift 2
      ;;
    --dev-ratio)
      dev_ratio="$2"
      shift 2
      ;;
    --test-ratio)
      test_ratio="$2"
      shift 2
      ;;
    --merge-into-dir)
      merge_into_dir="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check and install required packages
for package in pandas pyarrow requests tqdm; do
  if ! python -c "import $package" 2>/dev/null; then
    echo "Installing $package..."
    pip install "$package"
  else
    echo "$package is already installed."
  fi
done

# Create directory if it doesn't exist
if [ ! -d "people_speech_data" ]; then
  echo "Creating people_speech_data directory..."
  mkdir -p people_speech_data
else
  echo "Directory people_speech_data already exists."
fi

# Run the Python script with the specified parameter
echo "Running download script with download-total=$download_total..."
python download_people_speech_parquets_files.py --download-total "$download_total"

echo "People Speech preparation completed."

# Install additional required packages for conversion
echo "Installing additional required packages..."
pip install pandas pyarrow pydub soundfile

# Check and install ffmpeg if not already installed
if ! command -v ffmpeg &> /dev/null; then
  echo "ffmpeg not found. Installing ffmpeg..."
  
  # Detect OS and install ffmpeg accordingly
  if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    apt-get update && apt-get install -y ffmpeg
  elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    yum install -y ffmpeg
  elif [ -f /etc/arch-release ]; then
    # Arch Linux
    pacman -S --noconfirm ffmpeg
  elif [ -f /etc/alpine-release ]; then
    # Alpine
    apk add --no-cache ffmpeg
  elif command -v brew &> /dev/null; then
    # macOS with Homebrew
    brew install ffmpeg
  else
    echo "Warning: Could not automatically install ffmpeg. Please install it manually."
    echo "You can try: sudo apt-get install ffmpeg (for Debian/Ubuntu)"
    echo "or: sudo yum install ffmpeg (for CentOS/RHEL)"
    exit 1
  fi
else
  echo "ffmpeg is already installed."
fi

# Run the conversion script
echo "Converting parquet files to MP3 and transcripts (keeping only sentences with 1-40 words)..."
python convert_parquets_files_into_mp3_and_transcripts.py

echo "People Speech conversion completed."

# Filter TSV to remove entries without audio files
echo "Filtering custom_validated.tsv to match available audio files..."
if [ -f "custom_validated.tsv" ] && [ -d "clips" ]; then
  # Create temp file
  python - << 'EOL'
import os
import csv

# Get all audio files in clips directory
audio_files = set()
clips_dir = "clips"
for root, dirs, files in os.walk(clips_dir):
    for file in files:
        if file.endswith('.mp3'):
            audio_files.add(os.path.basename(file))

print(f"Found {len(audio_files)} audio files in clips directory")

# Read and filter TSV file
valid_rows = []
with open("custom_validated.tsv", 'r', encoding='utf-8') as f:
    reader = csv.reader(f, delimiter='\t')
    header = next(reader)  # Store header
    skipped = 0
    kept = 0
    
    for row in reader:
        if len(row) > 1:  # Ensure row has path column
            path = row[1]
            filename = os.path.basename(path)
            
            if filename in audio_files:
                valid_rows.append(row)
                kept += 1
            else:
                skipped += 1

print(f"Filtered out {skipped} entries without corresponding audio files")
print(f"Keeping {kept} valid entries")

# Write filtered TSV back
with open("custom_validated.tsv.filtered", 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow(header)
    writer.writerows(valid_rows)
EOL

  # Replace original with filtered version
  mv custom_validated.tsv.filtered custom_validated.tsv
  echo "Filtered custom_validated.tsv now contains only entries with matching audio files"
else
  echo "Warning: Could not filter TSV. custom_validated.tsv or clips directory not found"
fi

# Create 'en' directory if it doesn't exist
if [ -z "$merge_into_dir" ]; then
  if [ ! -d "en" ]; then
    echo "Creating 'en' directory..."
    mkdir -p en
  else
    echo "Directory 'en' already exists."
  fi

  # Move clips folder and custom_validated.tsv to en directory
  echo "Moving clips folder and custom_validated.tsv to en directory..."
  if [ -d "clips" ]; then
    mv clips en/
    echo "Moved clips folder to en directory."
  else
    echo "Warning: clips folder not found."
  fi

  if [ -f "custom_validated.tsv" ]; then
    mv custom_validated.tsv en/
    echo "Moved custom_validated.tsv to en directory."
  else
    echo "Warning: custom_validated.tsv file not found."
  fi
else
  # We're merging into an existing directory
  echo "Merging data into $merge_into_dir..."
  
  # Create target directories if they don't exist
  mkdir -p "$merge_into_dir/en/clips"
  
  # Check if clips folder exists and copy its contents
  if [ -d "clips" ]; then
    echo "Copying clips to $merge_into_dir/en/clips..."
    cp -r clips/* "$merge_into_dir/en/clips/"
  elif [ -d "en/clips" ]; then
    echo "Copying en/clips to $merge_into_dir/en/clips..."
    cp -r en/clips/* "$merge_into_dir/en/clips/"
  else
    echo "Warning: No clips folder found to copy."
  fi
  
  # Check for the target TSV file in multiple possible locations
  target_tsv=""
  if [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
    target_tsv="$merge_into_dir/en/custom_validated.tsv"
  elif [ -f "$merge_into_dir/custom_validated.tsv" ]; then
    # If it's in the root of merge_into_dir, create the en directory and move it there
    mkdir -p "$merge_into_dir/en"
    mv "$merge_into_dir/custom_validated.tsv" "$merge_into_dir/en/custom_validated.tsv"
    target_tsv="$merge_into_dir/en/custom_validated.tsv"
  elif [ -f "$(dirname $merge_into_dir)/custom_validated.tsv" ]; then
    # Check one level up
    mkdir -p "$merge_into_dir/en"
    cp "$(dirname $merge_into_dir)/custom_validated.tsv" "$merge_into_dir/en/custom_validated.tsv"
    target_tsv="$merge_into_dir/en/custom_validated.tsv"
  fi
  
  # Handle the TSV file
  if [ -n "$target_tsv" ]; then
    echo "Target custom_validated.tsv found at $target_tsv, merging data..."
    
    # Determine source TSV
    if [ -f "custom_validated.tsv" ]; then
      source_tsv="custom_validated.tsv"
    elif [ -f "en/custom_validated.tsv" ]; then
      source_tsv="en/custom_validated.tsv"
    else
      echo "Error: No source TSV file found for merging."
      exit 1
    fi
    
    # Create a Python script to merge TSV files without duplicates
    cat > merge_tsv_files.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import os

def main():
    parser = argparse.ArgumentParser(description="Merge TSV files without duplicates")
    parser.add_argument("--source", type=str, required=True, help="Source TSV file")
    parser.add_argument("--target", type=str, required=True, help="Target TSV file to merge into")
    parser.add_argument("--output", type=str, required=True, help="Output TSV file")
    args = parser.parse_args()
    
    # Read target file data to detect duplicates
    target_paths = set()
    target_sentences = set()
    target_rows = []
    
    with open(args.target, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)  # Read header
        for row in reader:
            path = row[1] if len(row) > 1 else ""
            sentence = row[3] if len(row) > 3 else ""
            
            # Store paths and sentences for duplicate detection
            if path:
                target_paths.add(os.path.basename(path))
            if sentence:
                target_sentences.add(sentence.strip())
            
            target_rows.append(row)
    
    # Read source file and find new entries
    new_rows = []
    duplicates = 0
    
    with open(args.source, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        source_header = next(reader)  # Skip header
        
        for row in reader:
            path = row[1] if len(row) > 1 else ""
            sentence = row[3] if len(row) > 3 else ""
            
            # Check for duplicates
            filename = os.path.basename(path) if path else ""
            is_duplicate = False
            
            if filename and filename in target_paths:
                is_duplicate = True
            elif sentence and sentence.strip() in target_sentences:
                is_duplicate = True
            
            if is_duplicate:
                duplicates += 1
            else:
                new_rows.append(row)
                # Add to sets to prevent duplicates within source file
                if path:
                    target_paths.add(os.path.basename(path))
                if sentence:
                    target_sentences.add(sentence.strip())
    
    # Write merged data to output file
    with open(args.output, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(target_rows)
        writer.writerows(new_rows)
    
    print(f"Merged files: {len(new_rows)} new entries added, {duplicates} duplicates skipped")

if __name__ == "__main__":
    main()
EOL
    
    # Make script executable
    chmod +x merge_tsv_files.py
    
    # Merge TSV files
    python merge_tsv_files.py --source="$source_tsv" --target="$target_tsv" --output="$target_tsv.new"
    mv "$target_tsv.new" "$target_tsv"
    
    echo "Data successfully merged into $merge_into_dir"
  else
    # Target TSV doesn't exist, create it from scratch
    echo "Target custom_validated.tsv doesn't exist, creating it..."
    
    # Create the target directory if it doesn't exist
    mkdir -p "$merge_into_dir/en"
    
    if [ -f "custom_validated.tsv" ]; then
      cp custom_validated.tsv "$merge_into_dir/en/custom_validated.tsv"
      echo "Copied custom_validated.tsv to $merge_into_dir/en/"
    elif [ -f "en/custom_validated.tsv" ]; then
      cp en/custom_validated.tsv "$merge_into_dir/en/custom_validated.tsv"
      echo "Copied en/custom_validated.tsv to $merge_into_dir/en/"
    else
      echo "Error: Could not find TSV file to copy to target location"
      # Instead of exiting, create an empty TSV file with the correct header
      echo -e "client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment" > "$merge_into_dir/en/custom_validated.tsv"
      echo "Created empty custom_validated.tsv with header in $merge_into_dir/en/"
    fi
    
    echo "Data successfully initialized in $merge_into_dir"
  fi
  
  echo "Skipping local dataset processing since we're in merge mode."
  # Skip the rest of the script when merging
  exit 0
fi

# Print statistics about the filtered dataset
echo "Dataset statistics after filtering:"
if [ -f "en/custom_validated.tsv" ]; then
  total_lines=$(wc -l < "en/custom_validated.tsv")
  data_lines=$((total_lines - 1))  # Subtract header line
  echo "Total utterances with 1-40 words: $data_lines"
fi

# Generate TSV files for train, dev, and test sets
echo "Generating train, dev, and test TSV files..."
cd en
python -c "
import argparse
import csv
import os
import random
from pathlib import Path

def write_tsv_file(filename, header, rows):
    with open(filename, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(rows)

# Read all rows from custom_validated.tsv
all_rows = []
with open('custom_validated.tsv', 'r', encoding='utf-8') as f:
    reader = csv.reader(f, delimiter='\t')
    header = next(reader)  # Get the header
    for row in reader:
        all_rows.append(row)

print(f'Total data rows in custom_validated.tsv: {len(all_rows)}')

# Shuffle the rows to ensure randomness in the split
random.seed(42)
random.shuffle(all_rows)

num_to_select = len(all_rows)
dev_ratio = $dev_ratio
test_ratio = $test_ratio

# For small datasets: ensure exact allocation with minimums of 1 for dev/test
if num_to_select >= 3:
    # For small datasets, we need to be very precise
    if num_to_select <= 10:
        # With small datasets, ensure at least 1 each for dev/test, and rest to train
        dev_size = 1
        test_size = 1
        train_size = num_to_select - dev_size - test_size
    else:
        # For larger datasets, calculate based on ratios
        dev_size = max(1, round(num_to_select * dev_ratio))
        test_size = max(1, round(num_to_select * test_ratio))
        
        # Ensure we don't over-allocate (leaving no train data)
        if dev_size + test_size >= num_to_select:
            dev_size = 1
            test_size = 1
            
        # All remaining rows go to train
        train_size = num_to_select - dev_size - test_size
else:
    # If we have fewer than 3 rows, prioritize train set
    print('Warning: Not enough data for all three splits. Prioritizing train set.')
    if num_to_select == 2:
        dev_size = 1
        test_size = 0
        train_size = 1
    elif num_to_select == 1:
        dev_size = 0
        test_size = 0
        train_size = 1
    else:  # num_to_select == 0
        dev_size = 0
        test_size = 0
        train_size = 0

print(f'Creating dev.tsv with {dev_size} data rows')
print(f'Creating test.tsv with {test_size} data rows')
print(f'Creating train.tsv with {train_size} data rows')

# Split the rows
dev_rows = all_rows[:dev_size]
test_rows = all_rows[dev_size:dev_size + test_size]
train_rows = all_rows[dev_size + test_size:]

# Write the TSV files
write_tsv_file('dev.tsv', header, dev_rows)
write_tsv_file('test.tsv', header, test_rows)
write_tsv_file('train.tsv', header, train_rows)

print(f'Wrote {len(dev_rows)} data rows to dev.tsv')
print(f'Wrote {len(test_rows)} data rows to test.tsv')
print(f'Wrote {len(train_rows)} data rows to train.tsv')
"
cd ..
echo "TSV files generation completed."

# Delete people_speech_data folder to save space
if [ -d "people_speech_data" ]; then
  echo "Deleting people_speech_data folder to save space..."
  rm -rf people_speech_data
  echo "people_speech_data folder deleted."
else
  echo "people_speech_data folder not found."
fi

# Clean up server space
echo "Cleaning up server trash to free up space..."
rm -rf ~/.local/share/Trash/*
echo "Server trash cleaned."

echo "People Speech preparation and organization completed."
