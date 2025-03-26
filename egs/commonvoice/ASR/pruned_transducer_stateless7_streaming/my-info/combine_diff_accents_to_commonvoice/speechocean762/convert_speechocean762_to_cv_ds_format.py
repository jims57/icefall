# 将speechocean762的格式转换为commonvoice的格式

import os
import hashlib
import uuid
import random
import string
import argparse
import sys
from pydub import AudioSegment
import shutil

def parse_arguments():
    parser = argparse.ArgumentParser(description="Convert SpeechOcean762 format to CommonVoice dataset format")
    parser.add_argument("--skip_audio_conversion", action="store_true", help="Skip audio conversion if MP3 files are already created")
    parser.add_argument("--output_tsv", type=str, default="custom_validated.tsv", help="Output TSV filename")
    parser.add_argument("--output_dir", type=str, default="clips", help="Directory where MP3 files are located/will be saved")
    parser.add_argument("--sync_files", action="store_true", help="Ensure TSV entries match MP3 files in output directory")
    parser.add_argument("--rebuild_tsv", action="store_true", help="Completely rebuild TSV file from MP3 files in output directory")
    return parser.parse_args()

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

def cleanup_mp3_filenames(clips_dir):
    """Rename any MP3 files with .WAV.mp3 or .wav.mp3 to a more unique format with speaker ID"""
    renamed_count = 0
    wave_dir = "WAVE"
    
    for filename in os.listdir(clips_dir):
        if filename.endswith('.WAV.mp3') or filename.endswith('.wav.mp3') or filename.endswith('_WAV.mp3') or filename.endswith('_wav.mp3'):
            # Extract base name without extension
            if filename.endswith('.WAV.mp3'):
                base_name = filename[:-8]  # Remove .WAV.mp3
            elif filename.endswith('.wav.mp3'):
                base_name = filename[:-8]  # Remove .wav.mp3
            elif filename.endswith('_WAV.mp3'):
                base_name = filename[:-8]  # Remove _WAV.mp3
            elif filename.endswith('_wav.mp3'):
                base_name = filename[:-8]  # Remove _wav.mp3
            else:
                base_name = os.path.splitext(filename)[0]
            
            # Try to find the original WAV file to determine the speaker ID
            speaker_name = None
            if os.path.exists(wave_dir):
                for speaker_dir in os.listdir(wave_dir):
                    speaker_path = os.path.join(wave_dir, speaker_dir)
                    if os.path.isdir(speaker_path):
                        wav_file = f"{base_name}.WAV"
                        wav_file_alt = f"{base_name}.wav"
                        if os.path.exists(os.path.join(speaker_path, wav_file)) or os.path.exists(os.path.join(speaker_path, wav_file_alt)):
                            # Check if speaker_dir already has SPEAKER prefix
                            if speaker_dir.startswith("SPEAKER"):
                                speaker_name = speaker_dir
                            else:
                                speaker_name = f"SPEAKER{speaker_dir}"
                            break
            
            # Default speaker name if we can't determine it
            if not speaker_name:
                speaker_name = "SPEAKER0000"
                print(f"Warning: Could not determine speaker ID for {filename}, using {speaker_name}")
            
            # Create a new name with SPEAKER prefix
            new_name = f"{speaker_name}_{base_name}.mp3"
                
            old_path = os.path.join(clips_dir, filename)
            new_path = os.path.join(clips_dir, new_name)
            
            # Only rename if the new filename doesn't already exist
            if not os.path.exists(new_path):
                os.rename(old_path, new_path)
                renamed_count += 1
                print(f"Renamed: {filename} -> {new_name}")
            else:
                print(f"Warning: Cannot rename {filename} to {new_name} as it already exists")
    
    if renamed_count > 0:
        print(f"Renamed {renamed_count} MP3 files to use speaker ID naming convention")
    
    return renamed_count

