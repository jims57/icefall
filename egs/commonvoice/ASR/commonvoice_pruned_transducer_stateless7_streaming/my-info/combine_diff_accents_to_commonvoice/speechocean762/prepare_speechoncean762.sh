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
# This script converts the SpeechOcean762 dataset to CommonVoice format.
# It requires the SpeechOcean762 dataset already downloaded with the following structure:
# - WAVE/ directory containing speaker subdirectories with WAV files
# - train/text and test/text files with transcriptions
#
# Basic usage:
# bash prepare_speechocean762.sh
#
# The script:
# 1. Installs required pydub package
# 2. Runs the conversion script that:
#    - Converts WAV files to MP3 format
#    - Creates a CommonVoice-compatible TSV file
#    - Organizes files in the proper directory structure

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

# Clean up empty sentences in parallel
echo "Cleaning up empty sentences from dataset..."
if [ -f "en/custom_validated.tsv" ] && [ -d "en/clips" ]; then
    # Create a temporary file to store the cleaned TSV
    temp_tsv=$(mktemp)
    
    # Copy the header line
    head -n 1 en/custom_validated.tsv > "$temp_tsv"
    
    # Create a temporary processing script
    process_script=$(mktemp)
    chmod +x "$process_script"
    
    cat > "$process_script" << 'EOL'
#!/bin/bash
input_file="$1"
line_num="$2"
tsv_file="$3"

# Read the specific line from TSV
line=$(sed -n "${line_num}p" "$tsv_file")

# Parse the line
IFS=$'\t' read -r client_id path sentence up_votes down_votes age gender accent locale segment other <<< "$line"

# Check if sentence field is empty
if [ -z "$sentence" ] || [ "$sentence" = " " ]; then
    # Extract the MP3 filename from the path
    mp3_file=$(basename "$path")
    
    # Remove the corresponding MP3 file if it exists
    if [ -f "en/clips/$mp3_file" ]; then
        echo "Removing empty sentence MP3: $mp3_file" >&2
        rm "en/clips/$mp3_file"
    fi
    # Return empty string (this row will be skipped)
    echo ""
else
    # Keep row with non-empty sentence (output the entire line)
    echo "$line"
fi
EOL
    
    # Count total rows for statistics
    total_count=$(wc -l < en/custom_validated.tsv)
    data_rows=$((total_count - 1))  # Subtract header
    
    # Process each data row
    echo "Processing $data_rows rows..."
    empty_count=0
    
    for (( i=2; i<=$total_count; i++ )); do
        result=$("$process_script" "$i" "$i" "en/custom_validated.tsv")
        if [ -n "$result" ]; then
            echo "$result" >> "$temp_tsv"
        else
            empty_count=$((empty_count + 1))
        fi
    done
    
    # Replace original file with cleaned version
    mv "$temp_tsv" "en/custom_validated.tsv"
    
    # Clean up
    rm -f "$process_script"
    
    echo "Cleaned dataset: removed $empty_count empty sentences out of $data_rows total entries."
else
    echo "Warning: Cannot clean empty sentences - either TSV file or clips directory not found."
fi

# Print statistics about the dataset
echo "Dataset statistics:"
if [ -f "en/custom_validated.tsv" ]; then
    total_lines=$(wc -l < "en/custom_validated.tsv")
    data_lines=$((total_lines - 1))  # Subtract header line
    echo "Total utterances: $data_lines"
fi

echo "SpeechOcean762 preparation completed." 