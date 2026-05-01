#!/bin/bash
# Quick fix script for CloudShell - removes --tags parameter from deploy.sh

DEPLOY_SCRIPT="/tmp/anora-deployment/deploy.sh"

if [ -f "$DEPLOY_SCRIPT" ]; then
  echo "Applying fix to deploy.sh..."
  # Remove the line with --tags (should be around line 202-203)
  sed -i '/--tags/d' "$DEPLOY_SCRIPT"
  echo "✅ Fixed! Removed --tags parameter"
  echo ""
  echo "Now running deploy.sh..."
  bash "$DEPLOY_SCRIPT" \
    --aws-account "027277540377" \
    --aws-region "us-east-1" \
    --db-url "postgresql://anora:anora@anora-db.cu56cgggut75.us-east-1.rds.amazonaws.com:5432/anora" \
    --app-runner-arn "arn:aws:apprunner:us-east-1:027277540377:service/anora-backend/0c2f45467984444888a19088517d15a9"
else
  echo "❌ deploy.sh not found at $DEPLOY_SCRIPT"
  exit 1
fi
