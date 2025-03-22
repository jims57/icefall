#!/usr/bin/env python3
import sys
from lhotse import CutSet

def main():
    output_file = sys.argv[-1]
    input_files = sys.argv[1:-1]
    
    print(f"Combining {len(input_files)} files into {output_file}")
    
    # Load all cuts from all files
    all_cuts = []
    for f in input_files:
        print(f"Loading {f}")
        cuts = CutSet.from_file(f)
        all_cuts.extend(cuts)
    
    # Create a new CutSet from all cuts
    combined = CutSet.from_cuts(all_cuts)
    print(f"Created combined CutSet with {len(combined)} cuts")
    
    # Save to output file
    combined.to_file(output_file)
    print(f"Saved to {output_file}")

if __name__ == "__main__":
    main()
