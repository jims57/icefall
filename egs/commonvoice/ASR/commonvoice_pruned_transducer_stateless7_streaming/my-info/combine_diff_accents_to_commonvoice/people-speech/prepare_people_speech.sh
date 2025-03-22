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
# Important: Both prepare_people_speech.sh and download_people_speech_parquets_files.py
# must be uploaded to your working folder before running these commands.
#
# Download 10 files (default):
# bash prepare_people_speech.sh
#
# Download a specific number of files:
# bash prepare_people_speech.sh --download-total 20
#
# This script:
# 1. Checks and installs required packages (pandas, pyarrow, requests, tqdm)
# 2. Creates the people_speech_data directory if it doesn't exist
# 3. Downloads People's Speech dataset parquet files

# Default value for download-total
download_total=10

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --download-total)
      download_total="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check and install required packages
for package in pandas pyarrow requests tqdm; do
  if ! python -c "import $package" 2>/dev/null; then
    echo "Installing $package..."
    pip install "$package"
  else
    echo "$package is already installed."
  fi
done

# Create directory if it doesn't exist
if [ ! -d "people_speech_data" ]; then
  echo "Creating people_speech_data directory..."
  mkdir -p people_speech_data
else
  echo "Directory people_speech_data already exists."
fi

# Run the Python script with the specified parameter
echo "Running download script with download-total=$download_total..."
python download_people_speech_parquets_files.py --download-total "$download_total"

echo "People Speech preparation completed."
