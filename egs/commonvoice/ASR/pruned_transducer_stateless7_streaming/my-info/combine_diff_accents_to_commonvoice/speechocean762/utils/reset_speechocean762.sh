#!/bin/bash
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# This script resets the SpeechOcean762 dataset by removing processed files

echo "Resetting SpeechOcean762 dataset..."

# Define paths
CLIPS_DIR=~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips
TSV_FILE=~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/custom_validated.tsv

# Remove clips directory
if [ -d "$CLIPS_DIR" ]; then
    echo "Removing clips directory: $CLIPS_DIR"
    rm -rf "$CLIPS_DIR"
    echo "✓ Clips directory removed successfully."
else
    echo "Note: Clips directory does not exist, nothing to remove."
fi

# Remove TSV file
if [ -f "$TSV_FILE" ]; then
    echo "Removing TSV file: $TSV_FILE"
    rm -f "$TSV_FILE"
    echo "✓ TSV file removed successfully."
else
    echo "Note: TSV file does not exist, nothing to remove."
fi

echo "Reset complete. The SpeechOcean762 dataset is now ready for fresh processing."