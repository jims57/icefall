conda activate icefall

#make sure the following commands are run in the conda icefall environment
cd ~/icefall/egs/commonvoice/ASR/download/l2_arctic
bash prepare_l2_arctic.sh --merge-into-dir ../concise-cv-ds-by-jimmy-1


cd ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0
bash prepare_speechocean762.sh --dev-ratio 0 --test-ratio 0 --merge-into-dir ../concise-cv-ds-by-jimmy-1

