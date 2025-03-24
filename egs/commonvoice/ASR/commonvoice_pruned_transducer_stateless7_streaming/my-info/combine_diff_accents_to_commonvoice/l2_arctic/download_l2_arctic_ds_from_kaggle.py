#!/usr/bin/env python3
# Copyright (c) 2023, Johns Hopkins University, Soumi Maiti
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
To be run in Google Colab.
"""

import os
import zipfile
import tarfile
from pathlib import Path
from tqdm import tqdm

def download_from_gdrive(file_id, output_file):
    """
    Download a file from Google Drive using the file ID.
    
    Args:
        file_id: The Google Drive file ID
        output_file: Local path to save the file
    """
    # Install gdown if not available
    try:
        import gdown
    except ImportError:
        print("Installing gdown...")
        !pip install -q gdown
        import gdown
    
    print(f"Downloading file from Google Drive to {output_file}...")
    url = f"https://drive.google.com/uc?id={file_id}"
    gdown.download(url, output_file, quiet=False)

def extract_archive(archive_file, output_dir):
    """
    Extract an archive file (zip, tar.gz, etc.) to the specified directory.
    
    Args:
        archive_file: Path to the archive file
        output_dir: Directory to extract files to
    """
    print(f"Extracting {archive_file} to {output_dir}...")
    
    if archive_file.endswith('.zip'):
        with zipfile.ZipFile(archive_file, 'r') as zip_ref:
            zip_ref.extractall(output_dir)
    elif archive_file.endswith('.tar.gz') or archive_file.endswith('.tgz'):
        with tarfile.open(archive_file, 'r:gz') as tar_ref:
            tar_ref.extractall(output_dir)
    elif archive_file.endswith('.tar'):
        with tarfile.open(archive_file, 'r') as tar_ref:
            tar_ref.extractall(output_dir)
    else:
        print(f"Unsupported archive format: {archive_file}")
        return False
    
    return True

def download_l2_arctic_dataset(output_dir="./l2_arctic_data"):
    """
    Download the L2-Arctic dataset from Google Drive and extract it.
    
    Args:
        output_dir: Directory to save the extracted dataset
    """
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Google Drive file ID from the shared link
    file_id = "1ciCw_ttbw7a9r7d5DZzTJwoZq5rQB3TA"
    archive_file = "l2_arctic.zip"  # assuming it's a zip file
    
    # Install required packages
    !pip install -q tqdm
    
    # Download the dataset
    download_from_gdrive(file_id, archive_file)
    
    # Check if download was successful
    if not os.path.exists(archive_file):
        print("Download failed. File not found.")
        return
    
    # Extract the dataset
    extraction_successful = extract_archive(archive_file, output_dir)
    
    # Remove the archive file
    if os.path.exists(archive_file):
        os.remove(archive_file)
        print(f"Removed archive file: {archive_file}")
    
    if extraction_successful:
        print(f"\nDataset downloaded and extracted to {output_dir}")
        
        # List the contents of the dataset
        print("\nDataset contents:")
        file_count = 0
        for path in Path(output_dir).rglob("*"):
            if path.is_file() and path.suffix in ['.wav', '.txt', '.lab']:
                print(f"  {path.relative_to(output_dir)}")
                file_count += 1
                if file_count >= 20:  # Limit the number of files to display
                    print("  ... (more files not shown)")
                    break
    else:
        print("\nExtraction failed.")
        print("Please download the dataset manually from the Google Drive link:")
        print("https://drive.google.com/file/d/1ciCw_ttbw7a9r7d5DZzTJwoZq5rQB3TA/view?usp=sharing")
        
        # Instructions for manual download
        print("\nManual download instructions:")
        print("1. Open the link in your browser")
        print("2. Click the download button in the top right corner")
        print("3. Extract the downloaded file to your desired location")

if __name__ == "__main__":
    download_l2_arctic_dataset()