def main():
    args = parse_arguments()
    
    # Use the specified output directory
    clips_dir = args.output_dir
    os.makedirs(clips_dir, exist_ok=True)
    
    # Clean up any existing MP3 files with bad naming convention
    cleanup_mp3_filenames(clips_dir)
    
    # Use the specified output TSV file
    tsv_file = args.output_tsv
    
    # If rebuild_tsv is specified, completely rebuild the TSV file from MP3 files
    if args.rebuild_tsv:
        print(f"Rebuilding TSV file from MP3 files in {clips_dir}...")
        rebuild_tsv_from_mp3_files(clips_dir, tsv_file)
        return
    
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
    
    # Track existing MP3 files in the output directory
    existing_mp3_files = set()
    if os.path.exists(clips_dir):
        for file in os.listdir(clips_dir):
            if file.endswith('.mp3'):
                existing_mp3_files.add(file)
    
    # Get all WAV files
    wav_files = []
    if os.path.exists(wave_dir):
        for speaker_dir in os.listdir(wave_dir):
            speaker_path = os.path.join(wave_dir, speaker_dir)
            if os.path.isdir(speaker_path):
                for wav_file in os.listdir(speaker_path):
                    if wav_file.endswith('.WAV') or wav_file.endswith('.wav'):
                        wav_path = os.path.join(speaker_path, wav_file)
                        wav_files.append((wav_path, wav_file))
    
    print(f"Found {len(wav_files)} WAV files to process")
    print(f"Found {len(existing_mp3_files)} existing MP3 files in output directory")
    
    # Process each WAV file
    for wav_path, wav_file in wav_files:
        # Extract the base name without extension
        if wav_file.upper().endswith('.WAV'):
            base_name = wav_file[:-4]  # Remove .WAV extension
        else:
            base_name = os.path.splitext(wav_file)[0]  # General case
            
        # Extract speaker ID from the path
        speaker_dir = os.path.basename(os.path.dirname(wav_path))
        speaker_name = f"SPEAKER{speaker_dir}"
            
        # Create a more unique MP3 filename with speaker ID
        mp3_name = f"{speaker_name}_{base_name}.mp3"
            
        mp3_path = os.path.join(clips_dir, mp3_name)
        
        # Check if MP3 already exists
        mp3_exists = os.path.exists(mp3_path)
        
        # Convert WAV to MP3 if not skipping audio conversion and MP3 doesn't exist
        if not args.skip_audio_conversion and not mp3_exists:
            try:
                audio = AudioSegment.from_wav(wav_path)
                audio = audio.set_frame_rate(32000).set_channels(1)
                audio.export(mp3_path, format="mp3")
                mp3_exists = True
                print(f"Processed: {wav_file} -> {mp3_name}")
            except Exception as e:
                print(f"Error converting {wav_file}: {e}", file=sys.stderr)
                continue
        
        # Only add to processed_files if MP3 exists
        if mp3_exists:
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
                'path': mp3_name,  # Just filename, not full path
                'sentence_id': sentence_id,
                'sentence': formatted_text,
                'uttid': uttid
            })
            
            # Remove from existing_mp3_files set as we've processed it
            if mp3_name in existing_mp3_files:
                existing_mp3_files.remove(mp3_name)
    
    # If sync_files is enabled, add entries for any MP3 files in the output directory
    # that weren't processed from WAV files
    if args.sync_files and existing_mp3_files:
        print(f"Found {len(existing_mp3_files)} additional MP3 files in output directory")
        for mp3_name in existing_mp3_files:
            # Extract utterance ID from MP3 filename
            if mp3_name.endswith('_WAV.mp3'):
                uttid = mp3_name[:-8]  # Remove _WAV.mp3
            elif mp3_name.endswith('_wav.mp3'):
                uttid = mp3_name[:-8]  # Remove _wav.mp3
            elif '_' in mp3_name and mp3_name.startswith('SPEAKER'):
                # Handle new format: SPEAKER0001_004570283.mp3
                uttid = mp3_name.split('_', 1)[1][:-4]  # Get part after SPEAKER prefix and before .mp3
            else:
                uttid = os.path.splitext(mp3_name)[0]
            
            # Get transcript if available
            text = all_transcripts.get(uttid, "")
            
            # Format sentence
            formatted_text = format_sentence(text)
            
            # Generate IDs
            sentence_id = hashlib.sha256(formatted_text.encode()).hexdigest()
            client_id = generate_client_id()
            
            processed_files.append({
                'client_id': client_id,
                'path': mp3_name,
                'sentence_id': sentence_id,
                'sentence': formatted_text,
                'uttid': uttid
            })
        print(f"Added {len(existing_mp3_files)} entries for existing MP3 files")
    
    # Check if we have processed files
    if not processed_files:
        print("No files were processed. Check if WAV files exist or if --skip_audio_conversion is set correctly.")
        return
    
    # Append to TSV file
    write_header = not os.path.exists(tsv_file)
    
    with open(tsv_file, 'a', encoding='utf-8') as f:
        if write_header:
            f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
        
        for file_info in processed_files:
            # Write the TSV line with the same format as the example
            f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")
    
    print(f"Added {len(processed_files)} entries to {tsv_file}")
    
    # Verify counts match
    mp3_count = len([f for f in os.listdir(clips_dir) if f.endswith('.mp3')])
    print(f"MP3 files in {clips_dir}: {mp3_count}")
    
    # Check for discrepancy
    if mp3_count != len(processed_files):
        print(f"WARNING: Discrepancy detected! {mp3_count} MP3 files but {len(processed_files)} TSV entries.")
        print("This may indicate duplicate files or files that couldn't be processed.")
        
        # List files that are in clips_dir but not in processed_files
        processed_paths = set(info['path'] for info in processed_files)
        missing_from_tsv = []
        for file in os.listdir(clips_dir):
            if file.endswith('.mp3') and file not in processed_paths:
                missing_from_tsv.append(file)
        
        if missing_from_tsv:
            print(f"Files in clips directory but missing from TSV ({len(missing_from_tsv)}):")
            for file in missing_from_tsv[:10]:  # Show first 10
                print(f"  - {file}")
            if len(missing_from_tsv) > 10:
                print(f"  ... and {len(missing_from_tsv) - 10} more")

