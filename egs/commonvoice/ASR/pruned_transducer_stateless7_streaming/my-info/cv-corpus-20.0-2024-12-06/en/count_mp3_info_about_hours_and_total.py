#!/usr/bin/env python3

import os
import sys
import subprocess
import argparse

# Check and install required packages
required_packages = ['mutagen', 'tqdm']
for package in required_packages:
    try:
        __import__(package)
    except ImportError:
        print(f"Package '{package}' not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        print(f"Successfully installed {package}")

# Now import after ensuring packages are installed
from mutagen.mp3 import MP3
from tqdm import tqdm

def count_mp3_info(clips_dir):
    """
    Count the total number of MP3 files and their total duration in hours.
    
    Args:
        clips_dir: Directory containing MP3 files
    
    Returns:
        tuple: (total_mp3_count, total_hours)
    """
    if not os.path.exists(clips_dir):
        print(f"Error: Directory '{clips_dir}' does not exist.")
        return 0, 0
        
    mp3_files = []
    for root, _, files in os.walk(clips_dir):
        for file in files:
            if file.lower().endswith('.mp3'):
                mp3_files.append(os.path.join(root, file))
    
    total_seconds = 0
    print(f"Processing {len(mp3_files)} MP3 files...")
    
    for mp3_file in tqdm(mp3_files):
        try:
            audio = MP3(mp3_file)
            total_seconds += audio.info.length
        except Exception as e:
            print(f"Error processing {mp3_file}: {e}")
    
    total_hours = total_seconds / 3600
    
    return len(mp3_files), total_hours

def main():
    parser = argparse.ArgumentParser(
        description="Count MP3 files and total audio duration in the clips directory"
    )
    parser.add_argument(
        "--clips_dir", 
        type=str, 
        default="clips", 
        help="Directory containing MP3 files (default: clips)"
    )
    
    args = parser.parse_args()
    clips_dir = args.clips_dir
    
    if clips_dir.startswith("@"):
        clips_dir = clips_dir[1:]  # Remove @ prefix if present
    
    total_files, total_hours = count_mp3_info(clips_dir)
    
    print("\n" + "="*50)
    print(f"📊 MP3 Statistics for '{clips_dir}':")
    print(f"🔢 Total MP3 files:     {total_files:,}")
    print(f"⏱️ Total audio duration: {total_hours:.2f} hours")
    print(f"                       ({int(total_hours*60):.0f} minutes)")
    print(f"                       ({int(total_hours*3600):.0f} seconds)")
    print("="*50)

if __name__ == "__main__":
    main()
