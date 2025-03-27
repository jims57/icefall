#!/bin/bash

# Default values for parameters
force_download=false
force_convert_mp3=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force-to-download)
      force_download=true
      shift
      ;;
    --force-to-convert-to-mp3)
      force_convert_mp3=true
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Usage: $0 [--force-to-download] [--force-to-convert-to-mp3]"
      exit 1
      ;;
  esac
done

# Define paths
l2_arctic_data_dir=~/icefall/egs/commonvoice/ASR/download/l2_arctic/l2_arctic_data
mp3_dir=~/icefall/egs/commonvoice/ASR/download/l2_arctic/en

# Handle force download if requested
if [ "$force_download" = true ]; then
  echo "🔄 Force download requested. Removing existing L2-ARCTIC data directory..."
  if [ -d "$l2_arctic_data_dir" ]; then
    echo "🗑️  Deleting: $l2_arctic_data_dir"
    rm -rf "$l2_arctic_data_dir"
    echo "✅ L2-ARCTIC data directory has been removed. It will be re-downloaded on next run."
  else
    echo "ℹ️  Directory $l2_arctic_data_dir does not exist. Nothing to delete."
  fi
fi

# Handle force convert to mp3 if requested
if [ "$force_convert_mp3" = true ]; then
  echo "🔄 Force MP3 conversion requested. Removing existing MP3 directory..."
  if [ -d "$mp3_dir" ]; then
    echo "🗑️  Deleting: $mp3_dir"
    rm -rf "$mp3_dir"
    echo "✅ MP3 directory has been removed. Files will be re-converted on next run."
  else
    echo "ℹ️  Directory $mp3_dir does not exist. Nothing to delete."
  fi
fi

echo "🎉 Reset operations completed!"
