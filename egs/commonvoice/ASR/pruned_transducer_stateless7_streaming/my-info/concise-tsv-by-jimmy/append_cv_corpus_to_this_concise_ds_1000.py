#!/usr/bin/env python3
# Copyright    2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# See ../../../../LICENSE for clarification regarding multiple authors
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

import os
import csv
import shutil
import argparse
import random
from pathlib import Path
from tqdm import tqdm
import logging
import sys

def setup_logger():
    """Set up the logger with formatting."""
    logging.basicConfig(
        format="%(asctime)s %(levelname)s [%(filename)s:%(lineno)d] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        level=logging.INFO,
        handlers=[logging.StreamHandler(sys.stdout)],
    )
    return logging.getLogger(__name__)

logger = setup_logger()

def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Append Common Voice corpus data to an existing dataset",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    
    parser.add_argument(
        "--cv-corpus-dir", 
        type=str, 
        default="../cv-corpus-20.0-2024-12-06",
        help="Path to Common Voice corpus directory"
    )
    
    parser.add_argument(
        "--target-dir", 
        type=str, 
        default=".",
        help="Directory where custom_validated.tsv and clips folder exist"
    )
    
    parser.add_argument(
        "--num-samples", 
        type=int, 
        default=1000,
        help="Number of samples to append from Common Voice corpus"
    )
    
    parser.add_argument(
        "--min-words", 
        type=int, 
        default=3,
        help="Minimum number of words required in a sentence"
    )
    
    parser.add_argument(
        "--random-seed", 
        type=int, 
        default=42,
        help="Random seed for reproducibility"
    )
    
    parser.add_argument(
        "--dry-run", 
        action="store_true",
        help="Show what would be done without actually copying files"
    )
    
    parser.add_argument(
        "--verbose", 
        action="store_true",
        help="Print detailed information during processing"
    )
    
    return parser.parse_args()

def count_words(sentence):
    """Count the number of words in a sentence."""
    if not sentence or sentence.isspace():
        return 0
    return len(sentence.strip().split())

