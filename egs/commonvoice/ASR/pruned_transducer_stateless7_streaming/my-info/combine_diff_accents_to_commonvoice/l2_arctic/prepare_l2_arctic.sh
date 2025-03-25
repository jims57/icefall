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

# Check if the output directory already exists
if [ -d "$output_dir" ]; then
  echo "Output directory $output_dir already exists."
  
  # Check if ZIP files already exist
  cn_speakers=("BWC" "LXC" "NCC" "TXHC")
  cn_zips_exist=true
  
  for speaker in "${cn_speakers[@]}"; do
    if [ ! -f "$output_dir/$speaker.zip" ]; then
      cn_zips_exist=false
      break
    fi
  done
  
  if [ "$use_cn_accented_only" = true ] && [ "$cn_zips_exist" = true ]; then
    echo "Chinese-accented speaker ZIP files already exist. Skipping download."
  elif [ -f "$output_dir/ABA.zip" ] && [ -f "$output_dir/BWC.zip" ]; then
    # Check for at least two ZIP files as a heuristic for a complete download
    echo "ZIP files already exist in $output_dir. Skipping download."
  else
    echo "ZIP files not found in $output_dir. Will download the dataset."
    # Remove the directory to force a clean download
    rm -rf "$output_dir"
  fi
else
  echo "Output directory $output_dir does not exist. Will download the dataset."
fi

