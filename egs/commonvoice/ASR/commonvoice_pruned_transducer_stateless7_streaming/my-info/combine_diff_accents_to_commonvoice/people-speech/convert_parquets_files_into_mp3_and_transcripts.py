import os
import hashlib
import uuid
import random
import string
import pandas as pd
import io
import soundfile as sf
from pydub import AudioSegment
import multiprocessing
from functools import partial
import time
import requests

# Function to generate random client_id with the same length as example
def generate_client_id():
    # Generate a UUID and hash it with sha256 for length consistency
    random_string = str(uuid.uuid4()) + ''.join(random.choices(string.ascii_lowercase + string.digits, k=20))
    hashed = hashlib.sha256(random_string.encode()).hexdigest()
    # Ensure the same length as example (128 chars)
    while len(hashed) < 128:
        hashed += hashlib.sha256(hashed.encode()).hexdigest()
    return hashed[:128]

# Function to format sentence properly (lowercase with first letter capitalized)
def format_sentence(sentence):
    if not sentence:
        return ""
    return sentence.strip().capitalize()

# Function to check if sentence has enough words (minimum 10)
def has_enough_words(sentence, min_words=10):
    if not sentence:
        return False
    words = sentence.strip().split()
    return len(words) >= min_words

def process_row(row_data, clips_dir, parquet_file):
    idx, row = row_data
    try:
        # Extract audio data and transcript based on the structure in colab-use-parquet.py
        audio_data = row.get('audio', {}).get('array')
        sample_rate = row.get('audio', {}).get('sample_rate', 16000)
        transcript = row.get('text', '')
        
        # If audio is in a different format (as seen in colab-use-parquet.py)
        if audio_data is None and isinstance(row.get('audio'), dict):
            if 'array' in row['audio']:
                audio_data = row['audio']['array']
            elif 'bytes' in row['audio']:
                # Handle bytes format if present
                audio_bytes = row['audio']['bytes']
                # Convert bytes to numpy array
                with io.BytesIO(audio_bytes) as buffer:
                    audio_data, sample_rate = sf.read(buffer)
        
        if audio_data is None or not transcript:
            print(f"Skipping row {idx} in {parquet_file}: Missing audio data or transcript")
            return None
            
        # Check if the sentence has at least 10 words
        if not has_enough_words(transcript, min_words=10):
            print(f"Skipping row {idx} in {parquet_file}: Sentence has fewer than 10 words")
            return None
        
        # Generate a unique filename for the mp3
        file_id = hashlib.md5(f"{parquet_file}_{idx}_{transcript}".encode()).hexdigest()
        mp3_name = f"people_speech_{file_id}.mp3"
        mp3_path = os.path.join(clips_dir, mp3_name)
        
        # Convert audio data to WAV in memory, then to MP3
        with io.BytesIO() as wav_buffer:
            sf.write(wav_buffer, audio_data, sample_rate, format='WAV')
            wav_buffer.seek(0)
            audio = AudioSegment.from_wav(wav_buffer)
            
            # Convert to 32kHz mono
            audio = audio.set_frame_rate(32000).set_channels(1)
            audio.export(mp3_path, format="mp3")
        
        # Format sentence
        formatted_text = format_sentence(transcript)
        
        # Generate a random ID for sentence_id
        sentence_id = hashlib.sha256(formatted_text.encode()).hexdigest()
        
        # Generate client_id
        client_id = generate_client_id()
        
        print(f"Processed: {parquet_file} idx {idx} -> {mp3_name}")
        
        return {
            'client_id': client_id,
            'path': mp3_name,
            'sentence_id': sentence_id,
            'sentence': formatted_text
        }
    
    except Exception as e:
        print(f"Error processing row {idx} in {parquet_file}: {e}")
        return None

