#!/usr/bin/env python3
#!/usr/bin/env python3
# Copyright (c) 2023 Jimmy
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
This script creates train, dev, and test TSV files from validated.tsv based on
available MP3 files. It selects rows from validated.tsv where the MP3 file exists
in the clips directory, and splits them into train, dev, and test sets.

Usage:
    python create-training-tsv-files-based-on-mp3-files.py --total-rows 1000 --clips-dir ../clips

This will select up to 1000 rows from validated.tsv where the MP3 files exist in
the ../clips directory, and split them into train, dev, and test sets according
to the specified ratios.
"""



import argparse
import csv
import os
import random
import shutil
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create train, dev, and test TSV files from custom_validated.tsv."
    )
    parser.add_argument(
        "--dev-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for dev set.",
    )
    parser.add_argument(
        "--test-ratio",
        type=float,
        default=0.1,
        help="Ratio of rows to use for test set.",
    )
    parser.add_argument(
        "--custom-validated-tsv",
        type=str,
        default="custom_validated.tsv",
        help="Path to the custom_validated.tsv file.",
    )
    parser.add_argument(
        "--clips-dir",
        type=str,
        default="../clips",
        help="Path to the clips directory containing MP3 files.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility.",
    )
    return parser.parse_args()


def count_rows(tsv_file):
    """Count the number of rows in a TSV file (excluding header)."""
    with open(tsv_file, "r", encoding="utf-8") as f:
        return sum(1 for _ in f) - 1  # Subtract 1 for the header


def select_random_rows(tsv_file, total_rows, num_to_select, random_seed):
    """
    Use reservoir sampling to select random rows from a potentially large file
    without loading the entire file into memory.
    """
    random.seed(random_seed)
    
    # If we need most of the rows, it's more efficient to select rows to exclude
    if num_to_select > total_rows / 2:
        # Generate indices to exclude
        exclude_indices = set(random.sample(range(1, total_rows + 1), total_rows - num_to_select))
        
        selected_rows = []
        with open(tsv_file, "r", encoding="utf-8") as f:
            reader = csv.reader(f, delimiter="\t")
            header = next(reader)  # Skip the header
            
            for i, row in enumerate(reader, 1):
                if i not in exclude_indices:
                    selected_rows.append(row)
    else:
        # Generate indices to include (more efficient for smaller selections)
        include_indices = set(random.sample(range(1, total_rows + 1), num_to_select))
        
        selected_rows = []
        with open(tsv_file, "r", encoding="utf-8") as f:
            reader = csv.reader(f, delimiter="\t")
            header = next(reader)  # Skip the header
            
            for i, row in enumerate(reader, 1):
                if i in include_indices:
                    selected_rows.append(row)
    
    return header, selected_rows


def write_tsv_file(filename, header, rows):
    """Write rows to a TSV file with the given header."""
    with open(filename, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(header)
        writer.writerows(rows)


def main():
    args = parse_args()
    
    # Validate the input parameters
    if args.dev_ratio + args.test_ratio >= 1.0:
        raise ValueError("The sum of dev_ratio and test_ratio should be less than 1.0")
    
    # Filter out rows with empty sentences from custom_validated.tsv
    filtered_rows = []
    empty_sentence_count = 0
    
    with open(args.custom_validated_tsv, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)  # Get the header
        
        # Find the index of the sentence column
        sentence_idx = header.index("sentence") if "sentence" in header else 2  # Default to index 2 if not found
        
        # Filter rows with empty sentences
        for row in reader:
            if len(row) > sentence_idx and row[sentence_idx].strip():  # Check if sentence is not empty
                filtered_rows.append(row)
            else:
                empty_sentence_count += 1
                print(f"Skipping row with empty sentence: {row[1] if len(row) > 1 else 'unknown'}")
    
    print(f"Removed {empty_sentence_count} rows with empty sentences")
    
    # Write the filtered rows back to custom_validated.tsv
    with open(args.custom_validated_tsv, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(header)
        writer.writerows(filtered_rows)
    
    print(f"Updated {args.custom_validated_tsv} with {len(filtered_rows)} valid rows")
    
    # Get the set of valid MP3 filenames from the filtered rows
    valid_mp3s = set()
    for row in filtered_rows:
        mp3_path = row[1]  # The path column (index 1) contains the mp3 filename
        # Extract just the filename from the path
        mp3_filename = os.path.basename(mp3_path)
        valid_mp3s.add(mp3_filename)
    
    # Delete any MP3 files in the clips directory that aren't in the valid set
    clips_dir = Path(args.clips_dir)
    if clips_dir.exists() and clips_dir.is_dir():
        print(f"Checking MP3 files in {clips_dir}...")
        deleted_count = 0
        
        for mp3_file in clips_dir.glob("*.mp3"):
            if mp3_file.name not in valid_mp3s:
                print(f"Deleting MP3 file not in valid set: {mp3_file.name}")
                mp3_file.unlink()
                deleted_count += 1
        
        print(f"Deleted {deleted_count} MP3 files not corresponding to valid entries")
    
    # Continue with the filtered rows
    all_rows = filtered_rows
    print(f"Total data rows in {args.custom_validated_tsv} after filtering: {len(all_rows)}")
    
    # Shuffle the rows to ensure randomness in the split
    random.seed(args.seed)
    random.shuffle(all_rows)
    
    num_to_select = len(all_rows)
    
    # For small datasets: ensure exact allocation with minimums of 1 for dev/test
    if num_to_select >= 3:
        # For small datasets, we need to be very precise
        if num_to_select <= 10:
            # With small datasets, ensure at least 1 each for dev/test, and rest to train
            dev_size = 1
            test_size = 1
            train_size = num_to_select - dev_size - test_size
        else:
            # For larger datasets, calculate based on ratios
            dev_size = max(1, round(num_to_select * args.dev_ratio))
            test_size = max(1, round(num_to_select * args.test_ratio))
            
            # Ensure we don't over-allocate (leaving no train data)
            if dev_size + test_size >= num_to_select:
                dev_size = 1
                test_size = 1
                
            # All remaining rows go to train
            train_size = num_to_select - dev_size - test_size
    else:
        # If we have fewer than 3 rows, prioritize train set
        print("Warning: Not enough data for all three splits. Prioritizing train set.")
        if num_to_select == 2:
            dev_size = 1
            test_size = 0
            train_size = 1
        elif num_to_select == 1:
            dev_size = 0
            test_size = 0
            train_size = 1
        else:  # num_to_select == 0
            dev_size = 0
            test_size = 0
            train_size = 0
    
    print(f"Creating dev.tsv with {dev_size} data rows")
    print(f"Creating test.tsv with {test_size} data rows")
    print(f"Creating train.tsv with {train_size} data rows")
    print(f"Total data rows in all splits: {dev_size + test_size + train_size}")
    
    # Verify the total count is correct
    assert dev_size + test_size + train_size == num_to_select, \
           f"Row count mismatch: {dev_size} + {test_size} + {train_size} != {num_to_select}"
    
    # Split the rows
    dev_rows = all_rows[:dev_size]
    test_rows = all_rows[dev_size:dev_size + test_size]
    train_rows = all_rows[dev_size + test_size:]
    
    # Double-check that all rows are accounted for
    assert len(dev_rows) + len(test_rows) + len(train_rows) == len(all_rows), \
           f"Error: Not all rows were allocated to splits. Got {len(dev_rows) + len(test_rows) + len(train_rows)} but expected {len(all_rows)}"
    
    # Write the TSV files
    write_tsv_file("dev.tsv", header, dev_rows)
    write_tsv_file("test.tsv", header, test_rows)
    write_tsv_file("train.tsv", header, train_rows)

    # Additional debug info to confirm file sizes
    print(f"Wrote {len(dev_rows)} data rows to dev.tsv")
    print(f"Wrote {len(test_rows)} data rows to test.tsv")
    print(f"Wrote {len(train_rows)} data rows to train.tsv")
    print(f"Each file also has 1 header row")
    
    print("Done!")


if __name__ == "__main__":
    main()