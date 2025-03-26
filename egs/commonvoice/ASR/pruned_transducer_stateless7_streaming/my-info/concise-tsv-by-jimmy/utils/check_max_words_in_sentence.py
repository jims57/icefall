#!/usr/bin/env python3

import os

def main():
    # Path to the TSV file
    tsv_path = "../validated.tsv"
    
    # Check if file exists
    if not os.path.exists(tsv_path):
        print(f"Error: File {tsv_path} not found!")
        return
    
    # Instead of tracking just one max sentence, we'll track the top 3
    top_sentences = []
    total_sentences = 0
    
    # Read the TSV file
    with open(tsv_path, 'r', encoding='utf-8') as tsv_file:
        # Skip header row
        next(tsv_file)
        
        # Process each row
        for line in tsv_file:
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
                    # Update top sentences list
                    top_sentences.append((word_count, sentence))
                    
                    # Sort and keep only the top 3
                    top_sentences.sort(reverse=True)
                    if len(top_sentences) > 3:
                        top_sentences.pop()
    
    # Print results in a user-friendly format
    print(f"Analyzed {total_sentences} sentences in total.")
    print(f"\nTop 3 sentences with maximum word count:")
    
    for i, (count, sentence) in enumerate(top_sentences, 1):
        print(f"\n{i}. Sentence with {count} words:")
        print(f'"{sentence}"')

if __name__ == "__main__":
    main()
