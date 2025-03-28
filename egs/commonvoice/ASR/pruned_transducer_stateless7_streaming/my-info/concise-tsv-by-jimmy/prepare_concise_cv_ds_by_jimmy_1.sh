#!/bin/bash

# Copyright (c) 2023 Jimmy
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

# =====================================================================
# This script prepares a concise CommonVoice dataset for ASR training.
# It performs the following steps:
# 1. Fixes dataset mismatches between TSV and audio files
# 2. Checks dataset consistency
# 3. Creates train/dev/test splits
# 4. Optionally calculates total audio duration
# =====================================================================

set -e  # Exit on error
set -u  # Error on undefined variables
set -o pipefail  # Exit if any command in a pipe fails

echo "=========================================================="
echo "  CommonVoice Dataset Preparation Tool"
echo "  This tool prepares a concise CommonVoice dataset for ASR"
echo "=========================================================="

# Display usage information
function show_usage {
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --custom-validated-tsv PATH   Path to custom validated TSV file (default: en/custom_validated.tsv)"
  echo "  --clips-dir PATH              Path to directory containing audio clips (default: ./en/clips)"
  echo "  --dev-ratio VALUE             Ratio of data for development set (default: 0.1)"
  echo "  --test-ratio VALUE            Ratio of data for test set (default: 0.1)"
  echo "  --seed VALUE                  Random seed for reproducibility (default: 42)"
  echo "  --count-total-hours true|false  Whether to calculate total audio duration (default: true)"
  echo ""
  echo "Example:"
  echo "  $0 --custom-validated-tsv path/to/validated.tsv --clips-dir path/to/clips --dev-ratio 0.15"
  echo ""
}

# Show usage if --help is provided
if [[ "$*" == *--help* ]] || [[ "$*" == *-h* ]]; then
  show_usage
  exit 0
fi

# Check if jq is installed, if not, install it using conda
if ! command -v jq &> /dev/null; then
  echo "jq not found. Installing jq using conda..."
  
  # Check if we're in a conda environment
  if [[ -n $CONDA_PREFIX ]]; then
    conda install -y -c conda-forge jq
    echo "jq installed successfully via conda in the icefall environment."
  else
    echo "Warning: Not in a conda environment. Installing jq locally..."
    wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x ./jq
    export PATH=$PWD:$PATH
    echo "jq installed successfully in the current directory."
  fi
fi

# Default parameters
CUSTOM_VALIDATED_TSV="./en/custom_validated.tsv"
CLIPS_DIR="./en/clips"
DEV_RATIO=0.1
TEST_RATIO=0.1
SEED=42
COUNT_TOTAL_HOURS=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --custom-validated-tsv)
      CUSTOM_VALIDATED_TSV="$2"
      shift 2
      ;;
    --clips-dir)
      CLIPS_DIR="$2"
      shift 2
      ;;
    --dev-ratio)
      DEV_RATIO="$2"
      shift 2
      ;;
    --test-ratio)
      TEST_RATIO="$2"
      shift 2
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --count-total-hours)
      COUNT_TOTAL_HOURS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
  esac
done

# Display configuration
echo ""
echo "Configuration:"
echo "  Custom validated TSV: ${CUSTOM_VALIDATED_TSV}"
echo "  Clips directory: ${CLIPS_DIR}"
echo "  Dev set ratio: ${DEV_RATIO}"
echo "  Test set ratio: ${TEST_RATIO}"
echo "  Random seed: ${SEED}"
echo "  Count total hours: ${COUNT_TOTAL_HOURS}"
echo ""

# Step 1: Fix dataset mismatch
echo "Step 1: Fixing dataset mismatch..."
if [ -f "fix_dataset_mismatch.py" ]; then
  python3 fix_dataset_mismatch.py --custom-validated-tsv "${CUSTOM_VALIDATED_TSV}" --clips-dir "${CLIPS_DIR}"
  echo "Dataset mismatch fix completed."
else
  echo "Error: fix_dataset_mismatch.py not found."
  echo "This script should be in the same directory and is required to ensure"
  echo "all audio files referenced in the TSV exist on disk."
  exit 1
fi

# Step 2: Check consistency
echo "Step 2: Checking dataset consistency..."
if [ -f "check_consistency.sh" ]; then
  bash check_consistency.sh --custom-validated-tsv "${CUSTOM_VALIDATED_TSV}" --clips-dir "${CLIPS_DIR}"
  
  # Check if the consistency check was successful
  if [ $? -ne 0 ]; then
    echo "Error: Dataset consistency check failed. Please fix the inconsistencies before proceeding."
    echo "Common issues include:"
    echo "  - Missing audio files"
    echo "  - Corrupted audio files"
    echo "  - Mismatched file paths in TSV"
    exit 1
  fi
  echo "Dataset consistency check passed."
else
  echo "Error: check_consistency.sh not found."
  echo "This script should be in the same directory and is required to verify"
  echo "the integrity of the dataset before proceeding."
  exit 1
fi

# Step 3: Create TSV files
echo "Step 3: Creating train, dev, and test TSV files..."

# Locate the Python script
PYTHON_SCRIPT="create_tsv_files_by_custom_validated_tsv.py"
SCRIPT_PATH=""

# Check if Python script exists in current directory
if [ -f "${PYTHON_SCRIPT}" ]; then
  SCRIPT_PATH="./${PYTHON_SCRIPT}"
  echo "Found Python script in current directory."
