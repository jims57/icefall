#!/bin/bash
# This script checks the number of audio files and TSV entries in the SpeechOcean762 dataset

echo "Checking SpeechOcean762 dataset statistics..."

# Count audio files
audio_count=$(ls -1 ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/clips | wc -l)
echo "Number of audio files in clips directory: $audio_count"

# Count TSV entries (excluding header)
tsv_count=$(tail -n +2 ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/custom_validated.tsv | wc -l)
echo "Number of entries in custom_validated.tsv: $tsv_count"

# Check if counts match
if [ "$audio_count" -eq "$tsv_count" ]; then
    echo "✓ Counts match: All audio files are properly indexed in the TSV file."
else
    echo "⚠ Warning: Mismatch between audio files ($audio_count) and TSV entries ($tsv_count)."
fi