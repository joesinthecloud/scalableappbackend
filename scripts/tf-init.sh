#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION="us-east-1"
export STATE_BUCKET="tf-state-949367020370-scalableappbackend"
export LOCK_TABLE="tf-lock-scalableappbackend"

terraform -chdir=infra init -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=env/dev/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${LOCK_TABLE}" \
  -backend-config="encrypt=true"
