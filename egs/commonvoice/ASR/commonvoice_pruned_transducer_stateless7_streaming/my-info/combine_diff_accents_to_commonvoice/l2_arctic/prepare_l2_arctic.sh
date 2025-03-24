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
# This script:
# 1. Checks if the output directory already exists (skips download if it does)
# 2. Checks if the download script exists
# 3. Runs the download script to fetch the L2-Arctic dataset
# 4. The download script will:
#    - Install required packages (gdown, tqdm)
#    - Download the dataset from Google Drive
#    - Extract the dataset to the specified directory
#    - Remove the downloaded archive file

set -e  # Exit on error

# Parse command line arguments
output_dir="./l2_arctic_data"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
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
  exit 0
fi

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