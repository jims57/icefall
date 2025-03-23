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
#
# Advanced example:
# bash prepare_speechocean762.sh --dev-ratio 0.15 --test-ratio 0.15

# Default values for parameters
dev_ratio=0.1
test_ratio=0.1

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
        *)
            # Unknown option
            echo "Unknown option: $1"
            echo "Usage: $0 [--dev-ratio RATIO] [--test-ratio RATIO]"
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
    echo "Error: WAVE directory not found. Please make sure SpeechOcean762 dataset is properly downloaded."
    exit 1
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
        
        # Create clips directory if it doesn't exist
        mkdir -p clips
        
        # Create a file list of all WAV files
        find WAVE -name "*.wav" > wav_files.txt
        
        # Define conversion functions based on GPU availability
        if $has_gpu; then
            # NVIDIA GPU conversion function
            convert_to_mp3() {
                local wav_file="$1"
                local filename=$(basename "$wav_file" .wav)
                local mp3_file="clips/${filename}.mp3"
                
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
                local filename=$(basename "$wav_file" .wav)
                local mp3_file="clips/${filename}.mp3"
                
                # Convert using CPU with thread optimization
                ffmpeg -y -i "$wav_file" -codec:a libmp3lame -qscale:a 2 -threads 1 "$mp3_file" -loglevel error
            }
        fi
        
        # Export the function so parallel can use it
        export -f convert_to_mp3
        
        # Process files in parallel with progress indicator
        echo "Starting parallel conversion with $effective_cores processes..."
        cat wav_files.txt | parallel --progress --bar -j $effective_cores convert_to_mp3
        
        # Clean up
        rm wav_files.txt
        
        # Generate the TSV file
        echo "Generating TSV file..."
        python convert_speechocean762_to_cv_ds_format.py --skip_audio_conversion
    fi
    
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