#!/bin/bash

#################################################
# reset_people_speech.sh
# 
# This script deletes People Speech data directories
# and empties the trash to free up disk space.
#################################################

echo "=========================================="
echo "  People Speech Data Reset Tool"
echo "=========================================="
echo "This script will:"
echo "  1. Delete clips and people_speech_data directories"
echo "  2. Empty the trash folder to free up space"
echo ""

# Display current working directory for debugging
echo "Current working directory: $(pwd)"
echo ""

# Delete People Speech directories - checking both with and without @ prefix
echo "Step 1: Deleting People Speech data directories..."

# Check for clips directory with or without @ prefix
if [ -d "@clips" ]; then
    echo "  - Removing @clips directory..."
    rm -rf "@clips"
    echo "    @clips removed successfully."
elif [ -d "clips" ]; then
    echo "  - Removing clips directory..."
    rm -rf "clips"
    echo "    clips removed successfully."
else
    echo "  - No clips directory found, skipping."
    # List directories for debugging
    echo "    Available directories: $(ls -la | grep -i clips)"
fi

# Check for people_speech_data directory with or without @ prefix
if [ -d "@people_speech_data" ]; then
    echo "  - Removing @people_speech_data directory..."
    rm -rf "@people_speech_data"
    echo "    @people_speech_data removed successfully."
elif [ -d "people_speech_data" ]; then
    echo "  - Removing people_speech_data directory..."
    rm -rf "people_speech_data"
    echo "    people_speech_data removed successfully."
else
    echo "  - No people_speech_data directory found, skipping."
    # List directories for debugging
    echo "    Available directories: $(ls -la | grep -i people)"
fi

# Empty trash
echo ""
echo "Step 2: Emptying trash folder..."
if [ -d ~/.local/share/Trash ]; then
    rm -rf ~/.local/share/Trash/*
    echo "  - Trash has been emptied successfully."
else
    echo "  - Trash folder not found at ~/.local/share/Trash"
fi

echo ""
echo "=========================================="
echo "  Reset completed successfully!"
echo "=========================================="
