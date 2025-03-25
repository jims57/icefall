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
# Important: download_l2_arctic_ds_from_official_site.py must be in the same directory
# before running these commands.
#
# Download L2-Arctic dataset to default location (./l2_arctic_data):
# bash prepare_l2_arctic.sh
#
# Download to a specific directory:
# bash prepare_l2_arctic.sh --output-dir /path/to/custom/directory
#
# Limit total hours of audio:
# bash prepare_l2_arctic.sh --total-hours 1.5
#
# Use only Chinese-accented speakers:
# bash prepare_l2_arctic.sh --use-cn-accented-only
#
# Merge into existing dataset:
# bash prepare_l2_arctic.sh --merge-into-dir /path/to/target/dataset
#
# This script:
# 1. Checks if the output directory already exists (skips download if it does)
# 2. Checks if the download script exists
# 3. Runs the download script to fetch the L2-Arctic dataset
# 4. The download script will:
#    - Install required packages (requests, tqdm, librosa)
#    - Download the dataset from Hugging Face
#    - Extract the dataset to the specified directory
# 5. If --use-cn-accented-only is specified, only extracts Chinese-accented speakers
# 6. Converts WAV files to MP3 format (32kHz, mono)
# 7. Creates a custom_validated.tsv file in CommonVoice format
# 8. If --merge-into-dir is specified, merges the data into the target directory

set -e  # Exit on error

# Parse command line arguments
output_dir="./l2_arctic_data"
use_cn_accented_only=false
merge_into_dir=""
total_hours=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --use-cn-accented-only)
      use_cn_accented_only=true
      shift 1
      ;;
    --merge-into-dir)
      merge_into_dir="$2"
      shift 2
      ;;
    --total-hours)
      total_hours="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if the download script exists and the output directory is not yet created
if [ ! -f "download_l2_arctic_ds_from_official_site.py" ]; then
  echo "Error: download_l2_arctic_ds_from_official_site.py not found in the current directory."
  exit 1
fi

# Check if the output directory already exists
if [ -d "$output_dir" ]; then
  echo "Output directory $output_dir already exists."
else
  echo "Output directory $output_dir does not exist. Will download the dataset."
  
  # Download L2-Arctic dataset
  echo "Starting L2-Arctic dataset download and extraction..."
  
  # Set download options based on arguments
  download_options=""
  if [ ! -z "$total_hours" ]; then
    download_options="$download_options --total-hours $total_hours"
  fi
  
  if [ "$use_cn_accented_only" = true ]; then
    download_options="$download_options --use-cn-only"
    echo "Will only use Chinese-accented speakers"
  fi
  
  # Execute download script
  echo "Running: python download_l2_arctic_ds_from_official_site.py --output-dir \"$output_dir\" $download_options"
  python download_l2_arctic_ds_from_official_site.py --output-dir "$output_dir" $download_options
  
  # Check if download was successful and the output directory has content
  if [ $? -ne 0 ] || [ ! "$(ls -A "$output_dir" 2>/dev/null)" ]; then
    echo "Error: Failed to download or extract the L2-Arctic dataset."
    echo "Trying to download again without hour limit..."
    
    # Try again without hour limit if that was set
    if [ ! -z "$total_hours" ]; then
      python download_l2_arctic_ds_from_official_site.py --output-dir "$output_dir"
      
      if [ $? -ne 0 ] || [ ! "$(ls -A "$output_dir" 2>/dev/null)" ]; then
        echo "Error: Failed to download or extract the L2-Arctic dataset after second attempt."
        exit 1
      fi
    else
      exit 1
    fi
  fi
fi

# When using Chinese accented only option, check if required speakers exist
cn_speakers=("BWC" "LXC" "NCC" "TXHC")  # Defined Chinese speakers
cn_found=false

if [ "$use_cn_accented_only" = true ]; then
  # Create a list to track which Chinese speakers were found
  found_cn_speakers=()
  
  for speaker in "${cn_speakers[@]}"; do
    if [ -d "$output_dir/$speaker" ]; then
      cn_found=true
      found_cn_speakers+=("$speaker")
    fi
  done
  
  if [ "$cn_found" = false ]; then
    echo "Error: No Chinese-accented speakers found in the dataset."
    echo "This could be due to incomplete download or extraction issues."
    echo "Please try downloading the dataset without using the --use-cn-accented-only option first."
    exit 1
  fi
  
  echo "Found ${#found_cn_speakers[@]} Chinese-accented speakers: ${found_cn_speakers[*]}"
fi

# Create directories for CommonVoice-like structure
mkdir -p "en/clips"

