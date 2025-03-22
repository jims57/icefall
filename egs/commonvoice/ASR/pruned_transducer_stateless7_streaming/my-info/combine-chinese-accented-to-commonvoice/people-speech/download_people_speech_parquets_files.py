# Install required libraries
!pip install pandas pyarrow requests tqdm

import os
import pandas as pd
import requests
from tqdm import tqdm

# Create directory to store the downloaded files
!mkdir -p people_speech_data

# Base URL for the People's Speech dataset on HuggingFace
base_url = "https://huggingface.co/datasets/MLCommons/peoples_speech/resolve/main/clean/"

# File pattern based on the image shown
file_pattern = "test-{:05d}-of-00009.parquet"

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

def main():
    """
    Download the first 10 parquet files from the People's Speech clean directory
    """
    # In the image, we see files numbered 00000 through 00008, at least
    # Let's download the first 10 (00000-00009) to be safe
    num_files_to_download = 11
    
    successfully_downloaded = []
    
    for i in range(num_files_to_download):
        file_name = file_pattern.format(i)
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
                # Print the first row to verify content
                if not df.empty:
                    print(f"First row columns: {df.columns.tolist()}")
                    print()
            except Exception as e:
                print(f"Error loading parquet file {file_name}: {e}")
        else:
            print(f"Failed to download {file_name}")
    
    print("\nDownload Summary:")
    print(f"Successfully downloaded {len(successfully_downloaded)}/{num_files_to_download} files:")
    for file_name in successfully_downloaded:
        print(f"- {file_name}")

if __name__ == "__main__":
    main()
