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
download_total=10
dev_ratio=0.1
test_ratio=0.1

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

# Run the conversion script
echo "Converting parquet files to MP3 and transcripts..."
python convert_parquets_files_into_mp3_and_transcripts.py

echo "People Speech conversion completed."

# Create 'en' directory if it doesn't exist
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