# Only download if the directory doesn't exist
if [ ! -d "$output_dir" ]; then
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
  if [ -n "$total_hours" ]; then
    python3 "$download_script" --output-dir "$output_dir" --total-hours "$total_hours"
  else
    python3 "$download_script" --output-dir "$output_dir"
  fi

  # Check if download was successful
  if [ $? -ne 0 ]; then
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
    
    # Determine which speakers to process
    if cn_accented_only:
        speakers_to_process = cn_accented_speakers
    else:
        # Get all ZIP files to determine all speakers
        zip_files = glob.glob(os.path.join(l2_arctic_dir, "*.zip"))
        speakers_to_process = [os.path.basename(f).split('.')[0] for f in zip_files]
    
    # Check which speakers need extraction
    speakers_to_extract = []
    for speaker in speakers_to_process:
        speaker_dir = os.path.join(l2_arctic_dir, speaker)
        nested_speaker_dir = os.path.join(speaker_dir, speaker)
        wav_dir = os.path.join(nested_speaker_dir, "wav") if os.path.exists(nested_speaker_dir) else None
        
        # Check if the speaker directory is already properly extracted
        if (os.path.exists(speaker_dir) and 
            ((os.path.exists(nested_speaker_dir) and os.path.isdir(nested_speaker_dir)) or
             (wav_dir and os.path.isdir(wav_dir) and len(glob.glob(os.path.join(wav_dir, "*.wav"))) > 0))):
            print(f"Speaker {speaker} already extracted, skipping extraction")
        else:
            # Need to extract this speaker
            speakers_to_extract.append(speaker)
    
    # Extract only the speakers that need extraction
    for speaker in speakers_to_extract:
        zip_file = os.path.join(l2_arctic_dir, f"{speaker}.zip")
        if not os.path.exists(zip_file):
            print(f"Warning: ZIP file for speaker {speaker} not found at {zip_file}")
            continue
            
        extract_dir = os.path.join(l2_arctic_dir, speaker)
        print(f"Extracting {zip_file} to {extract_dir}")
        try:
            with zipfile.ZipFile(zip_file, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            print(f"Successfully extracted {zip_file}")
        except Exception as e:
            print(f"Error extracting {zip_file}: {e}", file=sys.stderr)
    
    # Return all speakers to process, not just the ones we extracted
    return speakers_to_process

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
    
    # Check if MP3 files already exist
    existing_mp3_files = glob.glob(os.path.join(args.output_dir, "*.mp3"))
    if existing_mp3_files and args.skip_audio_conversion:
        print(f"Found {len(existing_mp3_files)} existing MP3 files in {args.output_dir}")
        print("Skipping audio conversion as requested")
        
        # Check if TSV file exists
        if os.path.exists(args.output_tsv):
            print(f"TSV file {args.output_tsv} already exists")
            print("Skipping TSV generation")
            return
        else:
            print(f"TSV file {args.output_tsv} does not exist")
            print("Will generate TSV file from existing MP3 files")
            # Continue with the rest of the script to generate TSV
    
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
            mkdir -p en/clips
            output_clips_dir="en/clips"
            output_tsv="en/custom_validated.tsv"
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
            if [ -f "en/custom_validated.tsv" ]; then
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
            
            if [ -f "en/custom_validated.tsv" ]; then
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

# Create a Python script to split the data into train, dev, and test sets
cat > split_data.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import os
import random
from pathlib import Path

def parse_args():
    parser = argparse.ArgumentParser(
        description="Create train, dev, and test TSV files from custom_validated.tsv."
    )
    parser.add_argument(
        "--dev-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for dev set.",
    )
    parser.add_argument(
        "--test-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for test set.",
    )
    parser.add_argument(
        "--custom-validated-tsv",
        type=str,
        required=True,
        help="Path to the custom_validated.tsv file.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility.",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=".",
        help="Directory to write the output TSV files.",
    )
    return parser.parse_args()

def write_tsv_file(filename, header, rows):
    """Write rows to a TSV file with the given header."""
    with open(filename, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(header)
        writer.writerows(rows)

def main():
    args = parse_args()
    
    # Validate the input parameters
    if args.dev_ratio + args.test_ratio >= 1.0:
        raise ValueError("The sum of dev_ratio and test_ratio should be less than 1.0")
    
    # Create output directory if it doesn't exist
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Read all rows from custom_validated.tsv
    all_rows = []
    with open(args.custom_validated_tsv, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)  # Get the header
        for row in reader:
            all_rows.append(row)
    
    print(f"Total data rows in {args.custom_validated_tsv}: {len(all_rows)}")
    
    # Shuffle the rows to ensure randomness in the split
    random.seed(args.seed)
    random.shuffle(all_rows)
    
    num_to_select = len(all_rows)
    
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
            dev_size = max(1, round(num_to_select * args.dev_ratio))
            test_size = max(1, round(num_to_select * args.test_ratio))
            
            # Ensure we don't over-allocate (leaving no train data)
            if dev_size + test_size >= num_to_select:
                dev_size = 1
                test_size = 1
                
            # All remaining rows go to train
            train_size = num_to_select - dev_size - test_size
    else:
        # If we have fewer than 3 rows, prioritize train set
        print("Warning: Not enough data for all three splits. Prioritizing train set.")
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
    
    print(f"Creating dev.tsv with {dev_size} data rows")
    print(f"Creating test.tsv with {test_size} data rows")
    print(f"Creating train.tsv with {train_size} data rows")
    print(f"Total data rows in all splits: {dev_size + test_size + train_size}")
    
    # Verify the total count is correct
    assert dev_size + test_size + train_size == num_to_select, \
           f"Row count mismatch: {dev_size} + {test_size} + {train_size} != {num_to_select}"
    
    # Split the rows
    dev_rows = all_rows[:dev_size]
    test_rows = all_rows[dev_size:dev_size + test_size]
    train_rows = all_rows[dev_size + test_size:]
    
    # Double-check that all rows are accounted for
    assert len(dev_rows) + len(test_rows) + len(train_rows) == len(all_rows), \
           f"Error: Not all rows were allocated to splits. Got {len(dev_rows) + len(test_rows) + len(train_rows)} but expected {len(all_rows)}"
    
    # Write the TSV files
    write_tsv_file(os.path.join(args.output_dir, "dev.tsv"), header, dev_rows)
    write_tsv_file(os.path.join(args.output_dir, "test.tsv"), header, test_rows)
    write_tsv_file(os.path.join(args.output_dir, "train.tsv"), header, train_rows)

    # Additional debug info to confirm file sizes
    print(f"Wrote {len(dev_rows)} data rows to dev.tsv")
    print(f"Wrote {len(test_rows)} data rows to test.tsv")
    print(f"Wrote {len(train_rows)} data rows to train.tsv")
    print(f"Each file also has 1 header row")
    
    print("Done!")

if __name__ == "__main__":
    main()
EOL

# Make the script executable
chmod +x split_data.py

# Add code to run the split_data.py script after processing
if [ -z "$merge_into_dir" ]; then
    # If we're not in merge mode, create the splits in the local en directory
    if [ -f "en/custom_validated.tsv" ]; then
        echo "Creating train, dev, and test splits..."
        python3 split_data.py \
            --custom-validated-tsv="en/custom_validated.tsv" \
            --dev-ratio=0.1 \
            --test-ratio=0.1 \
            --output-dir="en" \
            --seed=42
        
        # Print statistics about the splits
        train_count=$(tail -n +2 en/train.tsv | wc -l)
        dev_count=$(tail -n +2 en/dev.tsv | wc -l)
        test_count=$(tail -n +2 en/test.tsv | wc -l)
        total_count=$((train_count + dev_count + test_count))
        
        echo "Dataset splits created:"
        echo "  - Train set: $train_count utterances"
        echo "  - Dev set: $dev_count utterances"
        echo "  - Test set: $test_count utterances"
        echo "  - Total: $total_count utterances"
    else
        echo "Warning: Cannot create dataset splits - en/custom_validated.tsv not found."
    fi
else
    # If we're in merge mode, create the splits in the target directory
    if [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
        echo "Creating train, dev, and test splits in $merge_into_dir/en..."
        python3 split_data.py \
            --custom-validated-tsv="$merge_into_dir/en/custom_validated.tsv" \
            --dev-ratio=0.1 \
            --test-ratio=0.1 \
            --output-dir="$merge_into_dir/en" \
            --seed=42
        
        # Print statistics about the splits
        train_count=$(tail -n +2 "$merge_into_dir/en/train.tsv" | wc -l)
        dev_count=$(tail -n +2 "$merge_into_dir/en/dev.tsv" | wc -l)
        test_count=$(tail -n +2 "$merge_into_dir/en/test.tsv" | wc -l)
        total_count=$((train_count + dev_count + test_count))
        
        echo "Dataset splits created in $merge_into_dir/en:"
        echo "  - Train set: $train_count utterances"
        echo "  - Dev set: $dev_count utterances"
        echo "  - Test set: $test_count utterances"
        echo "  - Total: $total_count utterances"
    else
        echo "Warning: Cannot create dataset splits - $merge_into_dir/en/custom_validated.tsv not found."
    fi
fi

# After running the conversion script, ensure the TSV file exists in the merge directory
if [ -n "$merge_into_dir" ]; then
    # Check if the TSV file exists in the merge directory
    if [ ! -f "$merge_into_dir/en/custom_validated.tsv" ]; then
        echo "Warning: custom_validated.tsv not found in merge directory."
        
        # Check if we have a local TSV file to copy
        if [ -f "en/custom_validated.tsv" ]; then
            echo "Copying local custom_validated.tsv to merge directory..."
            cp "en/custom_validated.tsv" "$merge_into_dir/en/custom_validated.tsv"
            echo "Successfully copied custom_validated.tsv to $merge_into_dir/en/"
            
            # Verify row count
            local_row_count=$(wc -l < "en/custom_validated.tsv")
            target_row_count=$(wc -l < "$merge_into_dir/en/custom_validated.tsv")
            echo "Local TSV has $local_row_count rows"
            echo "Target TSV has $target_row_count rows"
            
            if [ "$local_row_count" -ne "$target_row_count" ]; then
                echo "Warning: Row count mismatch between local and target TSV files"
                echo "Using local TSV file as the correct version"
                cp "en/custom_validated.tsv" "$merge_into_dir/en/custom_validated.tsv"
            fi
        else
            echo "Error: No custom_validated.tsv file found to copy to merge directory."
            exit 1
        fi
    else
        echo "Found existing custom_validated.tsv in merge directory."
        
        # Check if we need to merge with local TSV
        if [ -f "en/custom_validated.tsv" ]; then
            echo "Creating a clean merge of local custom_validated.tsv with merge directory TSV..."
            
            # Create a Python script for proper TSV merging
            cat > merge_tsv.py << 'EOL'
#!/usr/bin/env python3
import sys
import csv
import os

def main():
    if len(sys.argv) != 4:
        print("Usage: python merge_tsv.py <target_tsv> <source_tsv> <output_tsv>")
        sys.exit(1)
    
    target_file = sys.argv[1]
    source_file = sys.argv[2]
    output_file = sys.argv[3]
    
    # Read the target file (including header)
    target_rows = []
    target_paths = set()
    with open(target_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)
        target_rows.append(header)
        
        for row in reader:
            if len(row) > 1:  # Ensure row has enough columns
                path = row[1]
                target_paths.add(path)
            target_rows.append(row)
    
    # Read the source file (excluding header)
    source_rows = []
    added_count = 0
    with open(source_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        next(reader)  # Skip header
        
        for row in reader:
            if len(row) > 1:  # Ensure row has enough columns
                path = row[1]
                if path not in target_paths:
                    source_rows.append(row)
                    target_paths.add(path)
                    added_count += 1
    
    # Write the merged file
    with open(output_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        for row in target_rows:
            writer.writerow(row)
        for row in source_rows:
            writer.writerow(row)
    
    print(f"Added {added_count} new entries from source to target")
    print(f"Total entries in merged file: {len(target_rows) - 1 + added_count}")

if __name__ == "__main__":
    main()
EOL
            
            chmod +x merge_tsv.py
            
            # Run the merge script
            echo "Merging TSV files..."
            python merge_tsv.py "$merge_into_dir/en/custom_validated.tsv" "en/custom_validated.tsv" "$merge_into_dir/en/custom_validated.tsv.new"
            
            # Replace the original with the merged file
            mv "$merge_into_dir/en/custom_validated.tsv.new" "$merge_into_dir/en/custom_validated.tsv"
            
            # Verify row count
            merged_row_count=$(wc -l < "$merge_into_dir/en/custom_validated.tsv")
            echo "Merged TSV has $merged_row_count rows"
        fi
    fi
    
    # Verify the TSV file exists in the merge directory
    if [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
        echo "Verified: custom_validated.tsv exists in merge directory."
        
        # Count entries in TSV file (excluding header)
        tsv_entry_count=$(tail -n +2 "$merge_into_dir/en/custom_validated.tsv" | wc -l)
        echo "TSV file contains $tsv_entry_count entries (excluding header)"
        
        # Count MP3 files in clips directory
        mp3_count=$(find "$merge_into_dir/en/clips" -name "*.mp3" | wc -l)
        echo "Clips directory contains $mp3_count MP3 files"
    else
        echo "Error: Failed to create custom_validated.tsv in merge directory."
        exit 1
    fi
fi

# After verifying the TSV file exists in the merge directory, regenerate the splits
if [ -n "$merge_into_dir" ] && [ -f "$merge_into_dir/en/custom_validated.tsv" ]; then
    echo "Regenerating train, dev, and test splits in $merge_into_dir/en..."
    
    # Create a Python script to split the data
    cat > regenerate_splits.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import os
import random
from pathlib import Path

def parse_args():
    parser = argparse.ArgumentParser(
        description="Create train, dev, and test TSV files from custom_validated.tsv."
    )
    parser.add_argument(
        "--dev-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for dev set.",
    )
    parser.add_argument(
        "--test-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for test set.",
    )
    parser.add_argument(
        "--custom-validated-tsv",
        type=str,
        required=True,
        help="Path to the custom_validated.tsv file.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility.",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=".",
        help="Directory to write the output TSV files.",
    )
    return parser.parse_args()

def write_tsv_file(filename, header, rows):
    """Write rows to a TSV file with the given header."""
    with open(filename, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(header)
        writer.writerows(rows)

def main():
    args = parse_args()
    
    # Validate the input parameters
    if args.dev_ratio + args.test_ratio >= 1.0:
        raise ValueError("The sum of dev_ratio and test_ratio should be less than 1.0")
    
    # Create output directory if it doesn't exist
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Read all rows from custom_validated.tsv
    all_rows = []
    with open(args.custom_validated_tsv, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)  # Get the header
        for row in reader:
            all_rows.append(row)
    
    print(f"Total data rows in {args.custom_validated_tsv}: {len(all_rows)}")
    
    # Shuffle the rows to ensure randomness in the split
    random.seed(args.seed)
    random.shuffle(all_rows)
    
    # Calculate the number of rows for each split
    dev_size = max(1, int(len(all_rows) * args.dev_ratio))
    test_size = max(1, int(len(all_rows) * args.test_ratio))
    train_size = len(all_rows) - dev_size - test_size
    
    print(f"Creating dev.tsv with {dev_size} data rows")
    print(f"Creating test.tsv with {test_size} data rows")
    print(f"Creating train.tsv with {train_size} data rows")
    
    # Split the rows
    dev_rows = all_rows[:dev_size]
    test_rows = all_rows[dev_size:dev_size + test_size]
    train_rows = all_rows[dev_size + test_size:]
    
    # Write the TSV files
    write_tsv_file(os.path.join(args.output_dir, "dev.tsv"), header, dev_rows)
    write_tsv_file(os.path.join(args.output_dir, "test.tsv"), header, test_rows)
    write_tsv_file(os.path.join(args.output_dir, "train.tsv"), header, train_rows)
    
    print(f"Wrote {len(dev_rows)} data rows to dev.tsv")
    print(f"Wrote {len(test_rows)} data rows to test.tsv")
    print(f"Wrote {len(train_rows)} data rows to train.tsv")
    print(f"Total: {len(dev_rows) + len(test_rows) + len(train_rows)} data rows")

if __name__ == "__main__":
    main()
EOL
    
    chmod +x regenerate_splits.py
    
    # Run the script to regenerate the splits
    python regenerate_splits.py \
        --custom-validated-tsv="$merge_into_dir/en/custom_validated.tsv" \
        --dev-ratio=0.1 \
        --test-ratio=0.1 \
        --output-dir="$merge_into_dir/en" \
        --seed=42
    
    # Verify the splits were created correctly
    if [ -f "$merge_into_dir/en/train.tsv" ] && [ -f "$merge_into_dir/en/dev.tsv" ] && [ -f "$merge_into_dir/en/test.tsv" ]; then
        train_count=$(tail -n +2 "$merge_into_dir/en/train.tsv" | wc -l)
        dev_count=$(tail -n +2 "$merge_into_dir/en/dev.tsv" | wc -l)
        test_count=$(tail -n +2 "$merge_into_dir/en/test.tsv" | wc -l)
        total_count=$((train_count + dev_count + test_count))
        
        echo "Verified dataset splits in $merge_into_dir/en:"
        echo "  - Train set: $train_count utterances"
        echo "  - Dev set: $dev_count utterances"
        echo "  - Test set: $test_count utterances"
        echo "  - Total: $total_count utterances"
        
        # Compare with the number of entries in custom_validated.tsv
        tsv_entry_count=$(tail -n +2 "$merge_into_dir/en/custom_validated.tsv" | wc -l)
        echo "Total entries in custom_validated.tsv: $tsv_entry_count"
        
        if [ "$total_count" -ne "$tsv_entry_count" ]; then
            echo "Warning: Mismatch between total split entries ($total_count) and custom_validated.tsv entries ($tsv_entry_count)"
            echo "Regenerating splits to ensure consistency..."
            
            # Regenerate the splits with the correct number of entries
            python regenerate_splits.py \
                --custom-validated-tsv="$merge_into_dir/en/custom_validated.tsv" \
                --dev-ratio=0.1 \
                --test-ratio=0.1 \
                --output-dir="$merge_into_dir/en" \
                --seed=42
            
            # Verify again
            train_count=$(tail -n +2 "$merge_into_dir/en/train.tsv" | wc -l)
            dev_count=$(tail -n +2 "$merge_into_dir/en/dev.tsv" | wc -l)
            test_count=$(tail -n +2 "$merge_into_dir/en/test.tsv" | wc -l)
            total_count=$((train_count + dev_count + test_count))
            
            echo "After regeneration:"
            echo "  - Train set: $train_count utterances"
            echo "  - Dev set: $dev_count utterances"
            echo "  - Test set: $test_count utterances"
            echo "  - Total: $total_count utterances"
        fi
    else
        echo "Error: Failed to create dataset splits in $merge_into_dir/en"
    fi
else
    echo "Warning: Cannot regenerate dataset splits - custom_validated.tsv not found in merge directory"
fi

# After merging the TSV files, ensure all MP3 files referenced in the TSV exist in the clips directory
if [ -n "$merge_into_dir" ] && [ -f "$merge_into_dir/en/custom_validated.tsv" ] && [ -d "en/clips" ]; then
    echo "Ensuring all MP3 files referenced in the merged TSV exist in the target clips directory..."
    
    # Create a Python script to extract MP3 filenames from TSV and copy missing files
    cat > copy_missing_mp3s.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import csv
import shutil
from pathlib import Path

def main():
    if len(sys.argv) != 4:
        print("Usage: python copy_missing_mp3s.py <tsv_file> <source_clips_dir> <target_clips_dir>")
        sys.exit(1)
    
    tsv_file = sys.argv[1]
    source_clips_dir = Path(sys.argv[2])
    target_clips_dir = Path(sys.argv[3])
    
    # Ensure target directory exists
    target_clips_dir.mkdir(exist_ok=True, parents=True)
    
    # Get list of MP3 files already in target directory
    existing_mp3s = set(f.name for f in target_clips_dir.glob("*.mp3"))
    print(f"Found {len(existing_mp3s)} existing MP3 files in target directory")
    
    # Extract MP3 filenames from TSV
    mp3_paths = []
    with open(tsv_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        next(reader)  # Skip header
        for row in reader:
            if len(row) > 1:
                path = row[1]
                if path:
                    mp3_paths.append(path)
    
    print(f"Found {len(mp3_paths)} MP3 paths in TSV file")
    
    # Determine which files need to be copied
    files_to_copy = []
    for path in mp3_paths:
        filename = os.path.basename(path)
        if filename not in existing_mp3s:
            source_file = source_clips_dir / filename
            if source_file.exists():
                files_to_copy.append((source_file, target_clips_dir / filename))
    
    print(f"Found {len(files_to_copy)} MP3 files to copy")
    
    # Copy missing files
    copied_count = 0
    for source, target in files_to_copy:
        try:
            shutil.copy2(source, target)
            copied_count += 1
            if copied_count % 100 == 0:
                print(f"Copied {copied_count} files so far...")
        except Exception as e:
            print(f"Error copying {source} to {target}: {e}")
    
    print(f"Successfully copied {copied_count} MP3 files to target directory")
    
    # Verify all files exist
    missing_files = []
    for path in mp3_paths:
        filename = os.path.basename(path)
        target_file = target_clips_dir / filename
        if not target_file.exists():
            missing_files.append(filename)
    
    if missing_files:
        print(f"Warning: {len(missing_files)} MP3 files referenced in TSV are still missing")
        print(f"First few missing files: {missing_files[:5]}")
    else:
        print("All MP3 files referenced in TSV exist in target directory")
    
    # Count final MP3 files
    final_count = len(list(target_clips_dir.glob("*.mp3")))
    print(f"Final count of MP3 files in target directory: {final_count}")

if __name__ == "__main__":
    main()
EOL
    
    chmod +x copy_missing_mp3s.py
    
    # Run the script to copy missing MP3 files
    echo "Copying missing MP3 files to target clips directory..."
    python copy_missing_mp3s.py "$merge_into_dir/en/custom_validated.tsv" "en/clips" "$merge_into_dir/en/clips"
    
    # Verify MP3 count matches TSV entry count
    mp3_count=$(find "$merge_into_dir/en/clips" -name "*.mp3" | wc -l)
    tsv_entry_count=$(tail -n +2 "$merge_into_dir/en/custom_validated.tsv" | wc -l)
    
    echo "MP3 files in target clips directory: $mp3_count"
    echo "Entries in target custom_validated.tsv: $tsv_entry_count"
    
    if [ "$mp3_count" -ne "$tsv_entry_count" ]; then
        echo "Warning: Mismatch between MP3 count ($mp3_count) and TSV entry count ($tsv_entry_count)"
        
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
    fi
fi