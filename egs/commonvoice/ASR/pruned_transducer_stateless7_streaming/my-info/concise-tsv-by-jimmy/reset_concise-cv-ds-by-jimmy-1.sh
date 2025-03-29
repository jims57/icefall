#!/bin/bash

# =====================================================================
# Reset CommonVoice Dataset Script
# =====================================================================
# This script resets the custom CommonVoice dataset to its original state
# by removing current files and restoring from backup copies.
#
# What this script does:
# 1. Removes the current custom_validated.tsv file
# 2. Removes the current clips directory
# 3. Removes dev.tsv, test.tsv, and train.tsv files
# 4. Restores clips directory from backup (clips-Copy1)
# 5. Restores custom_validated.tsv from backup (custom_validated-Copy1.tsv)
# 6. Cleans up the trash directory to free space
#
# Usage: ./reset_concise-cv-ds-by-jimmy-1.sh
# =====================================================================

echo "Starting dataset reset process..."

# Define base directory for better readability
BASE_DIR=~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/en

# Remove current files
echo "Removing current dataset files..."
rm -rf $BASE_DIR/custom_validated.tsv $BASE_DIR/clips

# Remove split TSV files
echo "Removing dev.tsv, test.tsv, and train.tsv files..."
rm -f $BASE_DIR/dev.tsv $BASE_DIR/test.tsv $BASE_DIR/train.tsv

# Restore from backups
echo "Restoring files from backup copies..."
cp -r $BASE_DIR/clips-Copy1 $BASE_DIR/clips
cp $BASE_DIR/custom_validated-Copy1.tsv $BASE_DIR/custom_validated.tsv

# Clean up trash
echo "Cleaning up trash directory..."
rm -rf ~/.local/share/Trash/*

echo "Dataset reset complete! The dataset has been restored to its original state."
echo "Note: dev.tsv, test.tsv, and train.tsv files have been removed and will need to be regenerated if needed."