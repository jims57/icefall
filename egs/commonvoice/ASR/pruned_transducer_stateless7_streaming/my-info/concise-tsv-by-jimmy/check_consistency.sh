#!/bin/bash

# check_consistency.sh - Script to check consistency between TSV file and clips directory

# Parse command line arguments
CUSTOM_VALIDATED_TSV="./en/custom_validated.tsv"  # Default value
CLIPS_DIR="./en/clips"  # Default value

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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "Running consistency check script..."

# Check if TSV file exists
if [ ! -f "${CUSTOM_VALIDATED_TSV}" ]; then
  echo "Error: TSV file '${CUSTOM_VALIDATED_TSV}' does not exist."
  exit 1
fi

# Check if clips directory exists
if [ ! -d "${CLIPS_DIR}" ]; then
  echo "Error: Clips directory '${CLIPS_DIR}' does not exist."
  exit 1
fi

# Count MP3 files in clips directory
MP3_COUNT=$(find "${CLIPS_DIR}" -name "*.mp3" | wc -l)

# Count entries in TSV file (excluding header)
TSV_COUNT=$(tail -n +2 "${CUSTOM_VALIDATED_TSV}" | wc -l)

echo "MP3 files in clips directory: ${MP3_COUNT}"
echo "Entries in TSV file: ${TSV_COUNT}"

# Check if counts match
if [ "${MP3_COUNT}" -eq "${TSV_COUNT}" ]; then
  echo "✓ Dataset is consistent: MP3 count matches TSV entry count."
  exit 0
else
  echo "⚠ Dataset is inconsistent: MP3 count (${MP3_COUNT}) does not match TSV entry count (${TSV_COUNT})."
  exit 1
fi
