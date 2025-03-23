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

# Install required packages
echo "Installing required packages..."
conda install -y pydub

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
        # Run the conversion script
        echo "Converting SpeechOcean762 dataset to CommonVoice format..."
        python convert_speechocean762_to_cv_ds_format.py
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

# After moving files to en directory, clean up empty sentences
echo "Cleaning up empty sentences from dataset..."
if [ -f "en/custom_validated.tsv" ] && [ -d "en/clips" ]; then
    # Create a temporary file to store the cleaned TSV
    temp_tsv=$(mktemp)
    
    # Copy the header line
    head -n 1 en/custom_validated.tsv > "$temp_tsv"
    
    # Process the TSV file to find and remove empty sentences
    empty_count=0
    total_count=0
    
    # Skip the header line and process each data row
    tail -n +2 en/custom_validated.tsv | while IFS=$'\t' read -r client_id path sentence up_votes down_votes age gender accent locale segment other
    do
        total_count=$((total_count + 1))
        
        # Check if sentence field is empty
        if [ -z "$sentence" ] || [ "$sentence" = " " ]; then
            empty_count=$((empty_count + 1))
            
            # Extract the MP3 filename from the path
            mp3_file=$(basename "$path")
            
            # Remove the corresponding MP3 file if it exists
            if [ -f "en/clips/$mp3_file" ]; then
                echo "Removing empty sentence MP3: $mp3_file"
                rm "en/clips/$mp3_file"
            fi
        else
            # Keep rows with non-empty sentences - write the entire row to the temp file
            echo -e "$client_id\t$path\t$sentence\t$up_votes\t$down_votes\t$age\t$gender\t$accent\t$locale\t$segment\t$other" >> "$temp_tsv"
        fi
    done
    
    # Replace the original TSV with the cleaned one
    mv "$temp_tsv" "en/custom_validated.tsv"
    
    echo "Cleaned dataset: removed $empty_count empty sentences out of $total_count total entries."
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