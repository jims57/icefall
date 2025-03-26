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
# This script converts the SpeechOcean762 dataset to CommonVoice format,
# cleans short sentences, and creates train/dev/test splits.
#
# Basic usage:
# bash prepare_speechocean762.sh --dev-ratio 0.1 --test-ratio 0.1
#
# Parameters:
#   --dev-ratio: Ratio of data to use for dev set (default: 0.1)
#   --test-ratio: Ratio of data to use for test set (default: 0.1)
#   --merge-into-dir: Directory to merge data into (default: empty)
#
# Advanced example:
# bash prepare_speechocean762.sh --dev-ratio 0.15 --test-ratio 0.15

# Default values for parameters
dev_ratio=0.1
test_ratio=0.1
merge_into_dir=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
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
            # Unknown option
            echo "Unknown option: $1"
            echo "Usage: $0 [--dev-ratio RATIO] [--test-ratio RATIO] [--merge-into-dir DIR]"
            exit 1
            ;;
    esac
done

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

# Determine the number of CPU cores for parallel processing
num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "Detected $num_cores CPU cores. Will use parallel processing."

# Avoid the GNU Parallel citation notice
export PARALLEL_SHELL=/bin/bash
mkdir -p ~/.parallel
touch ~/.parallel/will-cite

# For very large systems (like yours with 128 cores), limit to a reasonable number
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

# Check if the required directories exist
if [ ! -d "WAVE" ]; then
    echo "WAVE directory not found. Attempting to download SpeechOcean762 dataset..."
    
    # Check if Python is available
    if ! command -v python &> /dev/null; then
        echo "Error: Python is not installed or not in PATH"
        exit 1
    fi
    
    # Check if the convert script exists
    if [ ! -f "convert_speechocean762_to_cv_ds_format.py" ]; then
        echo "Error: convert_speechocean762_to_cv_ds_format.py script not found"
        exit 1
    fi
    
    # Download the dataset using the Python script
    python convert_speechocean762_to_cv_ds_format.py --download
    
    # Check if download was successful
    if [ ! -d "WAVE" ]; then
        echo "Error: Failed to download SpeechOcean762 dataset or WAVE directory not created"
        exit 1
    else
        echo "Successfully downloaded SpeechOcean762 dataset"
    fi
fi

if [ ! -f "train/text" ] && [ ! -f "test/text" ]; then
    echo "Error: Neither train/text nor test/text found. Please make sure SpeechOcean762 dataset is properly downloaded."
    exit 1
fi

