#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

if [ ! -f .terraform.lock.hcl ]; then
  terraform init
fi

terraform apply -auto-approve

echo
echo "Created instances:"
terraform output
