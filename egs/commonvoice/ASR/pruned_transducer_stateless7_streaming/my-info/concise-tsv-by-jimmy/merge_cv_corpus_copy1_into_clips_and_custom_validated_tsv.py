#!/usr/bin/env python3

import os
import shutil
import glob

# Define the correct paths using relative paths
# The script is in the parent directory of the 'en' folder that contains the actual files
en_dir = os.path.join("en")

# Define paths for clips directories
clips_copy1_dir = os.path.join(en_dir, "clips-Copy1")
clips_dir = os.path.join(en_dir, "clips")

# Define paths for TSV files
custom_validated_copy1 = os.path.join(en_dir, "custom_validated-Copy1.tsv")
custom_validated = os.path.join(en_dir, "custom_validated.tsv")

# Files to delete
files_to_delete = [
    os.path.join(en_dir, "dev.tsv"),
    os.path.join(en_dir, "test.tsv"),
    os.path.join(en_dir, "train.tsv")
]

# 1. Copy all MP3 files from clips-Copy1 to clips
print(f"Copying MP3 files from {clips_copy1_dir} to {clips_dir}")
if not os.path.exists(clips_dir):
    os.makedirs(clips_dir)

mp3_files = glob.glob(os.path.join(clips_copy1_dir, "*.mp3"))
for mp3_file in mp3_files:
    dest_file = os.path.join(clips_dir, os.path.basename(mp3_file))
    shutil.copy2(mp3_file, dest_file)

print(f"Copied {len(mp3_files)} MP3 files")

# 2. Append rows from custom_validated-Copy1.tsv to custom_validated.tsv
print(f"Appending rows from {custom_validated_copy1} to {custom_validated}")

# Read header and data from the Copy1 file
with open(custom_validated_copy1, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Skip header and get data rows
data_rows = lines[1:]

# Append to the target file
with open(custom_validated, 'a', encoding='utf-8') as f:
    f.writelines(data_rows)

print(f"Appended {len(data_rows)} rows")

# 3. Delete specified TSV files
for file_path in files_to_delete:
    if os.path.exists(file_path):
        os.remove(file_path)
        print(f"Deleted {file_path}")
    else:
        print(f"File not found, skipping: {file_path}")

print("All operations completed successfully!")