# Check if clips folder already exists in the en directory and contains MP3 files
if [ -d "en/clips" ] && [ "$(find en/clips -name "*.mp3" | wc -l)" -gt 0 ]; then
    echo "en/clips folder with MP3 files already exists. Skipping conversion from WAV to MP3..."
    
    # Check if custom_validated.tsv exists in en directory
    if [ ! -f "en/custom_validated.tsv" ]; then
        echo "Warning: en/clips folder exists but en/custom_validated.tsv not found. Running conversion script to generate TSV file only..."
        python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion
        
        # Move the generated TSV to en directory if it was created in the current directory
        if [ -f "custom_validated.tsv" ]; then
            mv custom_validated.tsv en/
        fi
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
            python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion
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
            echo "Will output MP3 files directly to $output_clips_dir"
        else
            # Create local clips directory if it doesn't exist
            mkdir -p clips
            output_clips_dir="clips"
        fi
        
        # Create a file list of all WAV files
        find WAVE -name "*.wav" -o -name "*.WAV" > wav_files.txt
        
        # Define conversion functions based on GPU availability
        if $has_gpu; then
            # NVIDIA GPU conversion function
            convert_to_mp3() {
                local wav_file="$1"
                local output_dir="$2"
                local filename=$(basename "$wav_file" .wav)
                local mp3_file="${output_dir}/${filename}.mp3"
                
                # Try GPU acceleration first
                ffmpeg -y -hwaccel cuda -i "$wav_file" -codec:a libmp3lame -qscale:a 2 "$mp3_file" -loglevel error
                
                # If GPU conversion fails, fall back to CPU
                if [ $? -ne 0 ]; then
                    echo "GPU acceleration failed for $wav_file, falling back to CPU..." >&2
                    ffmpeg -y -i "$wav_file" -codec:a libmp3lame -qscale:a 2 -threads 1 "$mp3_file" -loglevel error
                fi
            }
        else
            # CPU-only conversion function
            convert_to_mp3() {
                local wav_file="$1"
                local output_dir="$2"
                # Handle both uppercase and lowercase extensions
                if [[ "$wav_file" == *.WAV ]]; then
                    local filename=$(basename "$wav_file" .WAV)
                else
                    local filename=$(basename "$wav_file" .wav)
                fi
                local mp3_file="${output_dir}/${filename}.mp3"
                
                # Convert using CPU with thread optimization
                ffmpeg -y -i "$wav_file" -codec:a libmp3lame -qscale:a 2 -threads 1 "$mp3_file" -loglevel error
                
                # Print success message
                if [ $? -eq 0 ]; then
                    echo "Successfully converted: $wav_file -> $mp3_file"
                else
                    echo "Error converting: $wav_file"
                fi
            }
        fi
        
        # Export the function so parallel can use it
        export -f convert_to_mp3
        export output_clips_dir
        
        # Process files in parallel with progress indicator
        echo "Starting parallel conversion with $effective_cores processes..."
        cat wav_files.txt | parallel --progress --bar -j $effective_cores "convert_to_mp3 {} $output_clips_dir"
        
        # Clean up
        rm wav_files.txt
        
        # Generate the TSV file
        echo "Generating TSV file..."
        if [ -n "$merge_into_dir" ]; then
            # Generate TSV with audio path update to point to merge directory
            echo "Rebuilding TSV file from MP3 files in $merge_into_dir/en/clips..."
            python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion --output_tsv="$merge_into_dir/en/custom_validated.tsv" --output_dir="$merge_into_dir/en/clips" --rebuild_tsv
        else
            python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion --sync_files
        fi
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
            if [ -f "temp_generated.tsv" ]; then
                source_tsv="temp_generated.tsv"
            elif [ -f "custom_validated.tsv" ]; then
                source_tsv="custom_validated.tsv"
            elif [ -f "en/custom_validated.tsv" ]; then
                source_tsv="en/custom_validated.tsv"
            else
                # If no TSV file is found, create a custom_validated.tsv with the correct format
                echo "No source TSV file found. Creating custom_validated.tsv with correct format..."
                echo -e "client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment" > custom_validated.tsv
                
                # Generate TSV content from MP3 files
                python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion --output_tsv="custom_validated.tsv" --rebuild_tsv
                
                source_tsv="custom_validated.tsv"
            fi
            
            # Keep MP3 files in ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips
            # and also copy them to the merge directory
            mkdir -p ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips
            
            # Create a Python script to ensure all MP3 files in the TSV are copied
            cat > copy_mp3_files.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import os
import shutil
import sys

