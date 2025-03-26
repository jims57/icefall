#!/bin/bash

# Exit on error
set -e

echo "Installing pandas package..."
pip install pandas

echo "Running consistency check script..."
python check_mp3_and_custom_validated_tsv_consistency.py

echo "Consistency check completed."
