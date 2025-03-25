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
        import requests
    except ImportError:
        print("Installing requests...")
        subprocess.check_call(["pip", "install", "requests"])
    
    try:
        import librosa
    except ImportError:
        print("Installing librosa for audio duration calculation...")
        subprocess.check_call(["pip", "install", "librosa"])

def download_from_huggingface(file_name, output_path, repo_id="jims57/l2_arctic_dataset", repo_type="model", revision="main"):
    """
    Download a file from Hugging Face repository
    
    Args:
        file_name: The file name to download
        output_path: Local path to save the file
        repo_id: The Hugging Face repository ID
        repo_type: The repository type (model, dataset, etc.)
        revision: The branch name
    """
    import requests
    from tqdm import tqdm
    
    # URL for the file
    url = f"https://huggingface.co/{repo_id}/resolve/{revision}/main/{file_name}"
    
    print(f"Downloading {file_name} from Hugging Face to {output_path}...")
    
    # Send a GET request to the URL
    response = requests.get(url, stream=True)
    
    # Check if the request was successful
    if response.status_code == 200:
        # Get the total file size
        total_size = int(response.headers.get('content-length', 0))
        
        # Create a progress bar
        progress_bar = tqdm(total=total_size, unit='B', unit_scale=True)
        
        # Write the content to the output file
        with open(output_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=1024):
                if chunk:
                    f.write(chunk)
                    progress_bar.update(len(chunk))
        
        progress_bar.close()
        return True
    else:
        print(f"Failed to download {file_name}. Status code: {response.status_code}")
        return False

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

def extract_archive_with_limit(archive_dir, output_dir, total_hours_limit=None):
    """
    Extract all speaker zip files from a directory to the specified directory,
    with an optional limit on total audio duration.
    
    Args:
        archive_dir: Directory containing the zip files
        output_dir: Directory to extract files to
        total_hours_limit: Maximum total hours of audio to include (None for no limit)
    
    Returns:
        True if extraction was successful, False otherwise
    """
    print(f"Extracting files from {archive_dir} to {output_dir}...")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Find all zip files
    zip_files = [f for f in os.listdir(archive_dir) if f.endswith('.zip') and not f == "suitcase_corpus.zip"]
    
    if not zip_files:
        print(f"No zip files found in {archive_dir}")
        return False
    
    # Create a temporary directory for extraction if we have a total hours limit
    if total_hours_limit is not None:
        temp_dir = tempfile.mkdtemp(prefix="l2arctic_temp_")
        print(f"Using temporary directory for extraction with hours limit: {temp_dir}")
    else:
        temp_dir = None
    
    try:
        # If no hour limit is set, extract each zip to the output directory
        if total_hours_limit is None:
            for zip_file in zip_files:
                zip_path = os.path.join(archive_dir, zip_file)
                speaker_id = os.path.splitext(zip_file)[0]
                speaker_dir = os.path.join(output_dir, speaker_id)
                
                # Create speaker directory
                os.makedirs(speaker_dir, exist_ok=True)
                
                print(f"Extracting {zip_path} to {speaker_dir}...")
                with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                    zip_ref.extractall(speaker_dir)
            
            # Copy non-zip files to the output directory
            for f in os.listdir(archive_dir):
                if f.endswith('.zip'):
                    continue
                    
                src_path = os.path.join(archive_dir, f)
                dst_path = os.path.join(output_dir, f)
                
                if os.path.isfile(src_path):
                    shutil.copy2(src_path, dst_path)
                    print(f"Copied {f} to {output_dir}")
            
            print(f"All files extracted without duration limits.")
            return True
        
        # If we have a total_hours_limit, extract all zips to temp dir first
        # and then copy files until the limit is reached
        for zip_file in zip_files:
            zip_path = os.path.join(archive_dir, zip_file)
            speaker_id = os.path.splitext(zip_file)[0]
            speaker_temp_dir = os.path.join(temp_dir, speaker_id)
            
            # Create speaker directory in temp
            os.makedirs(speaker_temp_dir, exist_ok=True)
            
            print(f"Extracting {zip_path} to temporary directory...")
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(speaker_temp_dir)
        
        # Copy non-zip files to the temp directory
        for f in os.listdir(archive_dir):
            if f.endswith('.zip'):
                continue
                
            src_path = os.path.join(archive_dir, f)
            dst_path = os.path.join(temp_dir, f)
            
            if os.path.isfile(src_path):
                shutil.copy2(src_path, dst_path)
        
        # Find all WAV files in the extracted archives
        wav_files = []
        for root, _, files in os.walk(temp_dir):
            for file in files:
                if file.lower().endswith('.wav'):
                    wav_path = os.path.join(root, file)
                    # Get file creation/modification time for sorting
                    file_time = os.path.getmtime(wav_path)
                    wav_files.append((wav_path, file_time))
        
        if not wav_files:
            print("No WAV files found in the extracted archives")
            return False
        
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
        
        # Create a mapping of files to copy with their relative paths
        relative_paths = {}
        speaker_dirs = {}
        
        # First determine which speakers to include
        for wav_path in files_to_keep:
            rel_path = os.path.relpath(wav_path, temp_dir)
            speaker_id = rel_path.split(os.sep)[0]
            speaker_dirs[speaker_id] = True
        
        # Copy all speaker directories with their structures but only selected audio files
        for speaker_id in speaker_dirs:
            # Create speaker directory in output
            speaker_output_dir = os.path.join(output_dir, speaker_id)
            speaker_temp_dir = os.path.join(temp_dir, speaker_id)
            
            # Copy directory structure
            for root, dirs, files in os.walk(speaker_temp_dir):
                rel_path = os.path.relpath(root, speaker_temp_dir)
                target_dir = os.path.join(speaker_output_dir, rel_path)
                os.makedirs(target_dir, exist_ok=True)
                
                # Copy non-WAV files (metadata, etc.)
                for file in files:
                    if not file.lower().endswith('.wav'):
                        src_file = os.path.join(root, file)
                        dst_file = os.path.join(target_dir, file)
                        shutil.copy2(src_file, dst_file)
        
        # Now copy only the selected WAV files
        for wav_path in files_to_keep:
            rel_path = os.path.relpath(wav_path, temp_dir)
            dst_path = os.path.join(output_dir, rel_path)
            
            # Create parent directories if needed
            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            
            # Copy the WAV file
            shutil.copy2(wav_path, dst_path)
            
            # Copy related files (transcripts, etc.)
            wav_dir = os.path.dirname(wav_path)
            wav_basename = os.path.splitext(os.path.basename(wav_path))[0]
            for ext in ['.txt', '.lab', '.TextGrid', '.json']:
                related_path = os.path.join(wav_dir, wav_basename + ext)
                if os.path.exists(related_path):
                    dst_related = os.path.join(os.path.dirname(dst_path), wav_basename + ext)
                    shutil.copy2(related_path, dst_related)
        
        # Copy non-speaker files to the output directory
        for item in os.listdir(temp_dir):
            src_path = os.path.join(temp_dir, item)
            
            # Skip speaker directories
            if os.path.isdir(src_path) and item in speaker_dirs:
                continue
                
            dst_path = os.path.join(output_dir, item)
            
            if os.path.isfile(src_path):
                shutil.copy2(src_path, dst_path)
        
        print(f"Final dataset size: {total_seconds/3600:.2f} hours ({len(files_to_keep)} files)")
        return True
        
    except Exception as e:
        print(f"Error during extraction with hour limit: {e}")
        return False
    finally:
        # Clean up temporary directory if it was created
        if temp_dir:
            try:
                shutil.rmtree(temp_dir)
                print(f"Cleaned up temporary directory: {temp_dir}")
            except Exception as e:
                print(f"Error cleaning up temporary directory: {e}")

