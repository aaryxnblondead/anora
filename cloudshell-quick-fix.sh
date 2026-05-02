#!/bin/bash
# Quick fix script for CloudShell - removes --tags parameter from deploy.sh

DEPLOY_SCRIPT="/tmp/anora-deployment/deploy.sh"

required_vars=(
  "AUTH_JWT_SECRET"
  "AUTH_JWT_EXP_SECONDS"
  "OTP_TTL_SECONDS"
  "OTP_MAX_ATTEMPTS"
  "OTP_DEBUG_ECHO"
  "AWS_SMS_TYPE"
  "AWS_SNS_SMS_SENDER_ID"
  "APP_RUNNER_RUNTIME_ROLE_ARN"
)

for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name}" ]; then
    echo "❌ Missing required env var: $var_name"
    echo "Set all required OTP/Auth vars and retry."
    exit 1
  fi
done

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
    --runtime-role-arn "$APP_RUNNER_RUNTIME_ROLE_ARN" \
    --app-runner-arn "arn:aws:apprunner:us-east-1:027277540377:service/anora-backend/0c2f45467984444888a19088517d15a9"
else
  echo "❌ deploy.sh not found at $DEPLOY_SCRIPT"
  exit 1
fi
