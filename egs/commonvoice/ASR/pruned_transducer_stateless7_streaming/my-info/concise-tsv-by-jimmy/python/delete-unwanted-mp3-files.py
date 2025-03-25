import os
import sys

def main():
    # Path to the mp3-name.txt file
    mp3_names_file = "mp3-name.txt"
    # Path to the clips directory (one directory level up)
    clips_dir = "../clips"
    
    # Check if the mp3 names file exists
    if not os.path.isfile(mp3_names_file):
        print(f"Error: File '{mp3_names_file}' not found.")
        sys.exit(1)
    
    # Check if the clips directory exists
    if not os.path.isdir(clips_dir):
        print(f"Error: Directory '{clips_dir}' not found.")
        sys.exit(1)
    
    # Read the list of allowed mp3 files from mp3-name.txt
    allowed_mp3_files = set()
    with open(mp3_names_file, "r") as f:
        for line in f:
            filename = line.strip()
            if filename:  # Skip empty lines
                allowed_mp3_files.add(filename)
    
    print(f"Found {len(allowed_mp3_files)} allowed mp3 files in {mp3_names_file}")
    
    # Get all mp3 files in the clips directory and delete unwanted ones
    deleted_count = 0
    for filename in os.listdir(clips_dir):
        if filename.endswith(".mp3"):
            if filename not in allowed_mp3_files:
                # This mp3 file is not in the allowed list, delete it
                file_path = os.path.join(clips_dir, filename)
                try:
                    os.remove(file_path)
                    deleted_count += 1
                    print(f"Deleted: {filename}")
                except Exception as e:
                    print(f"Error deleting {filename}: {e}")
    
    print(f"\nSummary: Deleted {deleted_count} unwanted mp3 files from {clips_dir}")

if __name__ == "__main__":
    main()
