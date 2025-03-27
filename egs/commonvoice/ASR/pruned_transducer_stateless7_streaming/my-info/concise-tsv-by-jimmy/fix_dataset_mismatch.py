#!/usr/bin/env python3
# fix_dataset_mismatch.py - Script to ensure consistency between MP3 files and TSV entries

import csv
import os
import argparse
from pathlib import Path

# Parse command line arguments
parser = argparse.ArgumentParser(description="Fix dataset mismatch between TSV and clips directory")
parser.add_argument("--custom-validated-tsv", default="./en/custom_validated.tsv", 
                    help="Path to custom_validated.tsv file (default: ./en/custom_validated.tsv)")
parser.add_argument("--clips-dir", default="./en/clips", 
                    help="Path to clips directory (default: ./en/clips)")
args = parser.parse_args()

# Define paths from arguments
tsv_file = args.custom_validated_tsv
clips_dir = args.clips_dir

print(f"Starting dataset consistency check...")
print(f"TSV file: {tsv_file}")
print(f"Clips directory: {clips_dir}")

# Get all MP3 files in the clips directory
mp3_files = set()
clips_path = Path(clips_dir)
if clips_path.exists() and clips_path.is_dir():
    for mp3_file in clips_path.glob("*.mp3"):
        mp3_files.add(mp3_file.name)

print(f"Found {len(mp3_files)} MP3 files in clips directory")

# Read the TSV file and filter out rows with empty sentences
valid_rows = []
empty_sentence_mp3s = set()
header = None

with open(tsv_file, "r", encoding="utf-8") as f:
    reader = csv.reader(f, delimiter="\t")
    header = next(reader)  # Get the header
    
    # Find the index of the sentence column
    sentence_idx = header.index("sentence") if "sentence" in header else 3  # Default to index 3 if not found
    
    for row in reader:
        if len(row) > sentence_idx and row[sentence_idx].strip():  # Check if sentence is not empty
            valid_rows.append(row)
            
            # Extract MP3 filename
            if len(row) > 1:
                mp3_path = row[1]  # The path column (index 1) contains the mp3 filename
                mp3_filename = os.path.basename(mp3_path)
                # We'll collect valid MP3s later
        else:
            # This row has an empty sentence, collect its MP3 filename
            if len(row) > 1:
                mp3_path = row[1]
                mp3_filename = os.path.basename(mp3_path)
                empty_sentence_mp3s.add(mp3_filename)
                print(f"Found row with empty sentence: {mp3_filename}")

print(f"Found {len(empty_sentence_mp3s)} rows with empty sentences")

# Write the filtered rows back to the TSV file
with open(tsv_file, "w", encoding="utf-8", newline="") as f:
    writer = csv.writer(f, delimiter="\t")
    writer.writerow(header)
    writer.writerows(valid_rows)

print(f"Updated {tsv_file} with {len(valid_rows)} valid rows")

# Collect valid MP3 filenames from the filtered rows
valid_mp3s = set()
for row in valid_rows:
    if len(row) > 1:
        mp3_path = row[1]
        mp3_filename = os.path.basename(mp3_path)
        valid_mp3s.add(mp3_filename)

# Delete MP3 files with empty sentences
deleted_empty_count = 0
for mp3_file in empty_sentence_mp3s:
    mp3_path = clips_path / mp3_file
    if mp3_path.exists():
        print(f"Deleting MP3 with empty sentence: {mp3_file}")
        mp3_path.unlink()
        deleted_empty_count += 1

print(f"Deleted {deleted_empty_count} MP3 files with empty sentences")

# Find and delete extra MP3 files (in clips but not in valid TSV entries)
extra_mp3s = mp3_files - valid_mp3s - empty_sentence_mp3s  # Exclude already deleted ones
print(f"Found {len(extra_mp3s)} extra MP3 files not referenced in TSV")

deleted_extra_count = 0
for mp3_file in extra_mp3s:
    mp3_path = clips_path / mp3_file
    if mp3_path.exists():
        print(f"Deleting extra MP3 file: {mp3_file}")
        mp3_path.unlink()
        deleted_extra_count += 1

print(f"Deleted {deleted_extra_count} extra MP3 files")

# Check for consistency after cleanup
remaining_mp3s = set()
for mp3_file in clips_path.glob("*.mp3"):
    remaining_mp3s.add(mp3_file.name)

print(f"After cleanup: {len(remaining_mp3s)} MP3 files, {len(valid_rows)} TSV entries")
if len(remaining_mp3s) == len(valid_rows):
    print("✓ Dataset is now consistent!")
else:
    print(f"⚠ Dataset still inconsistent: MP3 files: {len(remaining_mp3s)}, TSV entries: {len(valid_rows)}")

print("Done!")