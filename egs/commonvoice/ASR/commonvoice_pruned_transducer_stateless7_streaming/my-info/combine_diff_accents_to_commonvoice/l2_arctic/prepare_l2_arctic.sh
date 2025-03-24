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
#    - Install required packages (gdown, tqdm)
#    - Download the dataset from Google Drive
#    - Extract the dataset to the specified directory
#    - Remove the downloaded archive file
# 5. If --use-cn-accented-only is specified, only extracts Chinese-accented speakers
# 6. Converts WAV files to MP3 format (32kHz, mono)
# 7. Creates a custom_validated.tsv file in CommonVoice format
# 8. If --merge-into-dir is specified, merges the data into the target directory

set -e  # Exit on error

# Parse command line arguments
output_dir="./l2_arctic_data"
use_cn_accented_only=false
merge_into_dir=""

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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if the output directory already exists
if [ -d "$output_dir" ]; then
  echo "Output directory $output_dir already exists."
  echo "Skipping download to save time. If you want to re-download, please remove the directory first."
else
  # Check if the download script exists
  download_script="download_l2_arctic_ds_from_official_site.py"
  if [ ! -f "$download_script" ]; then
    echo "Error: $download_script not found in the current directory."
    echo "Please make sure the script is in the same directory as prepare_l2_arctic.sh"
    exit 1
  fi

  # Make the script executable if it's not already
  chmod +x "$download_script"

  # Run the download script
  echo "Starting L2-Arctic dataset download and extraction..."
  python3 "$download_script" --output-dir "$output_dir"

  # Check if download was successful
  if [ $? -eq 0 ]; then
    echo "L2-Arctic dataset preparation completed successfully."
    echo "Dataset is available at: $output_dir"
  else
    echo "Error: Failed to download or extract the L2-Arctic dataset."
    exit 1
  fi
fi

# Check if conda is available
if ! command -v conda &> /dev/null; then
  echo "Error: conda is not installed or not in PATH"
  exit 1
fi

# Check if parallel is installed, and install if needed
if ! command -v parallel &> /dev/null; then
  echo "GNU Parallel not found. Installing..."
  conda install -y -c conda-forge parallel
fi

# Check if ffmpeg is installed, and install if needed
if ! command -v ffmpeg &> /dev/null; then
  echo "FFmpeg not found. Installing..."
  conda install -y -c conda-forge ffmpeg
fi

# Check if pydub is installed, and install if needed
if ! python3 -c "import pydub" &> /dev/null; then
  echo "pydub not found. Installing..."
  pip install pydub
fi

# Determine the number of CPU cores for parallel processing
num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "Detected $num_cores CPU cores. Will use parallel processing."

# Avoid the GNU Parallel citation notice
export PARALLEL_SHELL=/bin/bash
mkdir -p ~/.parallel
touch ~/.parallel/will-cite

# For very large systems, limit to a reasonable number
# to avoid I/O bottlenecks but still maximize throughput
if [ $num_cores -gt 32 ]; then
  effective_cores=32
  echo "System has $num_cores cores, but limiting parallel processing to $effective_cores jobs to avoid I/O bottlenecks"
else
  effective_cores=$num_cores
fi

# Check for GPU availability (NVIDIA)
has_gpu=false
if command -v nvidia-smi &> /dev/null; then
  nvidia-smi &> /dev/null
  if [ $? -eq 0 ]; then
    has_gpu=true
    echo "NVIDIA GPU detected. Will attempt to use GPU acceleration."
  fi
fi

# Create a Python script to convert L2-Arctic to CommonVoice format
cat > convert_l2arctic_to_cv_format.py << 'EOL'
#!/usr/bin/env python3
import os
import argparse
import hashlib
import uuid
import random
import string
import sys
from pathlib import Path
import glob
from pydub import AudioSegment
import zipfile

