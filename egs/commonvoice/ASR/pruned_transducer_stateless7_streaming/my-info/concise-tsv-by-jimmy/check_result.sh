#!/bin/bash

# Define dataset path for better readability
DATASET_PATH=~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/en

# Count audio files
echo "Checking dataset integrity..."
AUDIO_COUNT=$(ls -1 $DATASET_PATH/clips | wc -l)
echo "Number of audio files in clips directory: $AUDIO_COUNT"

# Count TSV entries (excluding header)
TSV_COUNT=$(tail -n +2 $DATASET_PATH/custom_validated.tsv | wc -l)
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