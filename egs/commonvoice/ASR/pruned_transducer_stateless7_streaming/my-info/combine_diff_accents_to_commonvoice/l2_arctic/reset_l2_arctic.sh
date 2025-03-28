#!/bin/bash

# Define paths
l2_arctic_data_dir=./l2_arctic_data
mp3_dir=./en

# Remove L2-ARCTIC data directory
echo "🔄 Removing existing L2-ARCTIC data directory..."
if [ -d "$l2_arctic_data_dir" ]; then
  echo "🗑️  Deleting: $l2_arctic_data_dir"
  rm -rf "$l2_arctic_data_dir"
  echo "✅ L2-ARCTIC data directory has been removed."
else
  echo "ℹ️  Directory $l2_arctic_data_dir does not exist. Nothing to delete."
fi

# Remove MP3 directory
echo "🔄 Removing existing MP3 directory..."
if [ -d "$mp3_dir" ]; then
  echo "🗑️  Deleting: $mp3_dir"
  rm -rf "$mp3_dir"
  echo "✅ MP3 directory has been removed."
else
  echo "ℹ️  Directory $mp3_dir does not exist. Nothing to delete."
fi

# Empty the trash to free up space
echo "🔄 Emptying trash to free up space..."
rm -rf ~/.local/share/Trash/*
echo "✅ Trash has been emptied."

echo "🎉 Reset operations completed!"
