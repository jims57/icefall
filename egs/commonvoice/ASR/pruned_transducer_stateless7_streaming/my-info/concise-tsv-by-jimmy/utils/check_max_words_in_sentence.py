#!/usr/bin/env python3

import os

def main():
    # Path to the TSV file
    tsv_path = "../validated.tsv"
    
    # Check if file exists
    if not os.path.exists(tsv_path):
        print(f"Error: File {tsv_path} not found!")
        return
    
    # Track the top 3 and bottom 3 sentences
    top_sentences = []
    min_sentences = []
    total_sentences = 0
    
    # Read the TSV file
    with open(tsv_path, 'r', encoding='utf-8') as tsv_file:
        # Skip header row
        next(tsv_file)
        
        # Process each row
        for line_idx, line in enumerate(tsv_file, 2):  # Start from 2 (after header)
            total_sentences += 1
            
            # Split the line by tabs
            fields = line.strip().split('\t')
            
            # Make sure we have enough columns and access the sentence field (index 3)
            if len(fields) > 3:
                sentence = fields[3]
                
                # Count words in the sentence (split by whitespace)
                word_count = len(sentence.split())
                
                # Only consider the sentence if it has words
                if word_count > 0:
                    # Update top sentences list with (count, row_id, sentence)
                    top_sentences.append((word_count, line_idx, sentence))
                    
                    # Sort and keep only the top 3
                    top_sentences.sort(reverse=True)
                    if len(top_sentences) > 3:
                        top_sentences.pop()
                    
                    # Update min sentences list
                    min_sentences.append((word_count, line_idx, sentence))
                    
                    # Sort and keep only the bottom 3
                    min_sentences.sort()  # Sort ascending
                    if len(min_sentences) > 3:
                        min_sentences.pop()
    
    # Print results in a user-friendly format
    print(f"Analyzed {total_sentences} sentences in total.")
    
    # Print top 3 sentences
    print(f"\nTop 3 sentences with maximum word count:")
    for i, (count, row_id, sentence) in enumerate(top_sentences, 1):
        print(f"\n{i}. Sentence with {count} words (Row {row_id}):")
        print(f'"{sentence}"')
    
    # Print bottom 3 sentences
    print(f"\nBottom 3 sentences with minimum word count:")
    for i, (count, row_id, sentence) in enumerate(min_sentences, 1):
        print(f"\n{i}. Sentence with {count} words (Row {row_id}):")
        print(f'"{sentence}"')

if __name__ == "__main__":
    main()