def verify_tsv_fields(tsv_path):
    """Verify the TSV file has the expected field structure."""
    try:
        with open(tsv_path, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            header = next(reader)
            
            expected_fields = [
                'client_id', 'path', 'sentence_id', 'sentence', 
                'sentence_domain', 'up_votes', 'down_votes', 
                'age', 'gender', 'accents', 'variant', 'locale', 'segment'
            ]
            
            if len(header) < 4:  # At minimum, we need client_id, path, sentence_id, sentence
                logger.error(f"TSV file missing essential fields. Found: {header}")
                return False
                
            if header[0] != 'client_id' or header[1] != 'path' or header[3] != 'sentence':
                logger.error(f"TSV file has unexpected field structure. Found: {header}")
                return False
                
            return True
    except Exception as e:
        logger.error(f"Error verifying TSV structure: {e}")
        return False

def read_source_data(source_tsv, num_samples, min_words, seed):
    """Read source data from CommonVoice TSV file."""
    logger.info(f"Reading source data from {source_tsv}")
    
    if not os.path.exists(source_tsv):
        logger.error(f"Source TSV file not found: {source_tsv}")
        return [], None
    
    with open(source_tsv, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)  # Read and store header
        rows = []
        
        # Read all eligible rows (with sufficient words)
        for row in reader:
            # Skip rows that don't have at least 4 columns
            if len(row) < 4:
                continue
                
            sentence = row[3]
            if count_words(sentence) >= min_words:
                rows.append(row)
    
    logger.info(f"Found {len(rows)} eligible rows with at least {min_words} words")
    
    # Sample randomly if we have more rows than needed
    if 0 < num_samples < len(rows):
        random.seed(seed)
        rows = random.sample(rows, num_samples)
        logger.info(f"Randomly sampled {num_samples} rows")
    
    return rows, header

def read_target_data(target_tsv):
    """Read existing data from target TSV file."""
    if not os.path.exists(target_tsv):
        logger.warning(f"Target TSV file not found: {target_tsv}. Creating new file.")
        return [], None
    
    existing_paths = set()
    existing_sentences = set()
    
    with open(target_tsv, 'r', encoding='utf-8') as f:
        reader = csv.reader(f, delimiter='\t')
        header = next(reader)  # Store header
        rows = list(reader)
        
        for row in rows:
            if len(row) > 1:  # Check path exists
                path = row[1]
                if path:
                    existing_paths.add(os.path.basename(path))
            
            if len(row) > 3:  # Check sentence exists
                sentence = row[3]
                if sentence:
                    existing_sentences.add(sentence.strip())
    
    logger.info(f"Read {len(rows)} existing rows from {target_tsv}")
    return rows, header

def append_data(source_rows, target_rows, source_header, target_header, target_tsv):
    """Append source data to target TSV, handling duplicate detection."""
    logger.info(f"Appending data to {target_tsv}")
    
    # Create sets of existing data for duplicate detection
    existing_paths = set()
    existing_sentences = set()
    
    for row in target_rows:
        if len(row) > 1 and row[1]:  # Path column
            existing_paths.add(os.path.basename(row[1]))
        if len(row) > 3 and row[3]:  # Sentence column
            existing_sentences.add(row[3].strip())
    
    # Filter source rows to exclude duplicates
    new_rows = []
    duplicates = 0
    
    for row in source_rows:
        is_duplicate = False
        
        if len(row) > 1 and row[1]:
            path = os.path.basename(row[1])
            if path in existing_paths:
                is_duplicate = True
        
        if len(row) > 3 and row[3]:
            sentence = row[3].strip()
            if sentence in existing_sentences:
                is_duplicate = True
        
        if not is_duplicate:
            new_rows.append(row)
            
            # Add to sets to prevent duplicates within source rows
            if len(row) > 1 and row[1]:
                existing_paths.add(os.path.basename(row[1]))
            if len(row) > 3 and row[3]:
                existing_sentences.add(row[3].strip())
        else:
            duplicates += 1
    
    logger.info(f"Found {duplicates} duplicates (skipped)")
    logger.info(f"Adding {len(new_rows)} new rows")
    
    # Ensure target directory exists
    os.makedirs(os.path.dirname(target_tsv), exist_ok=True)
    
    # If target TSV is empty, use source header
    header_to_use = target_header if target_header else source_header
    
    # Write combined data to target TSV
    with open(target_tsv, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, delimiter='\t')
        writer.writerow(header_to_use)
        writer.writerows(target_rows)
        writer.writerows(new_rows)
    
    return new_rows

def copy_mp3_files(new_rows, source_clips_dir, target_clips_dir, dry_run=False):
    """Copy MP3 files corresponding to new rows from source to target directory."""
    if not os.path.exists(source_clips_dir):
        logger.error(f"Source clips directory not found: {source_clips_dir}")
        return 0
    
    # Create target directory if it doesn't exist
    if not dry_run:
        os.makedirs(target_clips_dir, exist_ok=True)
    
    # Copy MP3 files
    copied_count = 0
    missing_count = 0
    
    for row in tqdm(new_rows, desc="Copying MP3 files"):
        if len(row) <= 1 or not row[1]:
            continue
            
        mp3_file = os.path.basename(row[1])
        source_path = os.path.join(source_clips_dir, mp3_file)
        target_path = os.path.join(target_clips_dir, mp3_file)
        
        if os.path.exists(source_path):
            if not dry_run:
                shutil.copy2(source_path, target_path)
            copied_count += 1
        else:
            logger.warning(f"MP3 file not found: {source_path}")
            missing_count += 1
    
    if dry_run:
        logger.info(f"[DRY RUN] Would copy {copied_count} MP3 files")
    else:
        logger.info(f"Copied {copied_count} MP3 files to {target_clips_dir}")
    
    if missing_count > 0:
        logger.warning(f"Could not find {missing_count} MP3 files")
    
    return copied_count

def verify_results(target_tsv, target_clips_dir):
    """Verify that the TSV entries match the files in the clips directory."""
    try:
        # Count TSV entries
        with open(target_tsv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter='\t')
            next(reader)  # Skip header
            tsv_count = sum(1 for _ in reader)
        
        # Count MP3 files
        mp3_count = len([f for f in os.listdir(target_clips_dir) if f.endswith('.mp3')])
        
        logger.info(f"Verification results:")
        logger.info(f"  - TSV entries: {tsv_count}")
        logger.info(f"  - MP3 files: {mp3_count}")
        
        if tsv_count != mp3_count:
            logger.warning(f"Mismatch between TSV entries ({tsv_count}) and MP3 files ({mp3_count})")
            return False
            
        return True
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return False

def main():
    """Main function to append CommonVoice corpus data to existing dataset."""
    args = parse_args()
    
    if args.verbose:
        logger.setLevel(logging.DEBUG)
    
    logger.info("=== Starting Common Voice corpus append operation ===")
    logger.info(f"Source directory: {args.cv_corpus_dir}")
    logger.info(f"Target directory: {args.target_dir}")
    logger.info(f"Samples to append: {args.num_samples}")
    logger.info(f"Minimum words per sentence: {args.min_words}")
    
    if args.dry_run:
        logger.info("DRY RUN MODE: No files will be modified")
    
    # Define file paths
    source_tsv = os.path.join(args.cv_corpus_dir, "en", "train.tsv")
    source_clips_dir = os.path.join(args.cv_corpus_dir, "en", "clips")
    
    target_tsv = os.path.join(args.target_dir, "en", "custom_validated.tsv")
    target_clips_dir = os.path.join(args.target_dir, "en", "clips")
    
    # Make sure paths are correctly resolved
    source_tsv = os.path.abspath(source_tsv)
    source_clips_dir = os.path.abspath(source_clips_dir)
    target_tsv = os.path.abspath(target_tsv)
    target_clips_dir = os.path.abspath(target_clips_dir)
    
    # Verify source data exists
    if not os.path.exists(source_tsv):
        logger.error(f"Source TSV file not found: {source_tsv}")
        return 1
    
    if not os.path.exists(source_clips_dir):
        logger.error(f"Source clips directory not found: {source_clips_dir}")
        return 1
    
    # Verify TSV structure
    if not verify_tsv_fields(source_tsv):
        logger.error("Source TSV file has invalid structure")
        return 1
    
    # Read source data
    source_rows, source_header = read_source_data(
        source_tsv, 
        args.num_samples, 
        args.min_words, 
        args.random_seed
    )
    
    if not source_rows:
        logger.error("No eligible source data found")
        return 1
    
    # Read target data
    target_rows, target_header = read_target_data(target_tsv)
    
    # Ensure target directory exists
    os.makedirs(os.path.dirname(target_tsv), exist_ok=True)
    
    # Append data (if not in dry run mode)
    if not args.dry_run:
        new_rows = append_data(source_rows, target_rows, source_header, target_header, target_tsv)
        
        # Copy MP3 files
        copy_mp3_files(new_rows, source_clips_dir, target_clips_dir)
        
        # Verify results
        verify_results(target_tsv, target_clips_dir)
    else:
        # In dry run mode, just show what would be done
        existing_paths = set()
        existing_sentences = set()
        
        for row in target_rows:
            if len(row) > 1 and row[1]:
                existing_paths.add(os.path.basename(row[1]))
            if len(row) > 3 and row[3]:
                existing_sentences.add(row[3].strip())
        
        new_rows = []
        duplicates = 0
        
        for row in source_rows:
            is_duplicate = False
            
            if len(row) > 1 and row[1]:
                path = os.path.basename(row[1])
                if path in existing_paths:
                    is_duplicate = True
            
            if len(row) > 3 and row[3]:
                sentence = row[3].strip()
                if sentence in existing_sentences:
                    is_duplicate = True
            
            if not is_duplicate:
                new_rows.append(row)
            else:
                duplicates += 1
        
        logger.info(f"[DRY RUN] Would add {len(new_rows)} new rows and skip {duplicates} duplicates")
        logger.info(f"[DRY RUN] Would copy {len(new_rows)} MP3 files")
    
    logger.info("=== Operation completed successfully ===")
    return 0

if __name__ == "__main__":
    sys.exit(main())