def parse_arguments():
    parser = argparse.ArgumentParser(description="Convert L2-Arctic format to CommonVoice dataset format")
    parser.add_argument("--l2_arctic_dir", type=str, required=True, help="L2-Arctic data directory")
    parser.add_argument("--output_dir", type=str, default="clips", help="Directory where MP3 files will be saved")
    parser.add_argument("--output_tsv", type=str, default="custom_validated.tsv", help="Output TSV filename")
    parser.add_argument("--cn_accented_only", action="store_true", help="Process only Chinese-accented speakers")
    parser.add_argument("--skip_audio_conversion", action="store_true", help="Skip audio conversion if MP3 files already exist")
    return parser.parse_args()

def generate_client_id():
    """Generate a random client_id with consistent length"""
    random_string = str(uuid.uuid4()) + ''.join(random.choices(string.ascii_lowercase + string.digits, k=20))
    hashed = hashlib.sha256(random_string.encode()).hexdigest()
    while len(hashed) < 128:
        hashed += hashlib.sha256(hashed.encode()).hexdigest()
    return hashed[:128]

def format_sentence(sentence):
    """Format sentence properly (lowercase with first letter capitalized)"""
    if not sentence:
        return ""
    return sentence.strip().lower().capitalize()

def get_transcript_from_txt(txt_file):
    """Extract transcript from a .txt file"""
    try:
        with open(txt_file, 'r', encoding='utf-8') as f:
            return f.read().strip()
    except Exception as e:
        print(f"Error reading transcript from {txt_file}: {e}", file=sys.stderr)
        return ""

