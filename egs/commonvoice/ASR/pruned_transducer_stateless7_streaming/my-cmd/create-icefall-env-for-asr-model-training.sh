# sudo apt update
# sudo apt install wget

# cd ~
# wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
# chmod +x Miniconda3-latest-Linux-x86_64.sh
# bash Miniconda3-latest-Linux-x86_64.sh
# echo "export PATH=\"/root/miniconda3/bin:\$PATH\"" >> ~/.bashrc
# source ~/.bashrc

# conda create -n icefall python=3.11.11
# source ~/.bashrc
# conda init

# #restart instance

# conda activate icefall

# pip install torch==2.0.1+cu117 torchaudio==2.0.2 --extra-index-url https://download.pytorch.org/whl/cu117
# pip install k2==1.24.4.dev20241029+cuda11.7.torch2.0.1 -f https://k2-fsa.github.io/k2/cuda.html
# pip install git+https://github.com/lhotse-speech/lhotse

# cd ~
# git clone https://github.com/k2-fsa/icefall
# cd ~/icefall
# pip install -r requirements.txt
# export PYTHONPATH=~/icefall:$PYTHONPATH

# cd ~/icefall/egs/yesno/ASR
# rm -rf data
# pip uninstall -y numpy
# pip install numpy==1.24.3

# pip install kaldifeat==1.25.5.dev20250203+cuda11.7.torch2.0.1  -f https://csukuangfj.github.io/kaldifeat/cuda.html

# apt-get update
# apt-get install -y file
# apt-get install -y git-lfs
# git lfs install

# sudo apt update
# sudo apt install tree

# export CUDA_VISIBLE_DEVICES="0"
# ./prepare.sh




#!/bin/bash

# Exit on error
set -e

echo "===== Starting Icefall Environment Setup ====="
# Define stage variables for controlling script execution
stage=1
stop_stage=100

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      stage="$2"
      shift 2
      ;;
    --stop_stage)
      stop_stage="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function for logging with timestamp
log() {
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}) $*"
}

log "Starting environment setup with stage=$stage, stop_stage=$stop_stage"

# Set CUDA device if available
export CUDA_VISIBLE_DEVICES="0"

# Stage 1: Set up basic environment and install Miniconda
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
  echo "Stage 1: Setting up basic environment and Miniconda"
  
  # Update system packages
  echo "Updating system packages..."
  sudo apt update
  sudo apt install -y wget file git-lfs tree

  # Install git-lfs
  echo "Setting up Git LFS..."
  git lfs install

  # Install Miniconda
  echo "Installing Miniconda..."
  cd ~
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  chmod +x Miniconda3-latest-Linux-x86_64.sh
  bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
  rm Miniconda3-latest-Linux-x86_64.sh

  # Set up conda in PATH
  echo "Setting up conda in PATH..."
  echo 'export PATH="$HOME/miniconda3/bin:$PATH"' >> ~/.bashrc
  eval "$(~/miniconda3/bin/conda shell.bash hook)"

  # Initialize conda for shell interaction
  conda init bash

  # Create icefall environment
  echo "Creating icefall conda environment..."
  conda create -y -n icefall python=3.11.11
fi

# Stage 2: Install dependencies and set up icefall
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
  echo "Stage 2: Installing dependencies and setting up icefall"
  
  # Activate icefall environment
  echo "Activating icefall environment..."
  eval "$(~/miniconda3/bin/conda shell.bash hook)"
  conda activate icefall

  # Install CUDA Toolkit 11.7 to match PyTorch version
  echo "Installing CUDA Toolkit 11.7..."
  wget https://developer.download.nvidia.com/compute/cuda/11.7.0/local_installers/cuda_11.7.0_515.43.04_linux.run
  sudo sh cuda_11.7.0_515.43.04_linux.run --silent --toolkit
  echo 'export PATH="/usr/local/cuda-11.7/bin:$PATH"' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH="/usr/local/cuda-11.7/lib64:$LD_LIBRARY_PATH"' >> ~/.bashrc
  source ~/.bashrc

  # Install PyTorch and related packages
  echo "Installing PyTorch and related packages..."
  pip install torch==2.0.1+cu117 torchaudio==2.0.2 --extra-index-url https://download.pytorch.org/whl/cu117
  pip install k2==1.24.4.dev20241029+cuda11.7.torch2.0.1 -f https://k2-fsa.github.io/k2/cuda.html
  pip install git+https://github.com/lhotse-speech/lhotse

  # Clone icefall repository
  echo "Cloning icefall repository..."
  cd ~
  git clone https://github.com/k2-fsa/icefall
  cd ~/icefall
  pip install -r requirements.txt

  # Set PYTHONPATH
  echo 'export PYTHONPATH="$HOME/icefall:$PYTHONPATH"' >> ~/.bashrc

  # Fix numpy version
  echo "Installing specific numpy version..."
  pip uninstall -y numpy
  pip install numpy==1.24.3

  # Install kaldifeat
  echo "Installing kaldifeat..."
  pip install kaldifeat==1.25.5.dev20250203+cuda11.7.torch2.0.1 -f https://csukuangfj.github.io/kaldifeat/cuda.html

  # Set CUDA device
  echo 'export CUDA_VISIBLE_DEVICES="0"' >> ~/.bashrc

  # Verify CUDA versions match
  echo "Verifying CUDA versions..."
  echo "CUDA Toolkit version:"
  nvcc --version
  echo "PyTorch CUDA version:"
  python -c "import torch; print('PyTorch CUDA version:', torch.version.cuda)"
fi

echo "===== Icefall Environment Setup Complete ====="