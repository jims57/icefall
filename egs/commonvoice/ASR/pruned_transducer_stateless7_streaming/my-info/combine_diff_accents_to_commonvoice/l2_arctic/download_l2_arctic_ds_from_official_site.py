#!/usr/bin/env python3
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
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

"""
This script downloads the L2-Arctic dataset from a Google Drive link.
See email for all download link: https://mail.google.com/mail/u/0/#spam/FMfcgzQZTprJQcWWxpxcDgNVbchkVTsw
Designed to work on Ubuntu server or any standard Python environment.
"""

import os
import zipfile
import tarfile
import subprocess
import argparse
import shutil
import tempfile
from pathlib import Path
import time

def install_requirements():
    """
    Install required packages using pip.
    """
    try:
        import tqdm
    except ImportError:
        print("Installing tqdm...")
        subprocess.check_call(["pip", "install", "tqdm"])
        
    try:
        import gdown
    except ImportError:
        print("Installing gdown...")
        subprocess.check_call(["pip", "install", "gdown"])
    
    try:
        import librosa
    except ImportError:
        print("Installing librosa for audio duration calculation...")
        subprocess.check_call(["pip", "install", "librosa"])

def download_from_gdrive(file_id, output_file):
    """
    Download a file from Google Drive using the file ID.
    
    Args:
        file_id: The Google Drive file ID
        output_file: Local path to save the file
    """
    import gdown
    from tqdm import tqdm
    
    print(f"Downloading file from Google Drive to {output_file}...")
    url = f"https://drive.google.com/uc?id={file_id}"
    gdown.download(url, output_file, quiet=False)

def get_audio_duration(file_path):
    """
    Get the duration of an audio file in seconds.
    
    Args:
        file_path: Path to the audio file
    
    Returns:
        Duration in seconds or 0 if file can't be processed
    """
    try:
        import librosa
        duration = librosa.get_duration(path=file_path)
        return duration
    except Exception as e:
        print(f"Warning: Could not get duration for {file_path}: {e}")
        return 0

def extract_archive_with_limit(archive_file, output_dir, total_hours_limit=None):
    """
    Extract an archive file (zip, tar.gz, etc.) to the specified directory,
    with an optional limit on total audio duration.
    
    Args:
        archive_file: Path to the archive file
        output_dir: Directory to extract files to
        total_hours_limit: Maximum total hours of audio to include (None for no limit)
    
    Returns:
        True if extraction was successful, False otherwise
    """
    print(f"Extracting {archive_file} to {output_dir}...")
    
    # Create a temporary directory for extraction
    temp_dir = tempfile.mkdtemp(prefix="l2arctic_temp_")
    print(f"Using temporary directory for extraction: {temp_dir}")
    
    try:
        # Extract archive to temporary directory first
        if archive_file.endswith('.zip'):
            with zipfile.ZipFile(archive_file, 'r') as zip_ref:
                zip_ref.extractall(temp_dir)
        elif archive_file.endswith('.tar.gz') or archive_file.endswith('.tgz'):
            with tarfile.open(archive_file, 'r:gz') as tar_ref:
                tar_ref.extractall(temp_dir)
        elif archive_file.endswith('.tar'):
            with tarfile.open(archive_file, 'r') as tar_ref:
                tar_ref.extractall(temp_dir)
        else:
            print(f"Unsupported archive format: {archive_file}")
            shutil.rmtree(temp_dir)
            return False
        
        # If no hour limit is set, just move everything to the output directory
        if total_hours_limit is None:
            # Create output directory if it doesn't exist
            os.makedirs(output_dir, exist_ok=True)
            
            # Move all contents from temp_dir to output_dir
            for item in os.listdir(temp_dir):
                src_path = os.path.join(temp_dir, item)
                dst_path = os.path.join(output_dir, item)
                
                if os.path.exists(dst_path):
                    if os.path.isdir(dst_path):
                        shutil.rmtree(dst_path)
                    else:
                        os.remove(dst_path)
                
                shutil.move(src_path, dst_path)
            
            print(f"All files extracted without duration limits.")
            return True
        
        # If we're limiting by duration, process WAV files
        print(f"Limiting total audio duration to {total_hours_limit} hours...")
        
        # Find all WAV files in the extracted archive
        wav_files = []
        for root, _, files in os.walk(temp_dir):
            for file in files:
                if file.lower().endswith('.wav'):
                    wav_path = os.path.join(root, file)
                    # Get file creation/modification time for sorting
                    file_time = os.path.getmtime(wav_path)
                    wav_files.append((wav_path, file_time))
        
        # Sort WAV files by creation time (oldest first)
        wav_files.sort(key=lambda x: x[1])
        
        # Calculate total duration and copy files until limit
        total_seconds = 0
        seconds_limit = total_hours_limit * 3600
        files_to_keep = []
        
        for wav_path, _ in wav_files:
            duration = get_audio_duration(wav_path)
            
            # If adding this file would exceed the limit, stop
            if total_seconds + duration > seconds_limit:
                break
            
            # Add this file to the list of files to keep
            files_to_keep.append(wav_path)
            total_seconds += duration
        
        print(f"Selected {len(files_to_keep)} WAV files with total duration of {total_seconds/3600:.2f} hours")
        
        if len(files_to_keep) == 0:
            print("Warning: No audio files were selected. Check if the hour limit is too low.")
            return False
        
        # Create a mapping from full paths to relative paths for copying
        relative_paths = {}
        for wav_path in files_to_keep:
            rel_path = os.path.relpath(wav_path, temp_dir)
            relative_paths[wav_path] = rel_path
            
            # Also need to include corresponding text files
            base_path = os.path.splitext(wav_path)[0]
            txt_path = base_path + ".txt"
            if os.path.exists(txt_path):
                rel_txt_path = os.path.relpath(txt_path, temp_dir)
                relative_paths[txt_path] = rel_txt_path
            
            # Check for other related files (transcripts, labels, etc.)
            for ext in [".lab", ".TextGrid", ".json"]:
                related_path = base_path + ext
                if os.path.exists(related_path):
                    rel_related_path = os.path.relpath(related_path, temp_dir)
                    relative_paths[related_path] = rel_related_path
        
        # Copy only the selected files to the output directory
        for src_path, rel_path in relative_paths.items():
            dst_path = os.path.join(output_dir, rel_path)
            
            # Create parent directories if they don't exist
            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            
            # Copy the file
            shutil.copy2(src_path, dst_path)
        
        print(f"Copied {len(relative_paths)} files (audio + metadata) to {output_dir}")
        
        # Preserve the speaker directory structure
        for item in os.listdir(temp_dir):
            src_path = os.path.join(temp_dir, item)
            if os.path.isdir(src_path):
                # This is likely a speaker directory
                dst_path = os.path.join(output_dir, item)
                
                # Make sure the directory exists
                os.makedirs(dst_path, exist_ok=True)
                
                # Copy speaker metadata if it exists
                for meta_file in ["SPKR.txt", "info.txt", "README"]:
                    meta_path = os.path.join(src_path, meta_file)
                    if os.path.exists(meta_path):
                        shutil.copy2(meta_path, os.path.join(dst_path, meta_file))
        
        print(f"Final dataset size: {total_seconds/3600:.2f} hours ({len(files_to_keep)} files)")
        return True
        
    except Exception as e:
        print(f"Error during extraction with hour limit: {e}")
        return False
    finally:
        # Clean up temporary directory
        try:
            shutil.rmtree(temp_dir)
            print(f"Cleaned up temporary directory: {temp_dir}")
        except Exception as e:
            print(f"Error cleaning up temporary directory: {e}")