def extract_zip_files(l2_arctic_dir, cn_accented_only=False):
    """Extract ZIP files in the L2-Arctic directory"""
    cn_accented_speakers = ["BWC", "LXC", "NCC", "TXHC"]
    
    # Get all ZIP files in the directory
    zip_files = glob.glob(os.path.join(l2_arctic_dir, "*.zip"))
    print(f"Found {len(zip_files)} ZIP files in {l2_arctic_dir}")
    
    # Determine which ZIP files to extract
    if cn_accented_only:
        zip_files_to_extract = [f for f in zip_files if any(speaker in os.path.basename(f) for speaker in cn_accented_speakers)]
        print(f"Will extract {len(zip_files_to_extract)} Chinese-accented speaker ZIP files")
    else:
        zip_files_to_extract = zip_files
        print(f"Will extract all {len(zip_files_to_extract)} ZIP files")
    
    # Extract each ZIP file
    for zip_file in zip_files_to_extract:
        speaker = os.path.basename(zip_file).split('.')[0]
        extract_dir = os.path.join(l2_arctic_dir, speaker)
        
        # Skip if already extracted
        if os.path.exists(extract_dir) and os.path.isdir(extract_dir):
            print(f"Directory {extract_dir} already exists, skipping extraction")
            continue
        
        print(f"Extracting {zip_file} to {extract_dir}")
        try:
            with zipfile.ZipFile(zip_file, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            print(f"Successfully extracted {zip_file}")
        except Exception as e:
            print(f"Error extracting {zip_file}: {e}", file=sys.stderr)
    
    # Return the list of speakers that were extracted
    return [os.path.basename(f).split('.')[0] for f in zip_files_to_extract]

def find_wav_files(speaker_dir):
    """Find WAV files in the speaker directory with the correct structure"""
    # Check for the specific structure you mentioned
    nested_speaker_dir = os.path.join(speaker_dir, os.path.basename(speaker_dir))
    if os.path.exists(nested_speaker_dir) and os.path.isdir(nested_speaker_dir):
        wav_dir = os.path.join(nested_speaker_dir, "wav")
        if os.path.exists(wav_dir) and os.path.isdir(wav_dir):
            wav_files = glob.glob(os.path.join(wav_dir, "*.wav"))
            if wav_files:
                return wav_files, wav_dir
    
    # Try other possible locations
    possible_wav_dirs = [
        os.path.join(speaker_dir, "wav"),
        os.path.join(speaker_dir, "arctic_wav"),
        os.path.join(speaker_dir, "wav48"),
        speaker_dir
    ]
    
    for wav_dir in possible_wav_dirs:
        if os.path.exists(wav_dir) and os.path.isdir(wav_dir):
            wav_files = glob.glob(os.path.join(wav_dir, "*.wav"))
            if wav_files:
                return wav_files, wav_dir
    
    # If we get here, no WAV files were found
    return [], None

def find_transcript_file(speaker_dir, base_name, wav_dir):
    """Find transcript file for a WAV file"""
    # Check for transcript in the same directory structure as WAV files
    nested_speaker_dir = os.path.join(speaker_dir, os.path.basename(speaker_dir))
    
    # Try different possible locations for transcript files
    possible_transcript_locations = [
        os.path.join(nested_speaker_dir, "transcript", f"{base_name}.txt"),
        os.path.join(nested_speaker_dir, "etc", f"{base_name}.txt"),
        os.path.join(speaker_dir, "transcript", f"{base_name}.txt"),
        os.path.join(speaker_dir, "txt", f"{base_name}.txt"),
        os.path.join(speaker_dir, "etc", "txt", f"{base_name}.txt"),
        os.path.join(speaker_dir, "etc", f"{base_name}.txt"),
        os.path.join(wav_dir, "..", "transcript", f"{base_name}.txt"),
        os.path.join(wav_dir, "..", "txt", f"{base_name}.txt")
    ]
    
    for txt_file in possible_transcript_locations:
        if os.path.exists(txt_file):
            return txt_file
    
    # If we get here, no transcript file was found
    return None

def main():
    args = parse_arguments()
    
    # Create output directory if it doesn't exist
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Extract ZIP files first
    extracted_speakers = extract_zip_files(args.l2_arctic_dir, args.cn_accented_only)
    
    # Define Chinese-accented speakers
    cn_accented_speakers = ["BWC", "LXC", "NCC", "TXHC"]
    
    # Determine which speakers to process
    if args.cn_accented_only:
        speakers_to_process = [s for s in extracted_speakers if s in cn_accented_speakers]
        print(f"Processing only Chinese-accented speakers: {speakers_to_process}")
    else:
        speakers_to_process = extracted_speakers
        print(f"Processing all speakers: {speakers_to_process}")
    
    # Process each speaker
    processed_files = []
    
    for speaker in speakers_to_process:
        speaker_dir = os.path.join(args.l2_arctic_dir, speaker)
        
        # Check if speaker directory exists
        if not os.path.exists(speaker_dir):
            print(f"Warning: Speaker directory {speaker_dir} not found, skipping")
            continue
        
        # Find WAV files
        wav_files, wav_dir = find_wav_files(speaker_dir)
        
        if not wav_files:
            print(f"Warning: No WAV files found for speaker {speaker}, skipping")
            continue
        
        print(f"Found {len(wav_files)} WAV files for speaker {speaker} in {wav_dir}")
        
        # Process each WAV file
        for wav_path in wav_files:
            wav_filename = os.path.basename(wav_path)
            base_name = os.path.splitext(wav_filename)[0]
            
            # Create MP3 filename
            mp3_name = f"{speaker}_{base_name}.mp3"
            mp3_path = os.path.join(args.output_dir, mp3_name)
            
            # Check if MP3 already exists
            mp3_exists = os.path.exists(mp3_path)
            
            # Convert WAV to MP3 if needed
            if not args.skip_audio_conversion and not mp3_exists:
                try:
                    audio = AudioSegment.from_wav(wav_path)
                    audio = audio.set_frame_rate(32000).set_channels(1)
                    audio.export(mp3_path, format="mp3")
                    mp3_exists = True
                    print(f"Processed: {wav_filename} -> {mp3_name}")
                except Exception as e:
                    print(f"Error converting {wav_filename}: {e}", file=sys.stderr)
                    continue
            
            # Only add to processed_files if MP3 exists
            if mp3_exists:
                # Find transcript file
                txt_file = find_transcript_file(speaker_dir, base_name, wav_dir)
                
                text = ""
                if txt_file:
                    text = get_transcript_from_txt(txt_file)
                else:
                    print(f"Warning: No transcript found for {wav_filename}")
                
                # Format sentence
                formatted_text = format_sentence(text)
                
                # Generate IDs
                sentence_id = hashlib.sha256(formatted_text.encode()).hexdigest()
                client_id = generate_client_id()
                
                processed_files.append({
                    'client_id': client_id,
                    'path': mp3_name,
                    'sentence_id': sentence_id,
                    'sentence': formatted_text,
                    'speaker': speaker,
                    'uttid': base_name
                })
    
    # Check if we have processed files
    if not processed_files:
        print("No files were processed. Check if WAV files exist or if paths are correct.")
        return
    
    # Write to TSV file
    with open(args.output_tsv, 'w', encoding='utf-8') as f:
        f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
        
        for file_info in processed_files:
            # Write the TSV line with the same format as CommonVoice
            f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")
    
    print(f"Added {len(processed_files)} entries to {args.output_tsv}")
    
    # Verify counts match
    mp3_count = len([f for f in os.listdir(args.output_dir) if f.endswith('.mp3')])
    print(f"MP3 files in {args.output_dir}: {mp3_count}")
    print(f"TSV entries: {len(processed_files)}")

if __name__ == "__main__":
    main()
EOL

# Make the script executable
chmod +x convert_l2arctic_to_cv_format.py

# Check if clips folder already exists and contains MP3 files
if [ -d "en/clips" ] && [ "$(find en/clips -name "*.mp3" | wc -l)" -gt 0 ]; then
    echo "en/clips folder with MP3 files already exists. Skipping conversion from WAV to MP3..."
    
    # Check if custom_validated.tsv exists in en directory
    if [ ! -f "en/custom_validated.tsv" ]; then
        echo "Warning: en/clips folder exists but en/custom_validated.tsv not found. Running conversion script to generate TSV file only..."
        python convert_l2arctic_to_cv_format.py --l2_arctic_dir="$output_dir" --output_dir="en/clips" --output_tsv="en/custom_validated.tsv" --skip_audio_conversion $([ "$use_cn_accented_only" = true ] && echo "--cn_accented_only")
    else
        echo "Both en/clips folder and en/custom_validated.tsv exist. Skipping conversion entirely."
    fi
else
    # Check if clips folder exists in current directory
    if [ -d "clips" ] && [ "$(find clips -name "*.mp3" | wc -l)" -gt 0 ]; then
        echo "clips folder with MP3 files exists in current directory. Skipping conversion from WAV to MP3..."
        
        # Check if custom_validated.tsv exists
        if [ ! -f "custom_validated.tsv" ]; then
            echo "Warning: clips folder exists but custom_validated.tsv not found. Running conversion script to generate TSV file only..."
            python convert_l2arctic_to_cv_format.py --l2_arctic_dir="$output_dir" --output_dir="clips" --skip_audio_conversion $([ "$use_cn_accented_only" = true ] && echo "--cn_accented_only")
        else
            echo "Both clips folder and custom_validated.tsv exist. Skipping conversion entirely."
        fi
    else
        echo "Converting WAV files to MP3 using FFmpeg with parallel processing..."
        
        # Determine output directory based on merge_into_dir parameter
        if [ -n "$merge_into_dir" ]; then
            # Ensure target directory exists
            mkdir -p "$merge_into_dir/en/clips"
            output_clips_dir="$merge_into_dir/en/clips"
            output_tsv="$merge_into_dir/en/custom_validated.tsv"
            echo "Will output MP3 files directly to $output_clips_dir"
        else
            # Create local clips directory if it doesn't exist
            mkdir -p clips
            output_clips_dir="clips"
            output_tsv="custom_validated.tsv"
        fi
        
        # Run the conversion script
        echo "Running conversion script to generate MP3 files and TSV file..."
        python convert_l2arctic_to_cv_format.py --l2_arctic_dir="$output_dir" --output_dir="$output_clips_dir" --output_tsv="$output_tsv" $([ "$use_cn_accented_only" = true ] && echo "--cn_accented_only")
    fi
    
    # Handle the TSV and directory operations based on merge_into_dir parameter
    if [ -n "$merge_into_dir" ]; then
        # We're merging into an existing directory
        echo "Merging data into $merge_into_dir..."
        
        # Create target directories if they don't exist
        mkdir -p "$merge_into_dir/en"
        
        # Check if target TSV exists
        if [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
            echo "Target custom_validated.tsv exists, merging data..."
            
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
            if [ -f "custom_validated.tsv" ]; then
                source_tsv="custom_validated.tsv"
            elif [ -f "en/custom_validated.tsv" ]; then
                source_tsv="en/custom_validated.tsv"
            else
                echo "Error: Could not find source TSV file to merge"
                exit 1
            fi
            
            python merge_tsv_files.py --source="$source_tsv" --target="$merge_into_dir/en/custom_validated.tsv" --output="$merge_into_dir/en/custom_validated.tsv.new"
            mv "$merge_into_dir/en/custom_validated.tsv.new" "$merge_into_dir/en/custom_validated.tsv"
            
            echo "Data successfully merged into $merge_into_dir"
            echo "Local processing complete. When using merge mode, local 'en' directory is not created to save space."
            
            # Skip creating local en directory when merging
            skip_local_processing=true
        else
            # Target TSV doesn't exist, create it from scratch
            echo "Target custom_validated.tsv doesn't exist, creating it..."
            
            if [ -f "custom_validated.tsv" ]; then
                cp custom_validated.tsv "$merge_into_dir/en/custom_validated.tsv"
            elif [ -f "en/custom_validated.tsv" ]; then
                cp en/custom_validated.tsv "$merge_into_dir/en/custom_validated.tsv"
            else
                echo "Error: Could not find TSV file to copy to target location"
                exit 1
            fi
            
            echo "Data successfully initialized in $merge_into_dir"
            echo "Local processing complete. When using merge mode, local 'en' directory is not created to save space."
            
            # Skip creating local en directory when merging
            skip_local_processing=true
        fi
    fi
    
    # Only create and process local en directory if we're not in merge mode
    if [ -z "$merge_into_dir" ] || [ "$skip_local_processing" != "true" ]; then
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
            # Check if en/clips already exists
            if [ -d "en/clips" ]; then
                echo "Warning: en/clips already exists. Moving files instead of the whole directory."
                # Move all MP3 files from clips to en/clips
                find clips -name "*.mp3" -exec mv {} en/clips/ \;
                echo "Moved MP3 files from clips to en/clips."
                # Remove the original clips directory
                rm -rf clips
                echo "Removed original clips directory."
            else
                mv clips en/
                echo "Moved clips folder to en directory."
            fi
        else
            echo "Warning: clips folder not found."
        fi
        
        if [ -f "custom_validated.tsv" ]; then
            # Check if en/custom_validated.tsv already exists
            if [ -f "en/custom_validated.tsv" ]; then
                echo "Warning: en/custom_validated.tsv already exists. Skipping move operation."
            else
                mv custom_validated.tsv en/
                echo "Moved custom_validated.tsv to en directory."
            fi
        else
            echo "Warning: custom_validated.tsv file not found."
        fi
    fi
fi

echo "L2-Arctic dataset preparation completed successfully."
if [ "$use_cn_accented_only" = true ]; then
    echo "Only Chinese-accented speakers (BWC, LXC, NCC, TXHC) were processed."
else
    echo "All speakers were processed."
fi

if [ -n "$merge_into_dir" ]; then
    echo "Data was merged into: $merge_into_dir"
else
    echo "Data is available in the 'en' directory."
fi