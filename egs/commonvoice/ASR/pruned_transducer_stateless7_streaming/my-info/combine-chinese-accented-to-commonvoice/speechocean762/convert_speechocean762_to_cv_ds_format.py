# 将speechocean762的格式转换为commonvoice的格式

import os
import hashlib
import uuid
import random
import string
from pydub import AudioSegment
import shutil

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
    return sentence.lower().capitalize()

# Create clips directory if it doesn't exist
clips_dir = "clips"
os.makedirs(clips_dir, exist_ok=True)

# Find all WAV files in WAVE folder
wave_dir = "WAVE"
text_files = {"train/text", "test/text"}
all_transcripts = {}

# First, read all transcripts from text files
for text_file in text_files:
    if os.path.exists(text_file):
        with open(text_file, 'r') as f:
            for line in f:
                parts = line.strip().split(maxsplit=1)
                if len(parts) == 2:
                    uttid, text = parts
                    all_transcripts[uttid] = text

# Process all WAV files and convert to MP3
processed_files = []
for speaker_dir in os.listdir(wave_dir):
    speaker_path = os.path.join(wave_dir, speaker_dir)
    if os.path.isdir(speaker_path):
        for wav_file in os.listdir(speaker_path):
            if wav_file.endswith('.WAV') or wav_file.endswith('.wav'):
                wav_path = os.path.join(speaker_path, wav_file)
                mp3_name = wav_file.replace('.WAV', '.mp3').replace('.wav', '.mp3')
                mp3_path = os.path.join(clips_dir, mp3_name)
                
                # Convert WAV to MP3
                audio = AudioSegment.from_wav(wav_path)
                audio = audio.set_frame_rate(32000).set_channels(1)
                audio.export(mp3_path, format="mp3")
                
                # Get the utterance ID
                uttid = os.path.splitext(wav_file)[0]
                
                # Get transcript
                text = all_transcripts.get(uttid, "")
                
                # Format sentence
                formatted_text = format_sentence(text)
                
                # Generate a random ID for sentence_id
                sentence_id = hashlib.sha256(formatted_text.encode()).hexdigest()
                
                # Generate client_id
                client_id = generate_client_id()
                
                processed_files.append({
                    'client_id': client_id,
                    'path': mp3_name,
                    'sentence_id': sentence_id,
                    'sentence': formatted_text,
                    'uttid': uttid
                })
                
                print(f"Processed: {wav_file} -> {mp3_name}")

# Append to custom_validated.tsv
tsv_file = "custom_validated.tsv"
write_header = not os.path.exists(tsv_file)

with open(tsv_file, 'a', encoding='utf-8') as f:
    if write_header:
        f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
    
    for file_info in processed_files:
        # Write the TSV line with the same format as the example
        f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")

print(f"Added {len(processed_files)} entries to {tsv_file}")

