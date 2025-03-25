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
This script downloads the L2-Arctic dataset from the official sources or mirrors.
It ensures both audio (WAV) files and transcript files are properly downloaded.
"""

import os
import sys
import argparse
import zipfile
import tempfile
import shutil
import traceback
import requests
from tqdm import tqdm
import json
import librosa
import glob
import re

# Base URL for HuggingFace downloads
HF_BASE_URL = "https://huggingface.co/jims57/l2_arctic_dataset/resolve/main/main/"

# Alternative sources for transcripts
TRANSCRIPT_SOURCES = {
    "github": "https://raw.githubusercontent.com/ku-nlp/l2-arctic/master/transcriptions/{speaker}.txt",
    "arctic": "http://www.festvox.org/cmu_arctic/cmuarctic.data"
}

def download_file(url, local_path, desc=None):
    """
    Download a file from a URL to a local path with progress bar.
    
    Args:
        url: URL to download from
        local_path: Local path to save to
        desc: Description for progress bar
        
    Returns:
        True if download was successful, False otherwise
    """
    try:
        # Create directory if it doesn't exist
        os.makedirs(os.path.dirname(local_path), exist_ok=True)
        
        # Start download
        response = requests.get(url, stream=True)
        if response.status_code != 200:
            print(f"Failed to download {url}. Status code: {response.status_code}")
            return False
        
        # Get file size for progress bar
        total_size = int(response.headers.get('content-length', 0))
        
        # Download with progress bar
        with open(local_path, 'wb') as f:
            with tqdm(total=total_size, unit='B', unit_scale=True, desc=desc or os.path.basename(url)) as pbar:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        pbar.update(len(chunk))
        
        return True
    except Exception as e:
        print(f"Error downloading {url}: {e}")
        return False

def get_audio_duration(audio_path):
    """
    Get the duration of an audio file in seconds.
    
    Args:
        audio_path: Path to the audio file
        
    Returns:
        Duration in seconds
    """
    try:
        duration = librosa.get_duration(path=audio_path)
        return duration
    except Exception as e:
        print(f"Warning: Could not get duration for {audio_path}: {e}")
        return 0  # Return 0 for duration calculation failures

def download_cmu_arctic_transcripts(output_dir):
    """
    Download and parse the original CMU Arctic transcriptions.
    These are the base transcriptions used in L2-Arctic.
    
    Args:
        output_dir: Directory to save transcripts to
        
    Returns:
        Dictionary mapping utterance IDs to transcripts
    """
    try:
        transcript_file = os.path.join(output_dir, "_downloads", "cmuarctic.data")
        os.makedirs(os.path.dirname(transcript_file), exist_ok=True)
        
        # Download if not already downloaded
        if not os.path.exists(transcript_file):
            print("Downloading CMU Arctic transcriptions...")
            download_file(TRANSCRIPT_SOURCES["arctic"], transcript_file, "CMU Arctic transcriptions")
        
        # Parse the transcript file
        transcripts = {}
        with open(transcript_file, 'r', encoding='utf-8') as f:
            for line in f:
                parts = line.strip().split(' ', 2)
                if len(parts) >= 3:
                    # Extract utterance ID and text (removing quotes)
                    utterance_id = parts[1].strip('()')
                    text = parts[2].strip('"')
                    transcripts[utterance_id] = text
        
        print(f"Loaded {len(transcripts)} CMU Arctic transcriptions")
        return transcripts
    except Exception as e:
        print(f"Error downloading CMU Arctic transcripts: {e}")
        return {}

def create_transcript_files(transcripts, speaker_dir):
    """
    Create individual transcript files for each WAV file.
    
    Args:
        transcripts: Dictionary mapping utterance IDs to transcripts
        speaker_dir: Directory containing speaker data
        
    Returns:
        Number of transcript files created
    """
    try:
        # Create transcript directory if it doesn't exist
        transcript_dir = os.path.join(speaker_dir, "txt")
        os.makedirs(transcript_dir, exist_ok=True)
        
        # Find all WAV files
        wav_dir = os.path.join(speaker_dir, "wav")
        if not os.path.exists(wav_dir):
            print(f"Warning: WAV directory not found for {os.path.basename(speaker_dir)}")
            return 0
        
        wav_files = glob.glob(os.path.join(wav_dir, "*.wav"))
        count = 0
        
        # Create transcript files
        for wav_file in wav_files:
            basename = os.path.splitext(os.path.basename(wav_file))[0]
            # Extract utterance ID (e.g., "arctic_a0001" from "speaker_arctic_a0001.wav")
            match = re.search(r'(arctic_[a-z][0-9]+)', basename)
            utterance_id = match.group(1) if match else basename
            
            if utterance_id in transcripts:
                # Create transcript file
                txt_file = os.path.join(transcript_dir, f"{basename}.txt")
                with open(txt_file, 'w', encoding='utf-8') as f:
                    f.write(transcripts[utterance_id])
                count += 1
        
        print(f"Created {count} transcript files for {os.path.basename(speaker_dir)}")
        return count
    except Exception as e:
        print(f"Error creating transcript files: {e}")
        return 0

def extract_archive_with_limit(archive_dir, output_dir, total_hours=None):
    """
    Extract all archives from a directory with an optional limit on total audio duration.
    
    Args:
        archive_dir: Directory containing all the ZIP archives
        output_dir: Directory to extract the archives to
        total_hours: Maximum total hours of audio to include (None for no limit)
        
    Returns:
        True if extraction was successful, False otherwise
    """
    try:
        # Create output directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)
        
        # Create a temporary directory for extraction
        temp_dir = None
        if total_hours is not None:
            temp_dir = tempfile.mkdtemp(prefix="l2arctic_temp_")
            print(f"Created temporary directory for extraction: {temp_dir}")
        
        # Get all ZIP files in the archive directory
        zip_files = [f for f in os.listdir(archive_dir) if f.lower().endswith('.zip')]
        zip_files.sort()  # Ensure consistent order
        
        # First, copy non-ZIP files directly to output directory
        for file in os.listdir(archive_dir):
            if not file.lower().endswith('.zip'):
                src_path = os.path.join(archive_dir, file)
                dst_path = os.path.join(output_dir, file)
                if os.path.isfile(src_path):
                    shutil.copy2(src_path, dst_path)
                    print(f"Copied metadata file: {file}")
        
        # Download CMU Arctic transcripts (for all speakers)
        transcripts = download_cmu_arctic_transcripts(output_dir)
        
        # Process each ZIP file
        for zip_file in zip_files:
            # Skip 'suitcase_corpus.zip' as it's not part of the speaker files
            if zip_file.lower() == 'suitcase_corpus.zip':
                continue
                
            zip_path = os.path.join(archive_dir, zip_file)
            speaker_id = os.path.splitext(zip_file)[0]  # Get speaker ID from filename (e.g., "ABA" from "ABA.zip")
            
            # Determine where to extract
            target_dir = output_dir if total_hours is None else temp_dir
            speaker_dir = os.path.join(target_dir, speaker_id)
            os.makedirs(speaker_dir, exist_ok=True)
            
            print(f"Extracting {zip_file}...")
            
            # Extract to the speaker directory
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                # List all files in the ZIP
                file_list = zip_ref.namelist()
                if not file_list:
                    continue
                    
                # Check for potential directory structures
                speaker_prefix = f"{speaker_id}/"
                has_speaker_dir = any(item.startswith(speaker_prefix) for item in file_list)
                
                # Extract all files
                if has_speaker_dir:
                    # The ZIP has a top-level directory matching the speaker name
                    for item in file_list:
                        if item.startswith(speaker_prefix):
                            # Remove the speaker prefix from the path
                            target_path = os.path.join(speaker_dir, item[len(speaker_prefix):])
                            if item.endswith('/'):
                                # Create directory
                                os.makedirs(target_path, exist_ok=True)
                            else:
                                # Extract file
                                try:
                                    # Create parent directory if it doesn't exist
                                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                                    # Extract the file content
                                    with open(target_path, 'wb') as f:
                                        f.write(zip_ref.read(item))
                                except Exception as e:
                                    print(f"Warning: Failed to extract {item}: {e}")
                else:
                    # The ZIP doesn't have a top-level speaker directory
                    for item in file_list:
                        target_path = os.path.join(speaker_dir, item)
                        if item.endswith('/'):
                            # Create directory
                            os.makedirs(target_path, exist_ok=True)
                        else:
                            # Extract file
                            try:
                                # Create parent directory if it doesn't exist
                                os.makedirs(os.path.dirname(target_path), exist_ok=True)
                                # Extract the file content
                                with open(target_path, 'wb') as f:
                                    f.write(zip_ref.read(item))
                            except Exception as e:
                                print(f"Warning: Failed to extract {item}: {e}")
            
            # Create transcript files if needed
            wav_dir = os.path.join(speaker_dir, "wav")
            txt_dir = os.path.join(speaker_dir, "txt")
            
            if os.path.exists(wav_dir) and not os.path.exists(txt_dir) and transcripts:
                create_transcript_files(transcripts, speaker_dir)
        
        # If we're using a total_hours limit, process the extracted files
        if total_hours is not None and temp_dir:
            success = process_with_hour_limit(temp_dir, output_dir, total_hours)
            
            # Also create transcript files for the speakers in the output directory
            # if they're missing after the hour-limited processing
            for speaker_dir in [d for d in os.listdir(output_dir) if os.path.isdir(os.path.join(output_dir, d))]:
                full_speaker_dir = os.path.join(output_dir, speaker_dir)
                wav_dir = os.path.join(full_speaker_dir, "wav")
                txt_dir = os.path.join(full_speaker_dir, "txt")
                
                if os.path.exists(wav_dir) and not os.path.exists(txt_dir) and transcripts:
                    create_transcript_files(transcripts, full_speaker_dir)
            
            return success
        
        return True
    except Exception as e:
        print(f"Error during extraction: {e}")
        traceback.print_exc()
        return False

def process_with_hour_limit(temp_dir, output_dir, total_hours):
    """
    Process files in the temporary directory and copy only enough to meet the hour limit.
    
    Args:
        temp_dir: Temporary directory containing all extracted files
        output_dir: Output directory to copy files to
        total_hours: Maximum total hours of audio to include
        
    Returns:
        True if processing was successful, False otherwise
    """
    try:
        # Convert hours to seconds for comparison
        total_seconds = total_hours * 3600
        
        # Find all WAV files in the temp directory
        wav_files = []
        for root, _, files in os.walk(temp_dir):
            for file in files:
                if file.lower().endswith('.wav'):
                    wav_path = os.path.join(root, file)
                    duration = get_audio_duration(wav_path)
                    relative_path = os.path.relpath(wav_path, temp_dir)
                    speaker = relative_path.split(os.path.sep)[0]
                    wav_files.append((wav_path, relative_path, duration, speaker))
        
        # Sort by duration (optional, could be random or by path instead)
        wav_files.sort(key=lambda x: x[2])  # Sort by duration
        
        # Group files by speaker
        files_by_speaker = {}
        for wav_path, relative_path, duration, speaker in wav_files:
            if speaker not in files_by_speaker:
                files_by_speaker[speaker] = []
            files_by_speaker[speaker].append((wav_path, relative_path, duration))
        
        # Select files up to the hour limit, ensuring we have files from all speakers
        selected_files = []
        current_total_duration = 0
        
        # First, select some files from each speaker to ensure representation
        files_per_speaker = 50  # Adjust as needed
        for speaker, files in files_by_speaker.items():
            for wav_path, relative_path, duration in files[:files_per_speaker]:
                if current_total_duration >= total_seconds:
                    break
                selected_files.append((wav_path, relative_path))
                current_total_duration += duration
        
        # Then add more files if we haven't reached the limit
        if current_total_duration < total_seconds:
            remaining_files = []
            for files in files_by_speaker.values():
                remaining_files.extend(files[files_per_speaker:])
            
            # Sort by duration
            remaining_files.sort(key=lambda x: x[2])
            
            # Add files up to the limit
            for wav_path, relative_path, duration in remaining_files:
                if current_total_duration >= total_seconds:
                    break
                selected_files.append((wav_path, relative_path))
                current_total_duration += duration
        
        print(f"Selected {len(selected_files)} files with total duration of {current_total_duration/3600:.2f} hours")
        
        # Copy selected files to output directory, preserving directory structure
        for wav_path, relative_path in selected_files:
            # Determine output path
            output_path = os.path.join(output_dir, relative_path)
            
            # Create output directory if it doesn't exist
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            # Copy the file
            shutil.copy2(wav_path, output_path)
        
        # Create list of selected speakers
        selected_speakers = set()
        for _, relative_path in selected_files:
            speaker = relative_path.split(os.path.sep)[0]
            selected_speakers.add(speaker)
        
        # Copy related files for the selected speakers
        for speaker in selected_speakers:
            speaker_temp_dir = os.path.join(temp_dir, speaker)
            speaker_output_dir = os.path.join(output_dir, speaker)
            
            # Create speaker directory
            os.makedirs(speaker_output_dir, exist_ok=True)
            
            # Copy non-WAV directories (e.g., txt, transcript, etc.)
            for item in os.listdir(speaker_temp_dir):
                source_path = os.path.join(speaker_temp_dir, item)
                if os.path.isdir(source_path) and item.lower() != "wav":
                    # Copy the directory
                    dest_path = os.path.join(speaker_output_dir, item)
                    if not os.path.exists(dest_path):
                        shutil.copytree(source_path, dest_path)
        
        print(f"Successfully processed and copied files to {output_dir}")
        return True
        
    except Exception as e:
        print(f"Error processing with hour limit: {e}")
        traceback.print_exc()
        
        # In case of failure, try copying all files from temp to output
        print("Trying to copy all files from temp directory as fallback...")
        try:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    src_path = os.path.join(root, file)
                    rel_path = os.path.relpath(src_path, temp_dir)
                    dst_path = os.path.join(output_dir, rel_path)
                    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
                    shutil.copy2(src_path, dst_path)
            return True
        except Exception as copy_error:
            print(f"Fallback copying also failed: {copy_error}")
            return False

def download_l2_arctic_dataset(output_dir, total_hours=None, use_cn_only=False):
    """
    Download the L2-Arctic dataset from HuggingFace.
    
    Args:
        output_dir: Directory to save the dataset
        total_hours: Maximum total hours of audio to include (None for no limit)
        use_cn_only: Only download Chinese-accented speakers if True
    """
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Create downloads directory
    downloads_dir = os.path.join(output_dir, "_downloads")
    os.makedirs(downloads_dir, exist_ok=True)
    
    # Define Chinese-accented speakers
    chinese_speakers = ["BWC", "LXC", "NCC", "TXHC"]
    
    # List of all speaker ZIPs
    all_speakers = [
        "ABA", "ASI", "BWC", "EBVS", "ERMS", "HQTV", "HKK", "MBMPS", 
        "NJS", "PNV", "SVBI", "THV", "TNI", "TXHC", "YDCK", "YKWK",
        "ZHAA", "LXC", "NCC", "SVBI", "YBAA"
    ]
    
    # Filter and prioritize speakers based on Chinese-only flag
    if use_cn_only:
        print("Chinese-accented speakers only mode activated")
        # Only use Chinese speakers
        speakers = [s for s in all_speakers if s in chinese_speakers]
        print(f"Will download only these Chinese-accented speakers: {speakers}")
    else:
        # If we're not in Chinese-only mode but still have a total_hours limit,
        # prioritize Chinese speakers at the beginning of the list
        if total_hours is not None:
            # Move Chinese speakers to the front of the list
            non_chinese = [s for s in all_speakers if s not in chinese_speakers]
            speakers = chinese_speakers + non_chinese
            print(f"Prioritizing Chinese-accented speakers: {chinese_speakers}")
        else:
            speakers = all_speakers
    
    if total_hours is not None:
        print(f"Downloading L2-Arctic dataset with {total_hours} hour limit...")
        
        # Initialize tracking
        downloaded_speakers = []
        estimated_total_hours = 0
        
        # Download speakers and track estimated hours until we reach the limit
        for speaker in speakers:
            # Check if we've reached the limit
            if estimated_total_hours >= total_hours:
                print(f"Reached estimated target duration ({estimated_total_hours:.2f} hours), stopping download")
                break
            
            # Download this speaker
            zip_file = f"{speaker}.zip"
            local_path = os.path.join(downloads_dir, zip_file)
            
            if download_file(f"{HF_BASE_URL}{zip_file}", local_path, f"{zip_file}"):
                downloaded_speakers.append(speaker)
                
                # Estimate hours based on file count (rough approximation)
                try:
                    with zipfile.ZipFile(local_path, 'r') as zip_ref:
                        file_count = len([f for f in zip_ref.namelist() if f.lower().endswith('.wav')])
                        # Rough estimate: 3-4 seconds per file
                        estimated_hours = file_count * 3.5 / 3600
                        print(f"  Estimated {file_count} files, {estimated_hours:.2f} hours")
                        estimated_total_hours += estimated_hours
                        print(f"Current estimated total: {estimated_total_hours:.2f} hours")
                except Exception as e:
                    print(f"  Warning: Couldn't estimate duration for {zip_file}: {e}")
                    # Use a fallback estimate of 1 hour per speaker
                    estimated_total_hours += 1
                    print(f"  Using fallback estimate. Current total: {estimated_total_hours:.2f} hours")
    else:
        print(f"Downloading L2-Arctic dataset...")
        
        # Download all filtered speakers
        for speaker in speakers:
            zip_file = f"{speaker}.zip"
            local_path = os.path.join(downloads_dir, zip_file)
            download_file(f"{HF_BASE_URL}{zip_file}", local_path, f"{zip_file}")
    
    # Extract the downloaded archives
    if extract_archive_with_limit(downloads_dir, output_dir, total_hours):
        print(f"L2-Arctic dataset downloaded and extracted to {output_dir}")
    else:
        print("Extraction failed.")
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
    parser.add_argument(
        "--use-cn-only",
        action="store_true",
        help="Only download Chinese-accented speakers"
    )
    args = parser.parse_args()
    
    download_l2_arctic_dataset(args.output_dir, args.total_hours, args.use_cn_only)

if __name__ == "__main__":
    main()