def process_parquet_file(parquet_file, parquet_dir, clips_dir):
    parquet_path = os.path.join(parquet_dir, parquet_file)
    print(f"Processing {parquet_file}...")
    
    try:
        # Check file size first
        file_size = os.path.getsize(parquet_path)
        if file_size < 100:
            print(f"Skipping {parquet_file}: File appears to be empty or too small ({file_size} bytes)")
            return []
        
        # Try multiple methods to read the parquet file
        df = None
        exceptions = []
        
        # Method 1: Standard pandas read_parquet
        try:
            df = pd.read_parquet(parquet_path)
        except Exception as e:
            exceptions.append(f"Method 1 (pandas): {str(e)}")
        
        # Method 2: PyArrow direct
        if df is None:
            try:
                import pyarrow.parquet as pq
                table = pq.read_table(parquet_path)
                df = table.to_pandas()
            except Exception as e:
                exceptions.append(f"Method 2 (pyarrow): {str(e)}")
        
        # Method 3: Try with fastparquet engine
        if df is None:
            try:
                df = pd.read_parquet(parquet_path, engine='fastparquet')
            except Exception as e:
                exceptions.append(f"Method 3 (fastparquet): {str(e)}")
        
        # Method 4: Try reading as a binary file and then as parquet
        if df is None:
            try:
                with open(parquet_path, 'rb') as f:
                    parquet_data = f.read()
                    
                # Try to read from the binary data
                import io
                buffer = io.BytesIO(parquet_data)
                df = pd.read_parquet(buffer)
            except Exception as e:
                exceptions.append(f"Method 4 (binary): {str(e)}")
        
        # Method 5: Try using the clean URL from download_people_speech_parquets_files.py
        if df is None and parquet_file.startswith(("test-", "train-")):
            try:
                import requests
                # Use the same URL structure as in download_people_speech_parquets_files.py
                base_url = "https://huggingface.co/datasets/MLCommons/peoples_speech/resolve/main/clean/"
                url = base_url + parquet_file
                
                print(f"Attempting to verify file integrity by checking URL: {url}")
                response = requests.head(url)
                if response.status_code == 200:
                    print(f"File exists on server. Local file may be corrupted. Consider re-downloading.")
                else:
                    print(f"File not found on server with status code: {response.status_code}")
                
                exceptions.append(f"Method 5 (URL check): File exists on server but local copy may be corrupted")
            except Exception as e:
                exceptions.append(f"Method 5 (URL check): {str(e)}")
        
        # If all methods failed
        if df is None:
            print(f"Failed to read {parquet_file} with all methods:")
            for exception in exceptions:
                print(f"  - {exception}")
            return []
        
        # Process rows in parallel
        with multiprocessing.Pool(processes=multiprocessing.cpu_count()) as pool:
            process_func = partial(process_row, clips_dir=clips_dir, parquet_file=parquet_file)
            results = pool.map(process_func, df.iterrows())
        
        # Filter out None results (failed processing)
        return [result for result in results if result is not None]
    
    except Exception as e:
        print(f"Error reading parquet file {parquet_file}: {e}")
        return []

# Create clips directory if it doesn't exist
clips_dir = "clips"
os.makedirs(clips_dir, exist_ok=True)

# Path to the parquet files
parquet_dir = "people_speech_data"

# Process all parquet files
start_time = time.time()
processed_files = []

# Get list of parquet files
parquet_files = [f for f in os.listdir(parquet_dir) if f.endswith('.parquet')]

# Process each parquet file
for parquet_file in parquet_files:
    file_results = process_parquet_file(parquet_file, parquet_dir, clips_dir)
    processed_files.extend(file_results)

# Append to custom_validated.tsv
tsv_file = "custom_validated.tsv"
write_header = not os.path.exists(tsv_file)

with open(tsv_file, 'a', encoding='utf-8') as f:
    if write_header:
        f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
    
    for file_info in processed_files:
        # Write the TSV line with the same format as the example
        f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")

end_time = time.time()
print(f"Added {len(processed_files)} entries to {tsv_file}")
print(f"Total processing time: {end_time - start_time:.2f} seconds")

# Calculate total size of MP3 files
total_size_bytes = 0
for mp3_file in os.listdir(clips_dir):
    if mp3_file.endswith('.mp3'):
        file_path = os.path.join(clips_dir, mp3_file)
        total_size_bytes += os.path.getsize(file_path)

# Convert bytes to GB
total_size_gb = total_size_bytes / (1024 * 1024 * 1024)

# Estimate total duration (32kHz mono MP3 files)
# Approximate calculation: ~32 kbps for MP3 at this quality
# So 32,000 bits per second = 4,000 bytes per second
estimated_duration_seconds = total_size_bytes / 4000
estimated_duration_hours = estimated_duration_seconds / 3600

print(f"Total MP3 size: {total_size_gb:.2f} GB")
print(f"Estimated audio duration: {estimated_duration_hours:.2f} hours") 