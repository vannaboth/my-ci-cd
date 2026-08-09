#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_DIR/terraform"

# Read ssh_key_name + region from terraform.tfvars (skip comments/blank lines)
KEY_NAME="$(grep -E '^ssh_key_name' "$TF_DIR/terraform.tfvars" | awk -F'"' '{print $2}')"
REGION="$(grep -E '^aws_region' "$TF_DIR/terraform.tfvars" | awk -F'"' '{print $2}')"
PUB_KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem.pub"

cd "$TF_DIR"

if [ ! -f .terraform.lock.hcl ]; then
  terraform init
fi

# Ensure the EC2 key pair exists in AWS (avoids console import formatting issues)
if [ -n "$KEY_NAME" ] && [ -f "$PUB_KEY_FILE" ]; then
  if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo "Importing EC2 key pair '$KEY_NAME' from $PUB_KEY_FILE..."
    aws ec2 import-key-pair \
      --region "$REGION" \
      --key-name "$KEY_NAME" \
      --public-key-material "fileb://$PUB_KEY_FILE"
  else
    echo "EC2 key pair '$KEY_NAME' already exists."
  fi
else
  echo "WARNING: ssh_key_name or $PUB_KEY_FILE not found — skipping key import."
fi

terraform apply -auto-approve

JENKINS_IP="$(terraform output -raw jenkins_public_ip)"
APP_IP="$(terraform output -raw app_public_ip)"

echo
echo "Created instances:"
echo "jenkins_public_ip = $JENKINS_IP"
echo "app_public_ip     = $APP_IP"

# Inject the auto-allocated IPs into the Ansible inventory
INVENTORY="$REPO_DIR/ansible/inventory.yml"
if [ -f "$INVENTORY" ]; then
  sed -i.bak \
    -e "s/JENKINS_EC2_PUBLIC_IP/$JENKINS_IP/g" \
    -e "s/APP_EC2_PUBLIC_IP/$APP_IP/g" \
    "$INVENTORY"
  rm -f "$INVENTORY.bak"
  echo
  echo "Updated $INVENTORY with the instance IPs."
fi