def main():
    parser = argparse.ArgumentParser(description="Copy MP3 files based on TSV entries")
    parser.add_argument("--tsv", type=str, required=True, help="TSV file with audio paths")
    parser.add_argument("--source-dir", type=str, required=True, help="Source directory containing MP3 files")
    parser.add_argument("--target-dir", type=str, required=True, help="Target directory to copy MP3 files to")
    args = parser.parse_args()
    
    # Expand home directory if path contains ~
    tsv_path = os.path.expanduser(args.tsv)
    source_dir = os.path.expanduser(args.source_dir)
    target_dir = os.path.expanduser(args.target_dir)
    
    # Ensure target directory exists
    os.makedirs(target_dir, exist_ok=True)
    
    # Read TSV file to get all MP3 filenames
    mp3_files = []
    with open(tsv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        next(reader)  # Skip header
        for row in reader:
            if len(row) > 1 and row[1]:  # Check if path column exists and is not empty
                mp3_file = os.path.basename(row[1])
                if mp3_file.endswith('.mp3'):
                    mp3_files.append(mp3_file)
    
    print(f"Found {len(mp3_files)} MP3 files in TSV")
    
    # Find all MP3 files in source directory
    source_mp3_files = []
    for root, dirs, files in os.walk(source_dir):
        for file in files:
            if file.endswith('.mp3'):
                source_mp3_files.append((os.path.join(root, file), file))
    
    print(f"Found {len(source_mp3_files)} MP3 files in source directory")
    
    # Copy MP3 files to target directory
    copied_count = 0
    missing_count = 0
    for mp3_file in mp3_files:
        found = False
        for source_path, source_file in source_mp3_files:
            if source_file == mp3_file:
                target_path = os.path.join(target_dir, mp3_file)
                if not os.path.exists(target_path):
                    shutil.copy2(source_path, target_path)
                    copied_count += 1
                found = True
                break
        
        if not found:
            print(f"Warning: Could not find {mp3_file} in source directory", file=sys.stderr)
            missing_count += 1
    
    print(f"Copied {copied_count} MP3 files to {target_dir}")
    if missing_count > 0:
        print(f"Warning: {missing_count} MP3 files from TSV were not found in source directory", file=sys.stderr)
    
    # Verify the number of MP3 files in target directory
    target_mp3_count = len([f for f in os.listdir(target_dir) if f.endswith('.mp3')])
    print(f"Target directory now contains {target_mp3_count} MP3 files")
    
    if target_mp3_count != len(mp3_files):
        print(f"Warning: Mismatch between TSV entries ({len(mp3_files)}) and MP3 files in target ({target_mp3_count})", file=sys.stderr)

if __name__ == "__main__":
    main()
EOL
            
            # Make script executable
            chmod +x copy_mp3_files.py
            
            # Find all possible source directories for MP3 files
            possible_sources=("clips" "en/clips" "$merge_into_dir/en/clips")
            
            # Copy MP3 files to both target directories
            echo "Copying MP3 files to ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips..."
            python copy_mp3_files.py --tsv="$source_tsv" --source-dir="." --target-dir=~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips
            
            # Also copy to merge directory
            echo "Copying MP3 files to $merge_into_dir/en/clips..."
            mkdir -p "$merge_into_dir/en/clips"
            python copy_mp3_files.py --tsv="$source_tsv" --source-dir="." --target-dir="$merge_into_dir/en/clips"
            
            # Make a copy of the source TSV to keep locally
            cp "$source_tsv" "custom_validated.tsv.backup"
            
            # Merge TSV files
            python merge_tsv_files.py --source="$source_tsv" --target="$merge_into_dir/en/custom_validated.tsv" --output="$merge_into_dir/en/custom_validated.tsv.new"
            mv "$merge_into_dir/en/custom_validated.tsv.new" "$merge_into_dir/en/custom_validated.tsv"
            
            # Also append the new entries to the source TSV
            echo "Updating local custom_validated.tsv with the same new entries..."
            python merge_tsv_files.py --source="$merge_into_dir/en/custom_validated.tsv" --target="$source_tsv" --output="custom_validated.tsv.new"
            mv "custom_validated.tsv.new" "custom_validated.tsv"
            
            # Copy the final TSV to the speechocean762-1.2.0 directory
            cp "custom_validated.tsv" ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/
            
            echo "Data successfully merged into $merge_into_dir and local custom_validated.tsv updated"
            
            # Verify the MP3 files match the TSV entries in the speechocean762-1.2.0 directory
            echo "Verifying MP3 files in ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips..."
            tsv_count=$(tail -n +2 ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/custom_validated.tsv 2>/dev/null | wc -l || echo 0)
            mp3_count=$(find ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips -name "*.mp3" 2>/dev/null | wc -l || echo 0)
            echo "TSV entries: $tsv_count, MP3 files: $mp3_count"
            
            if [ "$tsv_count" != "$mp3_count" ] && [ "$tsv_count" -gt 0 ]; then
                echo "Warning: Mismatch between TSV entries and MP3 files in speechocean762-1.2.0 directory"
                echo "Running additional sync to ensure all files are present..."
                
                # Create a fixed path version of the Python script
                cat > fix_path_copy_mp3_files.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import os
import shutil
import sys

def main():
    parser = argparse.ArgumentParser(description="Copy MP3 files based on TSV entries")
    parser.add_argument("--tsv", type=str, required=True, help="TSV file with audio paths")
    parser.add_argument("--source-dir", type=str, required=True, help="Source directory containing MP3 files")
    parser.add_argument("--target-dir", type=str, required=True, help="Target directory to copy MP3 files to")
    args = parser.parse_args()
    
    # Expand home directory if path contains ~
    tsv_path = os.path.expanduser(args.tsv)
    source_dir = os.path.expanduser(args.source_dir)
    target_dir = os.path.expanduser(args.target_dir)
    
    # Ensure target directory exists
    os.makedirs(target_dir, exist_ok=True)
    
    # Read TSV file to get all MP3 filenames
    mp3_files = []
    with open(tsv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        next(reader)  # Skip header
        for row in reader:
            if len(row) > 1 and row[1]:  # Check if path column exists and is not empty
                mp3_file = os.path.basename(row[1])
                if mp3_file.endswith('.mp3'):
                    mp3_files.append(mp3_file)
    
    print(f"Found {len(mp3_files)} MP3 files in TSV")
    
    # Find all MP3 files in source directory
    source_mp3_files = []
    for root, dirs, files in os.walk(source_dir):
        for file in files:
            if file.endswith('.mp3'):
                source_mp3_files.append((os.path.join(root, file), file))
    
    print(f"Found {len(source_mp3_files)} MP3 files in source directory")
    
    # Copy MP3 files to target directory
    copied_count = 0
    missing_count = 0
    for mp3_file in mp3_files:
        found = False
        for source_path, source_file in source_mp3_files:
            if source_file == mp3_file:
                target_path = os.path.join(target_dir, mp3_file)
                if not os.path.exists(target_path):
                    shutil.copy2(source_path, target_path)
                    copied_count += 1
                found = True
                break
        
        if not found:
            print(f"Warning: Could not find {mp3_file} in source directory", file=sys.stderr)
            missing_count += 1
    
    print(f"Copied {copied_count} MP3 files to {target_dir}")
    if missing_count > 0:
        print(f"Warning: {missing_count} MP3 files from TSV were not found in source directory", file=sys.stderr)
    
    # Verify the number of MP3 files in target directory
    target_mp3_count = len([f for f in os.listdir(target_dir) if f.endswith('.mp3')])
    print(f"Target directory now contains {target_mp3_count} MP3 files")
    
    if target_mp3_count != len(mp3_files):
        print(f"Warning: Mismatch between TSV entries ({len(mp3_files)}) and MP3 files in target ({target_mp3_count})", file=sys.stderr)

if __name__ == "__main__":
    main()
EOL
                
                # Make script executable
                chmod +x fix_path_copy_mp3_files.py
                
                # Use absolute paths instead of ~ paths
                speechocean_dir="${HOME}/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0"
                
                # Try one more time with all possible source directories
                for src_dir in "${possible_sources[@]}"; do
                    if [ -d "$src_dir" ]; then
                        echo "Trying to copy from $src_dir..."
                        python fix_path_copy_mp3_files.py --tsv="${speechocean_dir}/custom_validated.tsv" --source-dir="$src_dir" --target-dir="${speechocean_dir}/clips"
                    fi
                done
            fi
            
            # Skip creating local en directory when merging
            if [ -n "$merge_into_dir" ]; then
                # Set a flag to skip remaining local processing
                skip_local_processing=true
            fi
        else
            # Target TSV doesn't exist, create it from scratch
            echo "Target custom_validated.tsv doesn't exist, creating it..."
            
            if [ -f "temp_generated.tsv" ]; then
                # Copy the generated TSV to the target location
                cp temp_generated.tsv "$merge_into_dir/en/custom_validated.tsv"
                rm temp_generated.tsv
            elif [ -f "custom_validated.tsv" ]; then
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
                echo "Warning: en/clips already exists. Skipping move operation."
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

# Only clean up and create train/dev/test splits if we're not in merge mode
if [ -z "$merge_into_dir" ]; then
    # Clean up empty sentences and short sentences from dataset...
    echo "Cleaning up empty sentences and short sentences from dataset..."
    if [ -f "en/custom_validated.tsv" ] && [ -d "en/clips" ]; then
        # Create a temporary file to store the cleaned TSV
        temp_tsv=$(mktemp)
        
        # Copy the header line
        head -n 1 en/custom_validated.tsv > "$temp_tsv"
        
        # Directly process each line for better debugging and control
        total_lines=$(wc -l < en/custom_validated.tsv)
        empty_count=0
        short_count=0
        kept_count=0
        
        # First, display the first few lines of the TSV to understand its format
        echo "Examining TSV format:"
        head -n 5 en/custom_validated.tsv
        
        # Process line by line (starting from line 2 to skip header)
        for ((i=2; i<=$total_lines; i++)); do
            # Read the line
            line=$(sed -n "${i}p" en/custom_validated.tsv)
            
            # Split line into columns - using proper TSV parsing
            client_id=$(echo "$line" | cut -f1)
            path=$(echo "$line" | cut -f2)
            sentence=$(echo "$line" | cut -f4)  # Column 4 appears to be the sentence based on screenshot
            
            # Extract MP3 filename
            mp3_file=$(basename "$path")
            mp3_path="en/clips/$mp3_file"
            
            # Count words more accurately by replacing multiple spaces with single spaces first
            cleaned_sentence=$(echo "$sentence" | tr -s ' ' | xargs)
            word_count=$(echo "$cleaned_sentence" | wc -w)
            
            echo "Line $i: sentence=\"$sentence\", cleaned=\"$cleaned_sentence\", word count=$word_count"
            
            # Check if sentence is empty or has fewer than 3 words
            if [ -z "$cleaned_sentence" ] || [ "$cleaned_sentence" = " " ]; then
                if [ -f "$mp3_path" ]; then
                    echo "Removing empty sentence MP3: $mp3_file"
                    rm "$mp3_path"
                fi
                empty_count=$((empty_count + 1))
            elif [ $word_count -lt 3 ]; then
                if [ -f "$mp3_path" ]; then
                    echo "Removing short sentence MP3 (fewer than 3 words): $mp3_file"
                    rm "$mp3_path"
                fi
                short_count=$((short_count + 1))
            else
                # Keep this row - it has 3+ words
                echo "$line" >> "$temp_tsv"
                kept_count=$((kept_count + 1))
            fi
        done
        
        # Replace original file with cleaned version
        mv "$temp_tsv" "en/custom_validated.tsv"
        
        echo "Cleaned dataset: removed $empty_count empty sentences and $short_count short sentences (fewer than 3 words)"
        echo "Kept $kept_count sentences with 3+ words"
        
        # Double-check the MP3 files match the kept entries
        tsv_mp3_count=$(tail -n +2 en/custom_validated.tsv | wc -l)
        actual_mp3_count=$(find en/clips -name "*.mp3" | wc -l)
        echo "TSV entries (excluding header): $tsv_mp3_count"
        echo "MP3 files in en/clips: $actual_mp3_count"
        
        if [ "$tsv_mp3_count" != "$actual_mp3_count" ]; then
            echo "Warning: Mismatch between TSV entries and MP3 files"
            echo "Running sync operation to ensure consistency..."
            python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion --output_dir="en/clips" --output_tsv="en/custom_validated.tsv.new" --sync_files
            mv "en/custom_validated.tsv.new" "en/custom_validated.tsv"
            
            # Verify again
            tsv_mp3_count=$(tail -n +2 en/custom_validated.tsv | wc -l)
            actual_mp3_count=$(find en/clips -name "*.mp3" | wc -l)
            echo "After sync - TSV entries: $tsv_mp3_count, MP3 files: $actual_mp3_count"
        fi
    else
        echo "Warning: Cannot clean sentences - either TSV file or clips directory not found."
    fi

    # Create train, dev, and test splits
    echo "Creating train, dev, and test splits with dev ratio $dev_ratio and test ratio $test_ratio..."
    if [ -f "en/custom_validated.tsv" ]; then
        # Create a Python script for splitting
        cat > split_tsv_into_sets.py << 'EOL'
#!/usr/bin/env python3
import argparse
import csv
import random

def parse_args():
    parser = argparse.ArgumentParser(description="Split TSV file into train, dev, and test sets")
    parser.add_argument("--input-tsv", type=str, required=True, help="Input TSV file")
    parser.add_argument("--dev-ratio", type=float, default=0.1, help="Ratio for dev set")
    parser.add_argument("--test-ratio", type=float, default=0.1, help="Ratio for test set")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    return parser.parse_args()

def main():
    args = parse_args()
    
    # Validate ratios
    if args.dev_ratio + args.test_ratio >= 1.0:
        raise ValueError("Sum of dev_ratio and test_ratio must be less than 1.0")
    
    # Read the TSV file
    with open(args.input_tsv, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)  # Read header
        rows = list(reader)    # Read all data rows
    
    # Shuffle the rows
    random.seed(args.seed)
    random.shuffle(rows)
    
    # Calculate split sizes
    total_rows = len(rows)
    dev_size = max(1, int(total_rows * args.dev_ratio))
    test_size = max(1, int(total_rows * args.test_ratio))
    
    # Ensure we have enough data for all splits
    if total_rows < 3:
        print("Warning: Not enough data for proper splits")
        if total_rows == 2:
            dev_size, test_size = 1, 0
        elif total_rows == 1:
            dev_size, test_size = 0, 0
        else:  # total_rows == 0
            dev_size, test_size = 0, 0
    elif dev_size + test_size >= total_rows:
        # Ensure at least one row for train
        dev_size = 1
        test_size = 1 if total_rows > 2 else 0
    
    train_size = total_rows - dev_size - test_size
    
    print(f"Total rows: {total_rows}")
    print(f"Train set: {train_size} rows")
    print(f"Dev set: {dev_size} rows")
    print(f"Test set: {test_size} rows")
    
    # Split the data
    dev_rows = rows[:dev_size]
    test_rows = rows[dev_size:dev_size + test_size]
    train_rows = rows[dev_size + test_size:]
    
    # Write the output files
    with open('en/train.tsv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(train_rows)
    
    with open('en/dev.tsv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(dev_rows)
    
    with open('en/test.tsv', 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header)
        writer.writerows(test_rows)

if __name__ == "__main__":
    main()
EOL

        # Make the script executable
        chmod +x split_tsv_into_sets.py
        
        # Run the script
        python split_tsv_into_sets.py --input-tsv="en/custom_validated.tsv" --dev-ratio="$dev_ratio" --test-ratio="$test_ratio"
        
        # Verify the results
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
        echo "Warning: Cannot create dataset splits - custom_validated.tsv not found."
    fi

    # Print statistics about the final dataset
    echo "Dataset statistics:"
    if [ -f "en/custom_validated.tsv" ]; then
        total_lines=$(wc -l < "en/custom_validated.tsv")
        data_lines=$((total_lines - 1))  # Subtract header line
        echo "Total utterances: $data_lines"
    fi

    echo "SpeechOcean762 preparation completed." 
    echo
    echo "Example usage of the prepared dataset:"
    echo "  - Use all data: bash prepare_speechocean762.sh"
    echo "  - Custom split ratios: bash prepare_speechocean762.sh --dev-ratio 0.15 --test-ratio 0.15"
    echo "  - Merge into existing dataset: bash prepare_speechocean762.sh --merge-into-dir=/path/to/target/dataset"
else
    echo "Skipping dataset cleaning and splits since we're in merge mode."
    echo "To clean and split the merged dataset, run this script directly on $merge_into_dir."
fi 