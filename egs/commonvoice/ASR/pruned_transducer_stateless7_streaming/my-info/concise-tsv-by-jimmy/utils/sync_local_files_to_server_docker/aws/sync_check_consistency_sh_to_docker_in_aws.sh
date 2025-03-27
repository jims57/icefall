#!/bin/bash
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# This script syncs the check_consistency.sh file from local machine to AWS server and then to Docker container

# Step 1: Run on local machine to copy the file to AWS server
echo "Creating directory on AWS server and copying check_consistency.sh..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "mkdir -p ~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1" && \
scp -i /Users/mac/.ssh/aws/aws-icefall.pem /Users/mac/Documents/GitHub/icefall/egs/commonvoice/ASR/pruned_transducer_stateless7_streaming/my-info/concise-tsv-by-jimmy/check_consistency.sh ubuntu@3.22.99.8:~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/

echo "File copied to AWS server successfully."

# Step 2: Copy the file from AWS server to Docker container
echo "Copying file from AWS server to Docker container..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "docker cp ~/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/check_consistency.sh 432a764e93ea:/root/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/"

echo "File copied to Docker container successfully."
echo ""
echo "If you want to access the file in the Docker container, you can use these commands:"
echo "1. SSH into the AWS server: ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8"
echo "2. Access the Docker container: docker exec -it 432a764e93ea bash"
echo "3. Navigate to the directory: cd /root/icefall/egs/commonvoice/ASR/download/concise-cv-ds-by-jimmy-1/"