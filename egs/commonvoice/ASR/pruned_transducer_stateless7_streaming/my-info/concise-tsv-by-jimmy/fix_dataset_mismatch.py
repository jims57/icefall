#!/usr/bin/env python3
# fix_dataset_mismatch.py - Script to ensure consistency between MP3 files and TSV entries

import csv
import os
from pathlib import Path

# Define paths
tsv_file = "custom_validated.tsv"
clips_dir = "clips"

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

# Read the TSV file and get valid MP3 filenames
valid_mp3s = set()
tsv_entries = []
header = None

with open(tsv_file, "r", encoding="utf-8") as f:
    reader = csv.reader(f, delimiter="\t")
    header = next(reader)  # Get the header
    
    for row in reader:
        if len(row) > 1:  # Ensure row has enough columns
            mp3_path = row[1]  # The path column (index 1) contains the mp3 filename
            mp3_filename = os.path.basename(mp3_path)
            valid_mp3s.add(mp3_filename)
            tsv_entries.append(row)

print(f"Found {len(valid_mp3s)} unique MP3 references in TSV file")

# Find extra MP3 files (in clips but not in TSV)
extra_mp3s = mp3_files - valid_mp3s
print(f"Found {len(extra_mp3s)} extra MP3 files not referenced in TSV")

# Delete extra MP3 files
deleted_count = 0
for mp3_file in extra_mp3s:
    mp3_path = clips_path / mp3_file
    if mp3_path.exists():
        print(f"Deleting extra MP3 file: {mp3_file}")
        mp3_path.unlink()
        deleted_count += 1

print(f"Deleted {deleted_count} extra MP3 files")

# Check for consistency after cleanup
remaining_mp3s = set()
for mp3_file in clips_path.glob("*.mp3"):
    remaining_mp3s.add(mp3_file.name)

print(f"After cleanup: {len(remaining_mp3s)} MP3 files, {len(tsv_entries)} TSV entries")
if len(remaining_mp3s) == len(tsv_entries):
    print("✓ Dataset is now consistent!")
else:
    print(f"⚠ Dataset still inconsistent: MP3 files: {len(remaining_mp3s)}, TSV entries: {len(tsv_entries)}")

print("Done!")