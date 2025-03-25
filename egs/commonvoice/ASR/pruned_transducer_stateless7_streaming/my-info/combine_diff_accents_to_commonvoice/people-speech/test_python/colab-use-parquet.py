# Step 1: Install Required Libraries
!pip install pandas pyarrow

# Step 2: Import Necessary Libraries
import pandas as pd
import requests

# Step 3: Download the .parquet File
url = "https://huggingface.co/datasets/MLCommons/peoples_speech/resolve/main/microset/train-00000-of-00001.parquet?download=true"
file_name = "train-00000-of-00001.parquet"

# Use requests to download the file
response = requests.get(url)
if response.status_code == 200:
    with open(file_name, "wb") as f:
        f.write(response.content)
    print("File downloaded successfully!")
else:
    print(f"Failed to download file. Status code: {response.status_code}")

# Step 4: Load the .parquet File into a DataFrame
try:
    df = pd.read_parquet(file_name)

    # Step 5: Display the First Few Rows of the Data
    print("First few rows of the dataset:")
    print(df.head())

    # Step 6: Get Basic Information About the Dataset
    print("\nDataset Info:")
    print(df.info())

    # Print total number of audio samples
    print(f"\nTotal number of audio samples: {len(df)}")
    
    # Calculate total duration of all audio samples
    if 'duration_ms' in df.columns:
        total_duration_ms = df['duration_ms'].sum()
        total_duration_hours = total_duration_ms / (1000 * 60 * 60)  # Convert ms to hours
        print(f"\nTotal audio duration: {total_duration_ms:,} ms ({total_duration_hours:.2f} hours)")
        
        # Show duration statistics
        print(f"Minimum audio duration: {df['duration_ms'].min():,} ms ({df['duration_ms'].min()/1000:.2f} seconds)")
        print(f"Maximum audio duration: {df['duration_ms'].max():,} ms ({df['duration_ms'].max()/1000:.2f} seconds)")
        print(f"Average audio duration: {df['duration_ms'].mean():,.2f} ms ({df['duration_ms'].mean()/1000:.2f} seconds)")
    else:
        print("Duration information not available in the dataset")

    # Print all text transcriptions
    print("\nAll text transcriptions in the dataset:")
    for i, text in enumerate(df['text']):
        print(f"Sample {i+1}: {text}")

    # Step 7: List Column Names
    print("\nColumn Names:")
    print(df.columns)

    # Step 8: (Optional) Inspect Specific Columns
    if not df.empty:
        print("\nSample of the first column (if exists):")
        print(df.iloc[:, 0].head())  # Display the first column

    # Step 9: Save the first 3 audio samples and their texts
    try:
        if not df.empty:
            print("\nSaving the first 3 audio samples and their texts...")
            
            # Get number of samples to process (up to 3)
            num_samples = min(3, len(df))
            
            for i in range(num_samples):
                # Get the sample
                sample = df.iloc[i]
                
                # Extract audio data and text data
                audio_data = sample['audio']
                text_data = sample['text']
                
                # Print info about what we're saving
                print(f"\nSample {i+1} ID: {sample['id']}")
                print(f"Text content: {text_data}")
                print(f"Audio duration: {sample['duration_ms']} ms")
                
                # Check the type of audio data
                print(f"Audio data type: {type(audio_data)}")
                
                # Save the text to a file
                with open(f"sample{i+1}_text.txt", "w") as text_file:
                    text_file.write(text_data)
                    print(f"Text saved to sample{i+1}_text.txt")
                
                # Handle audio data based on its type
                if isinstance(audio_data, dict) and 'bytes' in audio_data:
                    # If audio is stored as bytes in a dictionary
                    with open(f"sample{i+1}_audio.wav", "wb") as audio_file:
                        audio_file.write(audio_data['bytes'])
                    print(f"Audio saved to sample{i+1}_audio.wav")
                elif isinstance(audio_data, bytes):
                    # If audio is stored directly as bytes
                    with open(f"sample{i+1}_audio.wav", "wb") as audio_file:
                        audio_file.write(audio_data)
                    print(f"Audio saved to sample{i+1}_audio.wav")
                elif isinstance(audio_data, str) and audio_data.startswith(('http://', 'https://')):
                    # If audio is a URL, download it
                    response = requests.get(audio_data)
                    if response.status_code == 200:
                        with open(f"sample{i+1}_audio.wav", "wb") as audio_file:
                            audio_file.write(response.content)
                        print(f"Audio downloaded and saved to sample{i+1}_audio.wav")
                    else:
                        print(f"Failed to download audio. Status code: {response.status_code}")
                else:
                    print(f"Unknown audio format. Please inspect the audio data structure: {audio_data}")

    except Exception as e:
        print(f"Error saving the first 3 samples: {e}")

except Exception as e:
    print(f"Error loading the .parquet file: {e}")