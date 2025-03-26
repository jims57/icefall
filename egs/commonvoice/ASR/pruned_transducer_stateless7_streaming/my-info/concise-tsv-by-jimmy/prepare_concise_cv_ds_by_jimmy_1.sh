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

set -e  # Exit on error
set -u  # Error on undefined variables
set -o pipefail  # Exit if any command in a pipe fails

echo "Starting preparation of concise CommonVoice dataset..."

# Default parameters
CUSTOM_VALIDATED_TSV="custom_validated.tsv"
CLIPS_DIR="./clips"
DEV_RATIO=0.1
TEST_RATIO=0.1
SEED=42

# Step 1: Fix dataset mismatch
echo "Step 1: Fixing dataset mismatch..."
if [ -f "fix_dataset_mismatch.py" ]; then
  python3 fix_dataset_mismatch.py
  echo "Dataset mismatch fix completed."
else
  echo "Error: fix_dataset_mismatch.py not found."
  exit 1
fi

# Step 2: Check consistency
echo "Step 2: Checking dataset consistency..."
if [ -f "check_consistency.sh" ]; then
  bash check_consistency.sh
  
  # Check if the consistency check was successful
  if [ $? -ne 0 ]; then
    echo "Error: Dataset consistency check failed. Please fix the inconsistencies before proceeding."
    exit 1
  fi
  echo "Dataset consistency check passed."
else
  echo "Error: check_consistency.sh not found."
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
else
  echo "Error: Failed to create all required TSV files."
  exit 1
fi

echo "Dataset preparation complete!"
