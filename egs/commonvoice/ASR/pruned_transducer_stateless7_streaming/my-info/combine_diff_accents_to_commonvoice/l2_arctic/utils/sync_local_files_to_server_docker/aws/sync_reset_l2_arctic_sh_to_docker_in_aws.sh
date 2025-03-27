#!/bin/bash
# Copyright    2023-2024  Watchfun Co., Ltd.        (authors: Jimmy Gan)
#
# This script syncs the reset_l2_arctic.sh file from local machine to AWS server and then to Docker container

# Step 1: Run on local machine to copy the file to AWS server
echo "Creating directory on AWS server and copying reset_l2_arctic.sh..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "mkdir -p ~/icefall/egs/commonvoice/ASR/download/l2_arctic" && \
scp -i /Users/mac/.ssh/aws/aws-icefall.pem /Users/mac/Documents/GitHub/icefall/egs/commonvoice/ASR/pruned_transducer_stateless7_streaming/my-info/combine_diff_accents_to_commonvoice/l2_arctic/reset_l2_arctic.sh ubuntu@3.22.99.8:~/icefall/egs/commonvoice/ASR/download/l2_arctic/

echo "File copied to AWS server successfully."

# Step 2: Copy the file from AWS server to Docker container
echo "Copying file from AWS server to Docker container..."
ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8 "docker cp ~/icefall/egs/commonvoice/ASR/download/l2_arctic/reset_l2_arctic.sh 432a764e93ea:/root/icefall/egs/commonvoice/ASR/download/l2_arctic/"

echo "File copied to Docker container successfully."
echo ""
echo "If you want to run the script in the Docker container, you can use these commands:"
echo "1. SSH into the AWS server: ssh -i /Users/mac/.ssh/aws/aws-icefall.pem ubuntu@3.22.99.8"
echo "2. Access the Docker container: docker exec -it 432a764e93ea bash"
echo "3. Navigate to the directory: cd /root/icefall/egs/commonvoice/ASR/download/l2_arctic/"
echo "4. Run the script: bash reset_l2_arctic.sh"