def download_l2_arctic_dataset(output_dir="./l2_arctic_data", total_hours=None):
    """
    Download the L2-Arctic dataset from Google Drive and extract it.
    
    Args:
        output_dir: Directory to save the extracted dataset
        total_hours: Maximum total hours of audio to include (None for no limit)
    """
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Google Drive file ID from the shared link
    file_id = "1ciCw_ttbw7a9r7d5DZzTJwoZq5rQB3TA"
    archive_file = "l2_arctic.zip"  # assuming it's a zip file
    
    # Install required packages if needed
    install_requirements()
    
    # Download the dataset
    download_from_gdrive(file_id, archive_file)
    
    # Check if download was successful
    if not os.path.exists(archive_file):
        print("Download failed. File not found.")
        return
    
    # Extract the dataset with optional hour limit
    extraction_successful = extract_archive_with_limit(archive_file, output_dir, total_hours)
    
    # Remove the archive file
    if os.path.exists(archive_file):
        os.remove(archive_file)
        print(f"Removed archive file: {archive_file}")
    
    if extraction_successful:
        print(f"\nDataset downloaded and extracted to {output_dir}")
        
        # List the contents of the dataset
        print("\nDataset contents:")
        file_count = 0
        wav_count = 0
        total_duration = 0
        
        for path in Path(output_dir).rglob("*"):
            if path.is_file():
                if path.suffix == '.wav':
                    wav_count += 1
                    duration = get_audio_duration(str(path))
                    total_duration += duration
                
                # Only show a limited number of files
                if file_count < 20:
                    print(f"  {path.relative_to(output_dir)}")
                    file_count += 1
                    if file_count == 20:
                        print("  ... (more files not shown)")
        
        print(f"\nTotal WAV files: {wav_count}")
        print(f"Total audio duration: {total_duration/3600:.2f} hours")
        
        if total_hours is not None:
            print(f"Requested duration limit: {total_hours:.2f} hours")
    else:
        print("\nExtraction failed.")
        print("Please download the dataset manually from the Google Drive link:")
        print("https://drive.google.com/file/d/1ciCw_ttbw7a9r7d5DZzTJwoZq5rQB3TA/view?usp=sharing")
        
        # Instructions for manual download
        print("\nManual download instructions:")
        print("1. Open the link in your browser")
        print("2. Click the download button in the top right corner")
        print("3. Extract the downloaded file to your desired location")

def main():
    """Parse arguments and download the dataset."""
    parser = argparse.ArgumentParser(
        description="Download L2-Arctic dataset from Google Drive"
    )
    parser.add_argument(
        "--output-dir", 
        type=str, 
        default="./l2_arctic_data", 
        help="Directory to save the dataset"
    )
    parser.add_argument(
        "--total-hours",
        type=float,
        default=None,
        help="Maximum total hours of audio to include (default: no limit)"
    )
    args = parser.parse_args()
    
    download_l2_arctic_dataset(args.output_dir, args.total_hours)

if __name__ == "__main__":
    main()
