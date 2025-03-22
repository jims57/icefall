import os
import hashlib
import uuid
import random
import string
import pandas as pd
import io
import soundfile as sf
from pydub import AudioSegment

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

# Create clips directory if it doesn't exist
clips_dir = "clips"
os.makedirs(clips_dir, exist_ok=True)

# Path to the parquet files
parquet_dir = "people_speech_data"

# Process all parquet files
processed_files = []
for parquet_file in os.listdir(parquet_dir):
    if parquet_file.endswith('.parquet'):
        parquet_path = os.path.join(parquet_dir, parquet_file)
        print(f"Processing {parquet_file}...")
        
        try:
            # Use pandas to read the parquet file directly instead of pyarrow
            df = pd.read_parquet(parquet_path)
            
            # Process each row in the dataframe
            for idx, row in df.iterrows():
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
                            # Convert bytes to numpy array (you might need additional processing)
                            with io.BytesIO(audio_bytes) as buffer:
                                audio_data, sample_rate = sf.read(buffer)
                    
                    if audio_data is None or not transcript:
                        print(f"Skipping row {idx} in {parquet_file}: Missing audio data or transcript")
                        continue
                    
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
                    
                    processed_files.append({
                        'client_id': client_id,
                        'path': mp3_name,
                        'sentence_id': sentence_id,
                        'sentence': formatted_text
                    })
                    
                    print(f"Processed: {parquet_file} idx {idx} -> {mp3_name}")
                
                except Exception as e:
                    print(f"Error processing row {idx} in {parquet_file}: {e}")
        
        except Exception as e:
            print(f"Error reading parquet file {parquet_file}: {e}")
            continue

# Append to validated.tsv
tsv_file = "validated.tsv"
write_header = not os.path.exists(tsv_file)

with open(tsv_file, 'a', encoding='utf-8') as f:
    if write_header:
        f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
    
    for file_info in processed_files:
        # Write the TSV line with the same format as the example
        f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")

print(f"Added {len(processed_files)} entries to {tsv_file}") 