def get_audio_durations_from_zip(zip_path, sample_size=10):
    """
    Estimate the total audio duration from a ZIP file by sampling a few audio files.
    
    Args:
        zip_path: Path to the ZIP file
        sample_size: Number of WAV files to sample
        
    Returns:
        (estimated_total_duration, num_wav_files) or (0, 0) if estimation fails
    """
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            # Get all WAV files in the ZIP
            wav_files = [f for f in zip_ref.namelist() if f.lower().endswith('.wav')]
            num_wav_files = len(wav_files)
            
            if num_wav_files == 0:
                return 0, 0
                
            # Use either all files or a sample
            if num_wav_files <= sample_size:
                files_to_sample = wav_files
            else:
                # Sample files evenly throughout the list
                step = num_wav_files // sample_size
                files_to_sample = wav_files[::step][:sample_size]
            
            # Create a temporary directory for extracting samples
            with tempfile.TemporaryDirectory() as temp_dir:
                # Extract sample files
                for wav_file in files_to_sample:
                    zip_ref.extract(wav_file, temp_dir)
                
                # Calculate average duration
                total_sample_duration = 0
                for wav_file in files_to_sample:
                    file_path = os.path.join(temp_dir, wav_file)
                    duration = get_audio_duration(file_path)
                    total_sample_duration += duration
                
                # Estimate total duration
                avg_duration = total_sample_duration / len(files_to_sample)
                estimated_total_duration = avg_duration * num_wav_files
                
                return estimated_total_duration, num_wav_files
    except Exception as e:
        print(f"Warning: Failed to estimate duration for {zip_path}: {e}")
        return 0, 0

