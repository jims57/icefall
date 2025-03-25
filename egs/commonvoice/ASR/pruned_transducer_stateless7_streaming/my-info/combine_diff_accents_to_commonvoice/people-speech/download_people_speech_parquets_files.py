# Install required libraries
# !pip install pandas pyarrow requests tqdm argparse

import os
import pandas as pd
import requests
from tqdm import tqdm
import argparse

# # Create directory to store the downloaded files
# !mkdir -p people_speech_data

# Base URL for the People's Speech dataset on HuggingFace
base_url = "https://huggingface.co/datasets/MLCommons/peoples_speech/resolve/main/clean/"

def download_file(url, output_path):
    """
    Download a file from a URL with progress bar
    """
    response = requests.get(url, stream=True)
    if response.status_code != 200:
        print(f"Failed to download {url}. Status code: {response.status_code}")
        return False
    
    total_size = int(response.headers.get('content-length', 0))
    block_size = 1024  # 1 KB
    
    with open(output_path, 'wb') as f:
        with tqdm(total=total_size, unit='B', unit_scale=True, desc=os.path.basename(output_path)) as pbar:
            for data in response.iter_content(block_size):
                pbar.update(len(data))
                f.write(data)
    
    return True

def main(download_total=10):
    """
    Download parquet files from the People's Speech clean directory
    
    Args:
        download_total: Total number of parquet files to download
    """
    # List of all available files to download in order
    # First all test files, then train files
    all_files = [
        # Test files (9 total)
        *[f"test-{i:05d}-of-00009.parquet" for i in range(9)],
        # Train files (804 total, but we'll only list as many as needed)
        *[f"train-{i:05d}-of-00804.parquet" for i in range(100)]  # Listing first 100 for now
    ]
    
    # Limit the number of files to download
    files_to_download = all_files[:download_total]
    
    successfully_downloaded = []
    
    print(f"\nDownloading {len(files_to_download)} parquet files...")
    for file_name in files_to_download:
        file_url = base_url + file_name
        output_path = os.path.join("people_speech_data", file_name)
        
        print(f"Downloading {file_name}...")
        success = download_file(file_url, output_path)
        
        if success:
            successfully_downloaded.append(file_name)
            
            # Verify we can read the parquet file
            try:
                df = pd.read_parquet(output_path)
                print(f"Successfully loaded {file_name}, contains {len(df)} rows")
                # Print the first row columns to verify content
                if not df.empty:
                    print(f"First row columns: {df.columns.tolist()}")
                    print()
            except Exception as e:
                print(f"Error loading parquet file {file_name}: {e}")
        else:
            print(f"Failed to download {file_name}")
    
    # Final summary
    print("\nDownload Summary:")
    print(f"Total files successfully downloaded: {len(successfully_downloaded)}/{len(files_to_download)}")
    print("Downloaded files:")
    for file_name in successfully_downloaded:
        print(f"- {file_name}")

if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Download People\'s Speech parquet files')
    parser.add_argument('--download-total', type=int, default=10,
                       help='Total number of parquet files to download (default: 10)')
    args = parser.parse_args()
    
    # Call the main function with the parsed arguments
    main(download_total=args.download_total)
