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
echo "  2. Reset custom_validated.tsv to header-only"
echo "  3. Empty the trash folder to free up space"
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

# Reset custom_validated.tsv file
echo ""
echo "Step 2: Resetting custom_validated.tsv to header-only..."
if [ -f "@custom_validated.tsv" ]; then
    echo "  - Saving header from @custom_validated.tsv..."
    head -n 1 "@custom_validated.tsv" > "@custom_validated.tsv.header"
    echo "  - Replacing @custom_validated.tsv with header only..."
    mv "@custom_validated.tsv.header" "@custom_validated.tsv"
    echo "    @custom_validated.tsv reset successfully."
elif [ -f "custom_validated.tsv" ]; then
    echo "  - Saving header from custom_validated.tsv..."
    head -n 1 "custom_validated.tsv" > "custom_validated.tsv.header"
    echo "  - Replacing custom_validated.tsv with header only..."
    mv "custom_validated.tsv.header" "custom_validated.tsv"
    echo "    custom_validated.tsv reset successfully."
else
    echo "  - No custom_validated.tsv file found, skipping."
    # List files for debugging
    echo "    Available files: $(ls -la | grep -i custom)"
fi

# Empty trash
echo ""
echo "Step 3: Emptying trash folder..."
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