def download_l2_arctic_dataset(output_dir="./l2_arctic_data", total_hours=None):
    """
    Download the L2-Arctic dataset from Hugging Face and extract it.
    
    Args:
        output_dir: Directory to save the extracted dataset
        total_hours: Maximum total hours of audio to include (None for no limit)
    """
    # Create download directory to store the zip files
    download_dir = os.path.join(output_dir, "_downloads")
    os.makedirs(download_dir, exist_ok=True)
    
    # Install required packages if needed
    install_requirements()
    
    # Speaker ZIP files to download
    speaker_zips = [
        "ABA.zip", "ASI.zip", "BWC.zip", "EBVS.zip", "ERMS.zip", 
        "HJK.zip", "HKK.zip", "HQTV.zip", "LXC.zip", "MBMPS.zip", 
        "NCC.zip", "NJS.zip", "PNV.zip", "RRBI.zip", "SKA.zip", 
        "SVBI.zip", "THV.zip", "TLV.zip", "TNI.zip", "TXHC.zip", 
        "YBAA.zip", "YDCK.zip", "YKWK.zip", "ZHAA.zip"
    ]
    
    # Sort speaker ZIPs to ensure consistent ordering across runs
    speaker_zips.sort()
    
    # Additional metadata files to download
    metadata_files = ["LICENSE", "PROMPTS", "README.md", "README.pdf"]
    
    # Download metadata files first, as they are small
    for meta_file in metadata_files:
        output_path = os.path.join(download_dir, meta_file)
        if os.path.exists(output_path):
            print(f"{meta_file} already exists, skipping download")
            continue
        
        download_from_huggingface(meta_file, output_path)
        # Metadata files are optional, so we don't track failures
    
    downloaded_files = []
    failed_files = []
    
    # If total_hours is set, download and check ZIPs one by one
    if total_hours is not None:
        print(f"Downloading L2-Arctic dataset with {total_hours} hour limit...")
        total_seconds_limit = total_hours * 3600
        estimated_total_seconds = 0
        
        # Add a safety margin to ensure we have enough data
        safety_margin = 0.2  # 20% extra data
        target_seconds = total_seconds_limit * (1 + safety_margin)
        
        for zip_file in speaker_zips:
            output_path = os.path.join(download_dir, zip_file)
            
            # Check if ZIP already exists
            if os.path.exists(output_path):
                print(f"{zip_file} already exists, checking duration...")
                estimated_duration, wav_count = get_audio_durations_from_zip(output_path)
                if estimated_duration > 0:
                    estimated_total_seconds += estimated_duration
                    downloaded_files.append(zip_file)
                    print(f"  Estimated {wav_count} files, {estimated_duration/3600:.2f} hours")
                else:
                    print(f"  Could not estimate duration, assuming ZIP is needed")
                    downloaded_files.append(zip_file)
            else:
                # Download the ZIP
                success = download_from_huggingface(zip_file, output_path)
                if success:
                    downloaded_files.append(zip_file)
                    estimated_duration, wav_count = get_audio_durations_from_zip(output_path)
                    estimated_total_seconds += estimated_duration
                    print(f"  Estimated {wav_count} files, {estimated_duration/3600:.2f} hours")
                else:
                    failed_files.append(zip_file)
            
            # Report progress
            print(f"Current estimated total: {estimated_total_seconds/3600:.2f} hours")
            
            # If we've reached our target with a safety margin, stop downloading
            if estimated_total_seconds >= target_seconds:
                print(f"Reached estimated target duration ({estimated_total_seconds/3600:.2f} hours), stopping download")
                break
    else:
        # Download all ZIP files if no hour limit
        print(f"Downloading full L2-Arctic dataset from Hugging Face repository...")
        
        for zip_file in speaker_zips:
            output_path = os.path.join(download_dir, zip_file)
            if os.path.exists(output_path):
                print(f"{zip_file} already exists, skipping download")
                downloaded_files.append(zip_file)
                continue
            
            success = download_from_huggingface(zip_file, output_path)
            if success:
                downloaded_files.append(zip_file)
            else:
                failed_files.append(zip_file)
    
    # Check if any speaker ZIPs were downloaded
    if not downloaded_files:
        print("Failed to download any speaker files. Aborting.")
        return
    
    if failed_files:
        print(f"Warning: Failed to download {len(failed_files)} files: {', '.join(failed_files)}")
    
    # Extract the dataset with optional hour limit
    extraction_successful = extract_archive_with_limit(download_dir, output_dir, total_hours)
    
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
        print("Please download the dataset manually from the HuggingFace repository:")
        print("https://huggingface.co/jims57/l2_arctic_dataset/tree/main/main")

def main():
    """Parse arguments and download the dataset."""
    parser = argparse.ArgumentParser(
        description="Download L2-Arctic dataset from Hugging Face"
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
