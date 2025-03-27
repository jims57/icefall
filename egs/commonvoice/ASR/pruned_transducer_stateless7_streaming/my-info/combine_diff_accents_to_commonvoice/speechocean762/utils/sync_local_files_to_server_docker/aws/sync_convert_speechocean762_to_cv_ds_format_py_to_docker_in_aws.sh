#!/bin/bash
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# This script syncs the convert_speechocean762_to_cv_ds_format.py file from local machine to AWS server and then to Docker container

# Step 1: Run on local machine to copy the file to AWS server
echo "Creating directory on AWS server and copying convert_speechocean762_to_cv_ds_format.py..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "mkdir -p ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0" && \
scp -i /Users/mac/.ssh/aws/aws-icefall.pem /Users/mac/Documents/GitHub/icefall/egs/commonvoice/ASR/pruned_transducer_stateless7_streaming/my-info/combine_diff_accents_to_commonvoice/speechocean762/convert_speechocean762_to_cv_ds_format.py ubuntu@3.22.99.8:~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/

echo "File copied to AWS server successfully."

# Step 2: Copy the file from AWS server to Docker container
echo "Creating directory in Docker container and copying file from AWS server..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "docker exec 432a764e93ea mkdir -p /root/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0"
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "docker cp ~/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/convert_speechocean762_to_cv_ds_format.py 432a764e93ea:/root/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/"

echo "File copied to Docker container successfully."
echo ""
echo "If you want to run the script in the Docker container, you can use these commands:"
echo "1. SSH into the AWS server: ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8"
echo "2. Access the Docker container: docker exec -it 432a764e93ea bash"
echo "3. Navigate to the directory: cd /root/icefall/egs/commonvoice/ASR/download/speechocean762-1.2.0/"
echo "4. Run the script: bash convert_speechocean762_to_cv_ds_format.py"