def rebuild_tsv_from_mp3_files(clips_dir, tsv_file):
    """Completely rebuild the TSV file based on MP3 files in the clips directory"""
    # First, try to read existing TSV file to preserve sentences
    existing_data = {}
    if os.path.exists(tsv_file):
        print(f"Reading existing TSV file {tsv_file} to preserve sentences...")
        with open(tsv_file, 'r', encoding='utf-8') as f:
            # Skip header
            header = f.readline()
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 4:  # Ensure we have enough columns
                    path = parts[1]
                    sentence = parts[3]
                    # Store the sentence indexed by the MP3 filename
                    existing_data[path] = {
                        'sentence': sentence,
                        'sentence_id': parts[2] if len(parts) > 2 else '',
                        'client_id': parts[0] if len(parts) > 0 else ''
                    }
        print(f"Loaded {len(existing_data)} entries from existing TSV file")
    
    # Read all transcripts from text files for SpeechOcean files
    text_files = {"train/text", "test/text"}
    all_transcripts = {}
    
    for text_file in text_files:
        if os.path.exists(text_file):
            with open(text_file, 'r') as f:
                for line in f:
                    parts = line.strip().split(maxsplit=1)
                    if len(parts) == 2:
                        uttid, text = parts
                        all_transcripts[uttid] = text
    
    # Get all MP3 files in the clips directory
    mp3_files = []
    for file in os.listdir(clips_dir):
        if file.endswith('.mp3'):
            mp3_files.append(file)
    
    print(f"Found {len(mp3_files)} MP3 files in {clips_dir}")
    
    # Process each MP3 file
    processed_files = []
    for mp3_name in mp3_files:
        # Check if we have existing data for this file
        if mp3_name in existing_data:
            # Use existing sentence and IDs
            sentence = existing_data[mp3_name]['sentence']
            sentence_id = existing_data[mp3_name]['sentence_id']
            client_id = existing_data[mp3_name]['client_id']
            
            processed_files.append({
                'client_id': client_id,
                'path': mp3_name,
                'sentence_id': sentence_id,
                'sentence': sentence,
                'uttid': mp3_name  # Use MP3 name as uttid for existing files
            })
        else:
            # This is a new file, try to get transcript from SpeechOcean data
            # Extract utterance ID from MP3 filename
            if mp3_name.endswith('_WAV.mp3'):
                uttid = mp3_name[:-8]  # Remove _WAV.mp3
            elif mp3_name.endswith('_wav.mp3'):
                uttid = mp3_name[:-8]  # Remove _wav.mp3
            elif '_' in mp3_name and mp3_name.startswith('SPEAKER'):
                # Handle new format: SPEAKER0001_004570283.mp3
                uttid = mp3_name.split('_', 1)[1][:-4]  # Get part after SPEAKER prefix and before .mp3
            else:
                uttid = os.path.splitext(mp3_name)[0]
            
            # Get transcript if available
            text = all_transcripts.get(uttid, "")
            
            # Format sentence
            formatted_text = format_sentence(text)
            
            # Generate IDs
            sentence_id = hashlib.sha256(formatted_text.encode()).hexdigest()
            client_id = generate_client_id()
            
            processed_files.append({
                'client_id': client_id,
                'path': mp3_name,
                'sentence_id': sentence_id,
                'sentence': formatted_text,
                'uttid': uttid
            })
    
    # Write the TSV file
    with open(tsv_file, 'w', encoding='utf-8') as f:
        f.write("client_id\tpath\tsentence_id\tsentence\tsentence_domain\tup_votes\tdown_votes\tage\tgender\taccents\tvariant\tlocale\tsegment\n")
        
        for file_info in processed_files:
            # Write the TSV line with the same format as the example
            f.write(f"{file_info['client_id']}\t{file_info['path']}\t{file_info['sentence_id']}\t{file_info['sentence']}\t\t2\t0\t\t\t\t\ten\t\n")
    
    print(f"Created TSV file with {len(processed_files)} entries")
    
    # Verify counts match
    mp3_count = len(mp3_files)
    print(f"MP3 files in {clips_dir}: {mp3_count}")
    print(f"TSV entries: {len(processed_files)}")
    
    if mp3_count != len(processed_files):
        print(f"ERROR: Counts still don't match! This should not happen.")
    else:
        print(f"SUCCESS: TSV file and MP3 files are in sync.")

if __name__ == "__main__":
    main()

