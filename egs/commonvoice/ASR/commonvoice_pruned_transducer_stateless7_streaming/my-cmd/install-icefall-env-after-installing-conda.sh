sudo apt update
sudo apt install -y wget
cd ~
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b
echo "export PATH=\"/root/miniconda3/bin:\$PATH\"" >> ~/.bashrc
source ~/.bashrc
conda create -y -n icefall python=3.11.11
source ~/.bashrc
conda init
conda activate icefall
nvcc --version
pip uninstall -y torch torchvision torchaudio
pip install torch==2.0.1+cu117 torchaudio==2.0.2 --extra-index-url https://download.pytorch.org/whl/cu117
pip install numpy==1.26.4
pip install --force-reinstall torch==2.1.0+cu121 torchaudio==2.1.0 --extra-index-url https://download.pytorch.org/whl/cu121
python -c "import torch; print(torch.__version__)"
python -c "import torchaudio; import torch; print(f'torchaudio version: {torchaudio.__version__}'); print(f'torch version: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version: {torch.version.cuda}' if torch.cuda.is_available() else 'CUDA not available')"
pip install k2==1.24.4.dev20241029+cuda11.7.torch2.0.1 -f https://k2-fsa.github.io/k2/cuda.html
wget https://huggingface.co/csukuangfj/k2/resolve/main/ubuntu-cuda/k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
pip install k2-1.24.4.dev20240223+cuda12.1.torch2.1.0-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
pip list | grep k2
pip install git+https://github.com/lhotse-speech/lhotse
pip list | grep lhotse
cd ~
git clone https://github.com/k2-fsa/icefall
cd ~/icefall
pip install -r requirements.txt
unset PYTHONPATH
export PYTHONPATH=~/icefall:$PYTHONPATH
cd ~/icefall/egs/yesno/ASR
pip uninstall -y numpy
pip install numpy==1.24.3