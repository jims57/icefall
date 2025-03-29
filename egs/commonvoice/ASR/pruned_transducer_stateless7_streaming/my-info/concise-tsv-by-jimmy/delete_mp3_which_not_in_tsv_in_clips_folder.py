#!/usr/bin/env python3

import os
import csv
import argparse

def main():
    parser = argparse.ArgumentParser(
        description="Delete MP3 files in clips folder that are not in the TSV file."
    )
    parser.add_argument(
        "--tsv-file", 
        type=str, 
        default="validated.tsv", 
        help="Path to the TSV file containing valid MP3 records"
    )
    parser.add_argument(
        "--clips-dir", 
        type=str, 
        default="clips", 
        help="Directory containing MP3 files"
    )
    parser.add_argument(
        "--dry-run", 
        action="store_true", 
        help="Only print files to be deleted without actually deleting them. Set to False or omit this flag to actually delete files."
    )
    args = parser.parse_args()

    # Read MP3 filenames from the TSV file
    valid_mp3s = set()
    with open(args.tsv_file, 'r', encoding='utf-8') as tsv_file:
        reader = csv.reader(tsv_file, delimiter='\t')
        # Skip header
        next(reader)
        for row in reader:
            if len(row) >= 2:  # Ensure we have at least the path field
                valid_mp3s.add(row[1])  # path is in the second column (index 1)

    print(f"Found {len(valid_mp3s)} valid MP3 files in the TSV")

    # List all MP3 files in the clips directory
    if not os.path.exists(args.clips_dir):
        print(f"Error: Clips directory {args.clips_dir} does not exist!")
        return

    all_mp3s = [f for f in os.listdir(args.clips_dir) if f.endswith('.mp3')]
    print(f"Found {len(all_mp3s)} MP3 files in {args.clips_dir}")

    # Find MP3 files that are not in the TSV
    to_delete = [mp3 for mp3 in all_mp3s if mp3 not in valid_mp3s]
    print(f"Found {len(to_delete)} MP3 files to delete")

    # Delete the files or just print them if in dry-run mode
    for mp3 in to_delete:
        mp3_path = os.path.join(args.clips_dir, mp3)
        if args.dry_run:
            print(f"Would delete: {mp3_path}")
        else:
            try:
                os.remove(mp3_path)
                print(f"Deleted: {mp3_path}")
            except Exception as e:
                print(f"Error deleting {mp3_path}: {e}")

    if not args.dry_run:
        print(f"Deleted {len(to_delete)} MP3 files that were not in the TSV")
    else:
        print(f"Dry run completed. Would delete {len(to_delete)} MP3 files")

if __name__ == "__main__":
    main()
