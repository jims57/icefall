#!/bin/bash

# Define dataset path for better readability
DATASET_PATH=~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/en

# Print the actual path being used for debugging
echo "Using dataset path: $DATASET_PATH"

# Check if directories and files exist with user-friendly messages
if [ ! -d "$DATASET_PATH" ]; then
    echo "📁 Dataset directory not found at: $DATASET_PATH"
    echo "💡 Tip: Please check if the path is correct or create the directory."
    exit 1
fi

if [ ! -d "$DATASET_PATH/clips" ]; then
    echo "📁 Clips directory not found at: $DATASET_PATH/clips"
    echo "💡 Tip: Please create the 'clips' directory to store your audio files."
    exit 1
fi

if [ ! -f "$DATASET_PATH/custom_validated.tsv" ]; then
    echo "📄 TSV file not found at: $DATASET_PATH/custom_validated.tsv"
    echo "💡 Tip: Please ensure your TSV file is named 'custom_validated.tsv' and placed in the dataset directory."
    exit 1
fi

# Count audio files
echo "Checking dataset integrity..."
AUDIO_COUNT=$(ls -1 "$DATASET_PATH/clips" 2>/dev/null | wc -l)
echo "Number of audio files in clips directory: $AUDIO_COUNT"

# Count TSV entries (excluding header)
TSV_COUNT=$(tail -n +2 "$DATASET_PATH/custom_validated.tsv" 2>/dev/null | wc -l)
echo "Number of entries in TSV file: $TSV_COUNT"

# Check if counts match
if [ "$AUDIO_COUNT" -eq "$TSV_COUNT" ]; then
    echo "✓ Dataset is consistent: Audio files count matches TSV entries count."
else
    echo "⚠ Warning: Mismatch detected!"
    echo "  - Audio files: $AUDIO_COUNT"
    echo "  - TSV entries: $TSV_COUNT"
    echo "  - Difference: $(($AUDIO_COUNT - $TSV_COUNT))"
fi