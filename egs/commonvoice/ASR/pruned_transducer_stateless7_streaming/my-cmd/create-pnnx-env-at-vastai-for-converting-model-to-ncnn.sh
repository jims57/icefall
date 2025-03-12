#!/bin/bash
set -e  # Exit on error

echo "Starting PNNX environment setup for NCNN model conversion..."

# Install Miniconda
cd ~
echo "Downloading Miniconda..."
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
echo "Installing Miniconda silently..."
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3

# Set up PATH
echo "Setting up PATH..."
echo "export PATH=\"$HOME/miniconda3/bin:\$PATH\"" >> ~/.bashrc
source ~/.bashrc

# Initialize conda
eval "$($HOME/miniconda3/bin/conda shell.bash hook)"

# Create and set up pnnx environment
echo "Creating pnnx conda environment..."
conda create -n pnnx python=3.8 -y
conda init bash

# Activate environment
echo "Activating pnnx environment..."
conda activate pnnx

# Install PyTorch and dependencies
echo "Installing PyTorch and dependencies..."
conda install pytorch=1.13.0 torchvision torchaudio pytorch-cuda=11.6 -c pytorch -c nvidia -y
pip install git+https://github.com/lhotse-speech/lhotse

# Install k2
echo "Installing k2..."
wget https://huggingface.co/csukuangfj/k2/resolve/main/ubuntu-cuda/k2-1.24.4.dev20250304+cuda11.6.torch1.13.0-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
pip install k2-1.24.4.dev20250304+cuda11.6.torch1.13.0-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl

# Clone and set up icefall
echo "Setting up icefall..."
cd ~
git clone https://github.com/k2-fsa/icefall
cd icefall
pip install -r requirements.txt
export PYTHONPATH=/tmp/icefall:$PYTHONPATH
echo "export PYTHONPATH=/tmp/icefall:\$PYTHONPATH" >> ~/.bashrc

# Install icefall
pip install -e .

# Clone and set up librispeech model
echo "Setting up librispeech model..."
cd ~/icefall/egs/librispeech/ASR
GIT_LFS_SKIP_SMUDGE=1 git clone https://huggingface.co/Zengwei/icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05
cd icefall-asr-librispeech-conv-emformer-transducer-stateless2-2022-07-05

# Install git-lfs and pull large files
echo "Installing git-lfs and pulling model files..."
sudo apt-get update
sudo apt-get install -y git-lfs
git lfs pull --include "exp/pretrained-epoch-30-avg-10-averaged.pt"
git lfs pull --include "data/lang_bpe_500/bpe.model"

# Set up NCNN
echo "Setting up NCNN..."
cd $HOME
mkdir -p open-source
cd open-source
git clone https://github.com/csukuangfj/ncnn
cd ncnn
git submodule update --recursive --init
mkdir -p build-wheel
cd build-wheel

# Install build dependencies
echo "Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y cmake g++

# Build NCNN
echo "Building NCNN..."
cmake -DCMAKE_BUILD_TYPE=Release -DNCNN_PYTHON=ON -DNCNN_BUILD_BENCHMARK=OFF -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=ON ..
make -j6

# Set up environment variables
echo "Setting up environment variables..."
echo "export PYTHONPATH=$HOME/open-source/ncnn/python:\$PYTHONPATH" >> ~/.bashrc
echo "export PATH=$HOME/open-source/ncnn/tools/pnnx/build/src:\$PATH" >> ~/.bashrc
echo "export PATH=$HOME/open-source/ncnn/build-wheel/tools/quantize:\$PATH" >> ~/.bashrc

# Build PNNX
echo "Building PNNX..."
cd ~/open-source/ncnn/tools/pnnx
mkdir -p build
cd build

# Install CUDNN and build PNNX
echo "Installing CUDNN and building PNNX..."
conda install -c conda-forge cudnn -y
cmake .. -DCUDNN_INCLUDE_PATH=$HOME/miniconda3/envs/pnnx/include -DCUDNN_LIBRARY_PATH=$HOME/miniconda3/envs/pnnx/lib/python3.8/site-packages/torch/lib
make -j6

# Install kaldifeat
echo "Installing kaldifeat..."
cd ~
wget https://huggingface.co/csukuangfj/kaldifeat/resolve/main/cuda/1.25.5.dev20241029/linux/kaldifeat-1.25.5.dev20250203+cuda11.6.torch1.13.0-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
pip install kaldifeat-1.25.5.dev20250203+cuda11.6.torch1.13.0-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl

echo "======================================================================"
echo "PNNX environment setup complete!"
echo "Please restart your shell or run 'source ~/.bashrc' to apply changes."
echo "Then activate the environment with 'conda activate pnnx'"
echo "======================================================================"
