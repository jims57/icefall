#!/usr/bin/env python3

import os
import argparse
import pandas as pd
from pathlib import Path
from tqdm import tqdm

def main():
    parser = argparse.ArgumentParser(
        description="Check if MP3 files in custom_validated.tsv exist in the clips folder"
    )
    parser.add_argument(
        "--tsv-file", 
        type=str, 
        default="./custom_validated.tsv",
        help="Path to the custom_validated.tsv file (default: ./custom_validated.tsv)"
    )
    parser.add_argument(
        "--clips-dir", 
        type=str, 
        default="./clips",
        help="Path to the clips directory containing MP3 files (default: ./clips)"
    )
    args = parser.parse_args()

    # Check if the TSV file exists
    if not os.path.isfile(args.tsv_file):
        print(f"Error: TSV file '{args.tsv_file}' does not exist.")
        return 1

    # Check if the clips directory exists
    if not os.path.isdir(args.clips_dir):
        print(f"Error: Clips directory '{args.clips_dir}' does not exist.")
        return 1

    # Read the TSV file
    print(f"Reading TSV file: {args.tsv_file}")
    try:
        df = pd.read_csv(args.tsv_file, sep='\t')
    except Exception as e:
        print(f"Error reading TSV file: {e}")
        return 1

    # Check if 'path' column exists
    if 'path' not in df.columns:
        print("Error: 'path' column not found in the TSV file.")
        return 1

    # Extract MP3 filenames from the path column
    mp3_files = df['path'].tolist()
    
    # Check if each MP3 file exists in the clips directory
    missing_files = []
    print(f"Checking {len(mp3_files)} MP3 files...")
    
    for mp3_file in tqdm(mp3_files):
        mp3_path = os.path.join(args.clips_dir, mp3_file)
        if not os.path.isfile(mp3_path):
            missing_files.append(mp3_file)
    
    # Report results
    if missing_files:
        print(f"\n{len(missing_files)} MP3 files from the TSV are missing in the clips folder:")
        for file in missing_files:
            print(f"  - {file}")
        print(f"\nTotal missing files: {len(missing_files)} out of {len(mp3_files)} ({len(missing_files)/len(mp3_files)*100:.2f}%)")
    else:
        print(f"\nAll {len(mp3_files)} MP3 files from the TSV exist in the clips folder.")
    
    return 0

if __name__ == "__main__":
    exit(main())
