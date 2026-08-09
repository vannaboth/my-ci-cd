#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

read -r -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -r -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo

read -r -p "AWS Region [ap-southeast-1]: " AWS_REGION_INPUT
export AWS_REGION="${AWS_REGION_INPUT:-ap-southeast-1}"
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

echo "Verifying credentials..."
aws sts get-caller-identity

echo
echo "Creating infrastructure..."
./scripts/create-infra.sh
