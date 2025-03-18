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

# Activate icefall environment
echo "Activating icefall environment..."
conda activate icefall

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

echo "===== Icefall Environment Setup Complete ====="
echo "To activate the environment, run: conda activate icefall"
echo "You may need to restart your shell or run 'source ~/.bashrc' for all changes to take effect"