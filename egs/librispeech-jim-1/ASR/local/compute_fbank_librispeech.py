#!/usr/bin/env python3
# Copyright    2021  Xiaomi Corp.        (authors: Fangjun Kuang)
#
# See ../../../../LICENSE for clarification regarding multiple authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


"""
This file computes fbank features of the LibriSpeech dataset.
It looks for manifests in the directory data/manifests.

The generated fbank features are saved in data/fbank.
"""

import argparse
import glob
import logging
import os
from pathlib import Path
from typing import Optional, List, Tuple, Dict

import sentencepiece as spm
import torch
from filter_cuts import filter_cuts
from lhotse import CutSet, Fbank, FbankConfig, LilcomChunkyWriter, RecordingSet, SupervisionSet
from lhotse.recipes.utils import read_manifests_if_cached

from icefall.utils import get_executor, str2bool

# Torch's multithreaded behavior needs to be disabled or
# it wastes a lot of CPU and slow things down.
# Do this outside of main() in case it needs to take effect
# even when we are not invoking the main (e.g. when spawning subprocesses).
torch.set_num_threads(1)
torch.set_num_interop_threads(1)


def get_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--bpe-model",
        type=str,
        help="""Path to the bpe.model. If not None, we will remove short and
        long utterances before extracting features""",
    )

    parser.add_argument(
        "--dataset",
        type=str,
        help="""Dataset parts to compute fbank. If None, we will use all""",
    )

    parser.add_argument(
        "--dataset-size",
        type=str,
        default="full",
        choices=["full", "mini"],
        help="""Whether to use full dataset or mini dataset (train-clean-100 only)""",
    )

    parser.add_argument(
        "--perturb-speed",
        type=str2bool,
        default=True,
        help="""Perturb speed with factor 0.9 and 1.1 on train subset.""",
    )

    return parser.parse_args()


def compute_fbank_librispeech(
    bpe_model: Optional[str] = None,
    dataset: Optional[str] = None,
    dataset_size: str = "full",
    perturb_speed: Optional[bool] = True,
):
    src_dir = Path("data/manifests")
    output_dir = Path("data/fbank")
    num_jobs = min(15, os.cpu_count())
    num_mel_bins = 80

    if bpe_model:
        logging.info(f"Loading {bpe_model}")
        sp = spm.SentencePieceProcessor()
        sp.load(bpe_model)

    # Determine which dataset parts to use based on dataset_size
    if dataset_size == "mini":
        target_parts = [
            "dev-clean",
            "dev-other",
            "test-clean",
            "test-other",
            "train-clean-100",
        ]
    else:
        target_parts = [
            "dev-clean",
            "dev-other",
            "test-clean",
            "test-other",
            "train-clean-100",
            "train-clean-360",
            "train-other-500",
        ]

    # If specific dataset parts are requested, filter them
    if dataset is not None:
        dataset_parts = dataset.split(" ", -1)
        # Only keep parts that are available in the selected dataset_size
        target_parts = [part for part in target_parts if part in dataset_parts]

    logging.info(f"Looking for manifests in {src_dir}")
    logging.info(f"Target parts for dataset_size={dataset_size}: {target_parts}")
    
    # Find all available manifest files
    recording_files = glob.glob(str(src_dir / "librispeech_recordings_*.jsonl.gz"))
    supervision_files = glob.glob(str(src_dir / "librispeech_supervisions_*.jsonl.gz"))
    
    logging.info(f"Found recording files: {recording_files}")
    logging.info(f"Found supervision files: {supervision_files}")
    
    # Extract the actual parts from filenames
    available_parts = []
    for f in recording_files:
        part = os.path.basename(f).replace("librispeech_recordings_", "").replace(".jsonl.gz", "")
        available_parts.append(part)
    
    logging.info(f"Available parts from manifest files: {available_parts}")
    
    # Map target parts to available parts
    part_mapping = {}
    for target in target_parts:
        for available in available_parts:
            if target in available:
                part_mapping[target] = available
                break
    
    logging.info(f"Part mapping: {part_mapping}")
    
    # Process each mapped part
    with get_executor() as ex:  # Initialize the executor only once.
        for target_part, actual_part in part_mapping.items():
            cuts_filename = f"librispeech_cuts_{target_part}.jsonl.gz"
            if (output_dir / cuts_filename).is_file():
                logging.info(f"{target_part} already exists - skipping.")
                continue
                
            logging.info(f"Processing {target_part} (using manifest {actual_part})")
            
            # Load recordings and supervisions
            recordings = RecordingSet.from_jsonl_gz(src_dir / f"librispeech_recordings_{actual_part}.jsonl.gz")
            supervisions = SupervisionSet.from_jsonl_gz(src_dir / f"librispeech_supervisions_{actual_part}.jsonl.gz")
            
            # Create cut set
            cut_set = CutSet.from_manifests(
                recordings=recordings,
                supervisions=supervisions,
            )
            
            logging.info(f"Created cut set with {len(cut_set)} cuts")

            if "train" in target_part:
                if bpe_model:
                    cut_set = filter_cuts(cut_set, sp)
                if perturb_speed:
                    logging.info(f"Doing speed perturb")
                    cut_set = (
                        cut_set
                        + cut_set.perturb_speed(0.9)
                        + cut_set.perturb_speed(1.1)
                    )
            
            logging.info(f"Computing features for {target_part}")
            cut_set = cut_set.compute_and_store_features(
                extractor=Fbank(FbankConfig(num_mel_bins=num_mel_bins)),
                storage_path=f"{output_dir}/librispeech_feats_{target_part}",
                # when an executor is specified, make more partitions
                num_jobs=num_jobs if ex is None else 80,
                executor=ex,
                storage_type=LilcomChunkyWriter,
            )
            
            logging.info(f"Saving cut set to {output_dir / cuts_filename}")
            cut_set.to_file(output_dir / cuts_filename)


if __name__ == "__main__":
    formatter = "%(asctime)s %(levelname)s [%(filename)s:%(lineno)d] %(message)s"

    logging.basicConfig(format=formatter, level=logging.INFO)
    args = get_args()
    logging.info(vars(args))
    compute_fbank_librispeech(
        bpe_model=args.bpe_model,
        dataset=args.dataset,
        dataset_size=args.dataset_size,
        perturb_speed=args.perturb_speed,
    )
