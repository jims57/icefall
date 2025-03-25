#!/bin/bash
# This script sets up the icefall environment and runs tests

# [way 1]: Set up env manually
# Install wget
sudo apt update
sudo apt install wget

# Install conda
cd ~
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
echo "export PATH=\"/root/miniconda3/bin:\$PATH\"" >> ~/.bashrc
source ~/.bashrc

# Create conda env
# chattts python version
conda create -n icefall python=3.11.11 -y

# Restart shell
source ~/.bashrc
conda init

echo "Please restart your shell now and then run the next part of the script"
echo "After restarting, run: conda activate icefall"
echo "Then continue with the rest of the installation"

# The following commands should be run after restarting and activating the environment:
# conda activate icefall

# Install numpy first
pip install numpy==1.26.4

# Check CUDA version and install appropriate packages
CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d. -f1)
CUDA_MINOR=$(echo $CUDA_VERSION | cut -d. -f2)

echo "Detected CUDA version: $CUDA_VERSION"

if [[ "$CUDA_MAJOR" -eq 11 && "$CUDA_MINOR" -eq 7 ]]; then
    echo "Installing packages for CUDA 11.7"
    # Install torch and torchaudio for CUDA 11.7
    pip install --force-reinstall torch==2.0.1+cu117 torchaudio==2.0.2 --extra-index-url https://download.pytorch.org/whl/cu117
    
    # Install k2 for CUDA 11.7
    wget https://huggingface.co/csukuangfj/k2/resolve/main/ubuntu-cuda/k2-1.24.4.dev20240223+cuda11.7.torch2.0.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install k2-1.24.4.dev20240223+cuda11.7.torch2.0.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    
    # Install kaldifeat for CUDA 11.7
    wget https://huggingface.co/csukuangfj/kaldifeat/resolve/main/cuda/1.25.5.dev20241029/linux/kaldifeat-1.25.5.dev20250203+cuda11.7.torch2.0.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install kaldifeat-1.25.5.dev20250203+cuda11.7.torch2.0.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    
elif [[ "$CUDA_MAJOR" -eq 12 && "$CUDA_MINOR" -eq 1 ]]; then
    echo "Installing packages for CUDA 12.1"
    # Install torch and torchaudio for CUDA 12.1
    pip install --force-reinstall torch==2.1.0+cu121 torchaudio==2.1.0 --extra-index-url https://download.pytorch.org/whl/cu121
    
    # Install k2 for CUDA 12.1
    wget https://huggingface.co/csukuangfj/k2/resolve/main/ubuntu-cuda/k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    
    # Install kaldifeat for CUDA 12.1
    wget https://huggingface.co/csukuangfj/kaldifeat/resolve/main/cuda/1.25.5.dev20241029/linux/kaldifeat-1.25.5.dev20250203+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install kaldifeat-1.25.5.dev20250203+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    
else
    echo "Unsupported CUDA version: $CUDA_VERSION"
    echo "This script supports CUDA 11.7 and 12.1"
    echo "Defaulting to CUDA 12.1 packages, but they may not work correctly"
    
    # Default to CUDA 12.1 packages
    pip install --force-reinstall torch==2.1.0+cu121 torchaudio==2.1.0 --extra-index-url https://download.pytorch.org/whl/cu121
    
    wget https://huggingface.co/csukuangfj/k2/resolve/main/ubuntu-cuda/k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    
    wget https://huggingface.co/csukuangfj/kaldifeat/resolve/main/cuda/1.25.5.dev20241029/linux/kaldifeat-1.25.5.dev20250203+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
    pip install kaldifeat-1.25.5.dev20250203+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
fi

# Check torch version
python -c "import torch; print(torch.__version__)"

# Check torchaudio installation
python -c "import torchaudio; import torch; print(f'torchaudio version: {torchaudio.__version__}'); print(f'torch version: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version: {torch.version.cuda}' if torch.cuda.is_available() else 'CUDA not available')"

# Check k2 installation
pip list | grep k2

# Install lhotse
pip install git+https://github.com/lhotse-speech/lhotse

# Check lhotse installation
pip list | grep lhotse

# Install icefall
cd ~
git clone https://github.com/k2-fsa/icefall
cd ~/icefall
pip install -r requirements.txt

# Unset env variable
unset PYTHONPATH
export PYTHONPATH=~/icefall:$PYTHONPATH

# Test installation
cd ~/icefall/egs/yesno/ASR
rm -rf data

# Check kaldifeat installation
python -c "import kaldifeat; print(f'Kaldifeat version: {kaldifeat.__version__}')"

# Prepare data
./prepare.sh

# Training (uncomment to run)
# export CUDA_VISIBLE_DEVICES="0"
# ./tdnn/train.py

# Decoding (uncomment to run)
# ./tdnn/decode.py

# Pre-trained model
mkdir -p ~/icefall/egs/yesno/ASR/tmp
cd ~/icefall/egs/yesno/ASR/tmp
git clone https://huggingface.co/csukuangfj/icefall_asr_yesno_tdnn

# Install find command and git-lfs
apt-get update
apt-get install -y file git-lfs
git lfs install

# Download actual model files
cd ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn
git lfs pull

# Check file size to confirm download
ls -la ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/pretrained.pt

# Decode file with pre-trained model
cd ~/icefall/egs/yesno/ASR
./tdnn/pretrained.py --checkpoint ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/pretrained.pt --words-file ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/lang_phone/words.txt --HLG ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/lang_phone/HLG.pt ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/test_waves/1_0_1_1_0_1_1_1.wav ~/icefall/egs/yesno/ASR/tmp/icefall_asr_yesno_tdnn/test_waves/0_0_1_0_1_0_0_1.wav

python -c "import torch; print(f'GPU memory allocated: {torch.cuda.memory_allocated() / 1e9} GB'); print(f'GPU memory reserved: {torch.cuda.memory_reserved() / 1e9} GB')"