# Create TSV file
echo -e "client_id\tpath\tsentence\tup_votes\tdown_votes\tage\tgender\taccent\tlocale\tsegment" > en/custom_validated.tsv

# Get list of speakers to process
if [ "$use_cn_accented_only" = true ]; then
  # Use only the Chinese speakers that were actually found
  speakers=("${found_cn_speakers[@]}")
else
  # Process all speakers found in the output directory
  speakers=()
  for dir in "$output_dir"/*/; do
    if [ -d "$dir" ]; then
      speaker=$(basename "$dir")
      # Skip _downloads directory and any hidden directories
      if [[ "$speaker" != "_downloads" && "$speaker" != .* ]]; then
        speakers+=("$speaker")
      fi
    fi
  done
fi

# Make sure we have speakers to process
if [ ${#speakers[@]} -eq 0 ]; then
  echo "Error: No speaker directories found in $output_dir"
  exit 1
fi

echo "Processing speakers: ${speakers[*]}"

# Create a Python script to handle the conversion more reliably
cat > convert_wavs_to_mp3.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import subprocess
import glob
from pathlib import Path
import re

def sanitize_text(text):
    """Sanitize transcript text to avoid special character issues."""
    # Replace problematic characters
    text = text.replace('"', ' ').replace("'", " ")
    # Remove non-printable characters and normalize whitespace
    text = re.sub(r'[^\x20-\x7E\s]', '', text)
    return text.strip()

def find_transcript(wav_file, speaker_dir, txt_dir=None):
    """Find the transcript for a WAV file."""
    # Get the basename without extension
    basename = os.path.basename(wav_file)[:-4]  # Remove .wav
    
    # Try exact match in txt_dir if provided
    if txt_dir:
        for ext in [".txt", ".lab", ".trans.txt"]:
            potential_file = os.path.join(txt_dir, basename + ext)
            if os.path.isfile(potential_file):
                with open(potential_file, 'r', errors='replace') as f:
                    return sanitize_text(f.read())
    
    # Try to find transcript file anywhere in speaker directory
    for ext in [".txt", ".lab", ".trans.txt"]:
        # Use glob to find matching files (case insensitive)
        pattern = os.path.join(speaker_dir, "**", f"*{basename}*{ext}")
        matches = glob.glob(pattern, recursive=True)
        if matches:
            with open(matches[0], 'r', errors='replace') as f:
                return sanitize_text(f.read())
    
    # If no transcript found
    return ""

def process_speaker(speaker, speaker_dir, clips_dir, tsv_file):
    """Process all WAV files for a single speaker."""
    # Find transcript directory
    txt_dir = None
    for potential_dir in ["txt", "transcript", "transcripts", "annotation", "annotations", "text"]:
        potential_path = os.path.join(speaker_dir, potential_dir)
        if os.path.isdir(potential_path):
            txt_dir = potential_path
            print(f"Found transcript directory: {txt_dir}")
            break
    
    # Find all WAV files
    wav_files = glob.glob(os.path.join(speaker_dir, "**", "*.wav"), recursive=True)
    total_files = len(wav_files)
    print(f"Found {total_files} WAV files for speaker {speaker}")
    
    # Process each WAV file
    processed = 0
    for wav_file in wav_files:
        # Get basename without extension
        basename = os.path.basename(wav_file)[:-4]
        
        # Create MP3 filename
        mp3_filename = f"{speaker}_{basename}.mp3"
        mp3_path = os.path.join(clips_dir, mp3_filename)
        
        # Get transcript
        transcript = find_transcript(wav_file, speaker_dir, txt_dir)
        
        # Convert WAV to MP3
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", wav_file, "-ar", "32000", "-ac", "1", "-b:a", "48k", mp3_path
        ]
        try:
            subprocess.run(cmd, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error converting {wav_file}: {e}")
            continue
        
        # Add to TSV
        with open(tsv_file, 'a', encoding='utf-8') as f:
            f.write(f"{speaker}\tclips/{mp3_filename}\t{transcript}\t1\t0\t\t\t{speaker}\ten\t\n")
        
        # Update progress
        processed += 1
        if processed % 20 == 0 or processed == total_files:
            print(f"Speaker {speaker}: Processed {processed}/{total_files} files")
    
    print(f"COMPLETED: Speaker {speaker} - processed {processed} files")
    return processed

def main():
    if len(sys.argv) < 4:
        print("Usage: python convert_wavs_to_mp3.py <output_dir> <speakers> <tsv_file>")
        sys.exit(1)
    
    output_dir = sys.argv[1]
    speakers = sys.argv[2].split(',')
    tsv_file = sys.argv[3]
    clips_dir = os.path.dirname(tsv_file) + "/clips"
    
    # Make sure clips directory exists
    os.makedirs(clips_dir, exist_ok=True)
    
    # Process each speaker
    total_processed = 0
    for speaker in speakers:
        speaker_dir = os.path.join(output_dir, speaker)
        if not os.path.isdir(speaker_dir):
            print(f"Warning: Speaker directory {speaker_dir} not found, skipping")
            continue
        
        processed = process_speaker(speaker, speaker_dir, clips_dir, tsv_file)
        total_processed += processed
    
    # Verify final counts
    mp3_count = len(glob.glob(os.path.join(clips_dir, "*.mp3")))
    tsv_count = sum(1 for _ in open(tsv_file, 'r')) - 1  # Subtract header
    
    print(f"\nConversion complete.")
    print(f"Total files processed: {total_processed}")
    print(f"MP3 files in {clips_dir}: {mp3_count}")
    print(f"Entries in TSV file: {tsv_count}")
    
    if mp3_count != tsv_count:
        print(f"WARNING: MP3 count ({mp3_count}) doesn't match TSV entry count ({tsv_count})")

if __name__ == "__main__":
    main()
EOL

# Make the script executable
chmod +x convert_wavs_to_mp3.py

# Run the Python script to convert WAV files to MP3
echo "Converting WAV files to MP3 and creating the TSV file..."
python convert_wavs_to_mp3.py "$output_dir" "$(IFS=,; echo "${speakers[*]}")" "$(pwd)/en/custom_validated.tsv"

# Verify the TSV file
tsv_lines=$(wc -l < en/custom_validated.tsv)
tsv_count=$((tsv_lines - 1))  # Subtract header line
echo "Verified TSV has $tsv_count entries (excluding header)."

# Count MP3 files in clips directory for verification
mp3_count=$(find "en/clips" -name "*.mp3" | wc -l)
echo "MP3 files in en/clips: $mp3_count"

# Verify that MP3 count matches TSV entry count
if [ "$mp3_count" -ne "$tsv_count" ]; then
  echo "Warning: MP3 count ($mp3_count) does not match TSV entry count ($tsv_count)"
  echo "Cleaning up orphaned MP3 files..."
  
  # Create a script to clean up orphaned MP3 files
  cat > cleanup_mp3s.py << 'EOL'
#!/usr/bin/env python3
import os
import csv
from pathlib import Path

# Read valid MP3 files from TSV
valid_mp3s = set()
with open('en/custom_validated.tsv', 'r', encoding='utf-8') as f:
    reader = csv.reader(f, delimiter='\t')
    next(reader)  # Skip header
    for row in reader:
        if len(row) > 1:
            path = row[1]
            if path:
                valid_mp3s.add(os.path.basename(path))

print(f"Found {len(valid_mp3s)} valid MP3 filenames in TSV")

# Find and delete MP3 files not in the TSV
clips_dir = Path('en/clips')
deleted_count = 0
for mp3_file in clips_dir.glob("*.mp3"):
    if mp3_file.name not in valid_mp3s:
        mp3_file.unlink()
        deleted_count += 1
        if deleted_count % 10 == 0:
            print(f"Deleted {deleted_count} files so far...")

print(f"Deleted {deleted_count} MP3 files not referenced in the TSV")

# Count remaining MP3 files
remaining_count = len(list(clips_dir.glob("*.mp3")))
print(f"Remaining MP3 files in clips directory: {remaining_count}")
EOL
  
  chmod +x cleanup_mp3s.py
  python cleanup_mp3s.py
  
  # Verify again
  mp3_count=$(find "en/clips" -name "*.mp3" | wc -l)
  echo "MP3 files in en/clips after cleanup: $mp3_count"
fi

# Merge data into target directory if requested
if [ ! -z "$merge_into_dir" ]; then
  echo "Merging data into $merge_into_dir..."
  
  # Create target directory structure if it doesn't exist
  mkdir -p "$merge_into_dir/en/clips"
  
  # If target TSV exists, merge data
  if [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
    echo "Target custom_validated.tsv exists, merging data..."
    
    # Count entries in target file before merging
    target_count_before=$(tail -n +2 "$merge_into_dir/en/custom_validated.tsv" | wc -l)
    source_count=$(tail -n +2 "en/custom_validated.tsv" | wc -l)
    expected_total=$((target_count_before + source_count))
    
    echo "Target TSV entries before merging: $target_count_before"
    echo "Source TSV entries to add: $source_count"
    echo "Expected total after merging: $expected_total"
    
    # Preserve the header
    head -n 1 "$merge_into_dir/en/custom_validated.tsv" > "${merge_into_dir}/en/temp_header.tsv"
    
    # Concatenate all entries (excluding headers)
    tail -n +2 "$merge_into_dir/en/custom_validated.tsv" > "${merge_into_dir}/en/temp_existing.tsv"
    tail -n +2 "en/custom_validated.tsv" > "${merge_into_dir}/en/temp_new.tsv"
    
    # Create a new file with header + all entries
    cat "${merge_into_dir}/en/temp_header.tsv" "${merge_into_dir}/en/temp_existing.tsv" "${merge_into_dir}/en/temp_new.tsv" > "${merge_into_dir}/en/merged.tsv"
    
    # Replace the target file with the merged file
    mv "${merge_into_dir}/en/merged.tsv" "$merge_into_dir/en/custom_validated.tsv"
    
    # Clean up temporary files
    rm -f "${merge_into_dir}/en/temp_header.tsv" "${merge_into_dir}/en/temp_existing.tsv" "${merge_into_dir}/en/temp_new.tsv"
    
    # Copy MP3 files
    echo "Copying MP3 files to target clips directory..."
    cp "en/clips"/*.mp3 "$merge_into_dir/en/clips/"
    
    # Verify MP3 count matches TSV entry count after merging
    mp3_count=$(find "$merge_into_dir/en/clips" -name "*.mp3" | wc -l)
    tsv_entry_count=$(tail -n +2 "$merge_into_dir/en/custom_validated.tsv" | wc -l)
    
    echo "MP3 files in target clips directory: $mp3_count"
    echo "Entries in target custom_validated.tsv: $tsv_entry_count"
    echo "Expected entries: $expected_total"
    
    # Check if the merged count matches the expected total
    if [ "$tsv_entry_count" -ne "$expected_total" ]; then
      echo "Warning: Merged TSV count ($tsv_entry_count) doesn't match expected total ($expected_total)"
    fi
  else
    # If target TSV doesn't exist, copy our files
    echo "Target custom_validated.tsv doesn't exist, copying files..."
    cp "en/custom_validated.tsv" "$merge_into_dir/en/"
    cp "en/clips"/*.mp3 "$merge_into_dir/en/clips/"
  fi
  
  echo "Merge complete!"
fi

echo "All processing completed successfully!"
    
    if [ "$mp3_count" -ne "$tsv_entry_count" ]; then
      echo "Warning: Mismatch between MP3 count ($mp3_count) and TSV entry count ($tsv_entry_count)"
      echo "Cleaning up orphaned MP3 files in target directory..."
      
      # Create a script to delete MP3 files not in the TSV
      cat > delete_unused_mp3s.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import csv
from pathlib import Path

def main():
    if len(sys.argv) != 3:
        print("Usage: python delete_unused_mp3s.py <tsv_file> <clips_dir>")
        sys.exit(1)
    
    tsv_file = sys.argv[1]
    clips_dir = Path(sys.argv[2])
    
    # Extract MP3 filenames from TSV
    valid_mp3s = set()
    with open(tsv_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        next(reader)  # Skip header
        for row in reader:
            if len(row) > 1:
                path = row[1]
                if path:
                    valid_mp3s.add(os.path.basename(path))
    
    print(f"Found {len(valid_mp3s)} valid MP3 filenames in TSV")
    
    # Find and delete MP3 files not in the TSV
    deleted_count = 0
    for mp3_file in clips_dir.glob("*.mp3"):
        if mp3_file.name not in valid_mp3s:
            mp3_file.unlink()
            deleted_count += 1
            if deleted_count % 100 == 0:
                print(f"Deleted {deleted_count} files so far...")
    
    print(f"Deleted {deleted_count} MP3 files not referenced in the TSV")
    
    # Count remaining MP3 files
    remaining_count = len(list(clips_dir.glob("*.mp3")))
    print(f"Remaining MP3 files in clips directory: {remaining_count}")

if __name__ == "__main__":
    main()
EOL
      
      chmod +x delete_unused_mp3s.py
      
      # Run the script to delete unused MP3 files
      echo "Deleting MP3 files not referenced in the TSV..."
      python delete_unused_mp3s.py "$merge_into_dir/en/custom_validated.tsv" "$merge_into_dir/en/clips"
      
      # Verify again
      mp3_count=$(find "$merge_into_dir/en/clips" -name "*.mp3" | wc -l)
      echo "MP3 files in target clips directory after cleanup: $mp3_count"
    else
    # If target TSV doesn't exist, simply copy the files
    echo "Target custom_validated.tsv does not exist, copying all files..."
    cp "en/custom_validated.tsv" "$merge_into_dir/en/"
    cp "en/clips"/*.mp3 "$merge_into_dir/en/clips/"
  fi
  
  echo "Merge completed."
fi

echo "L2-Arctic dataset preparation complete."