# Check if Python script exists in python subdirectory
elif [ -f "python/${PYTHON_SCRIPT}" ]; then
  SCRIPT_PATH="python/${PYTHON_SCRIPT}"
  echo "Found Python script in python directory."
else
  echo "Error: Cannot find ${PYTHON_SCRIPT} in current directory or python subdirectory."
  echo "This script is required to split the dataset into train, dev, and test sets."
  exit 1
fi

# Make sure the script is executable
chmod +x "${SCRIPT_PATH}"

echo "Running Python script to create TSV files..."
python3 "${SCRIPT_PATH}" \
  --custom-validated-tsv "${CUSTOM_VALIDATED_TSV}" \
  --clips-dir "${CLIPS_DIR}" \
  --dev-ratio "${DEV_RATIO}" \
  --test-ratio "${TEST_RATIO}" \
  --seed "${SEED}"

# Check if the files were created successfully
if [ -f "train.tsv" ] && [ -f "dev.tsv" ] && [ -f "test.tsv" ]; then
  echo "Success! Created train.tsv, dev.tsv, and test.tsv files."
  
  # Display row counts for verification
  echo "File statistics:"
  wc -l train.tsv dev.tsv test.tsv
  
  # Move TSV files to the en folder
  echo "Moving TSV files to en folder..."
  mkdir -p "en"
  mv train.tsv dev.tsv test.tsv "en/"
  echo "TSV files moved to en folder."
else
  echo "Error: Failed to create all required TSV files."
  echo "Check the output above for any error messages from the Python script."
  exit 1
fi

echo "Dataset preparation complete!"

# Count total hours of audio if requested
if [ "${COUNT_TOTAL_HOURS}" = "true" ]; then
  echo "Step 4: Calculating total audio duration..."
  DURATION_SCRIPT="calculate_audio_duration.py"
  
  # Check if ffmpeg is installed
  if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "FFmpeg/ffprobe is required but not installed. Installing now..."
    # Try to install ffmpeg based on the system
    if [[ -n $CONDA_PREFIX ]]; then
      conda install -y -c conda-forge ffmpeg
    elif command -v apt-get &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y ffmpeg
    elif command -v yum &> /dev/null; then
      sudo yum install -y ffmpeg
    elif command -v brew &> /dev/null; then
      brew install ffmpeg
    else
      echo "Error: Could not install FFmpeg automatically. Please install FFmpeg manually and try again."
      echo "Visit https://ffmpeg.org/download.html for installation instructions."
      exit 1
    fi
  fi
  
  # Create the duration calculation script
  cat > "${DURATION_SCRIPT}" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import pandas as pd
from pydub import AudioSegment
import concurrent.futures
import argparse

def get_audio_duration(file_path):
    try:
        audio = AudioSegment.from_mp3(file_path)
        return len(audio) / 1000.0  # Convert milliseconds to seconds
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
        return 0

def main():
    parser = argparse.ArgumentParser(description="Calculate total audio duration from TSV files")
    parser.add_argument("--tsv-files", nargs="+", required=True, help="List of TSV files")
    parser.add_argument("--clips-dir", required=True, help="Directory containing audio clips")
    args = parser.parse_args()
    
    total_duration = 0
    file_count = 0
    
    for tsv_file in args.tsv_files:
        if not os.path.exists(tsv_file):
            print(f"Warning: {tsv_file} does not exist, skipping.")
            continue
            
        df = pd.read_csv(tsv_file, sep='\t')
        if 'path' not in df.columns:
            print(f"Warning: {tsv_file} does not have a 'path' column, skipping.")
            continue
            
        file_paths = [os.path.join(args.clips_dir, path) for path in df['path']]
        file_count += len(file_paths)
        
        # Process files in parallel for speed
        with concurrent.futures.ProcessPoolExecutor() as executor:
            durations = list(executor.map(get_audio_duration, file_paths))
            total_duration += sum(durations)
    
    hours = total_duration / 3600
    print(f"Processed {file_count} audio files")
    print(f"Total audio duration: {total_duration:.2f} seconds ({hours:.2f} hours)")

if __name__ == "__main__":
    main()
EOF

  chmod +x "${DURATION_SCRIPT}"

  # Install required packages if not already installed
  echo "Installing required Python packages (pydub, pandas)..."
  pip install pydub pandas

  # Run the duration calculation script
  echo "Calculating total audio duration (this may take a while)..."
  python3 "${DURATION_SCRIPT}" --tsv-files en/train.tsv en/dev.tsv en/test.tsv --clips-dir "${CLIPS_DIR}"
else
  echo "Skipping audio duration calculation (--count-total-hours is set to false)"
fi

echo ""
echo "=========================================================="
echo "All processing complete!"
echo ""
echo "IMPORTANT NOTES:"
echo "1. Make sure jq is available when running prepare.sh"
echo "   If you encounter 'jq: command not found' when running prepare.sh, run:"
echo "   conda install -y -c conda-forge jq"
echo ""
echo "2. The prepared dataset is now ready in the 'en' directory:"
echo "   - en/train.tsv: Training data"
echo "   - en/dev.tsv: Development/validation data"
echo "   - en/test.tsv: Test data"
echo ""
echo "3. Next steps:"
echo "   - Run the ASR training script with this prepared dataset"
echo "   - Monitor training progress with TensorBoard"
echo "   - Evaluate model performance on the test set"
echo "=========================================================="
