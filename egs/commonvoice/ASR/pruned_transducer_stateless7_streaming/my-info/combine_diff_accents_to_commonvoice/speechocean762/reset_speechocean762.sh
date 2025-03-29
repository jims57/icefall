#!/bin/bash

# reset_speechocean762.sh
# Purpose: Clean up SpeechOcean762 data folders and empty trash
# Usage: ./reset_speechocean762.sh

echo "====================================================="
echo "  SpeechOcean762 Data Cleanup Script"
echo "====================================================="
echo "This script will delete the following folders:"
echo "  - WAVE"
echo "  - train"
echo "  - test"
echo "  - download"
echo "  - clips"
echo "And the following files:"
echo "  - custom_validated.tsv"
echo "And will also empty your trash folder."
echo "====================================================="

# Function to delete a folder with feedback
delete_folder() {
    folder="$1"
    if [ -d "$folder" ]; then
        echo "Deleting $folder folder..."
        rm -rf "$folder"
        echo "✓ $folder deleted successfully."
    else
        echo "! $folder folder not found, skipping."
    fi
}

# Function to delete a file with feedback
delete_file() {
    file="$1"
    if [ -f "$file" ]; then
        echo "Deleting $file file..."
        rm -f "$file"
        echo "✓ $file deleted successfully."
    else
        echo "! $file not found, skipping."
    fi
}

# Delete each folder
delete_folder "WAVE"
delete_folder "train"
delete_folder "test"
delete_folder "download"
delete_folder "clips"

# Delete specific files
delete_file "custom_validated.tsv"

# Empty trash
echo "Emptying trash folder..."
rm -rf ~/.local/share/Trash/*
echo "✓ Trash emptied successfully."

echo "====================================================="
echo "Cleanup completed!"
echo "====================================================="
