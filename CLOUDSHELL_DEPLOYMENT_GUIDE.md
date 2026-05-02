# AWS CloudShell Deployment Guide for Anora

**Estimated Time:** 15-20 minutes (first deployment) | 5-10 minutes (subsequent)

---

## Quick Start (Copy & Paste)

### 1. Open AWS CloudShell

1. Log into [AWS Console](https://console.aws.amazon.com/)
2. Click the **CloudShell** icon (terminal icon) in the top-right corner
3. Wait for terminal to load (first time may take 30 seconds)

### 2. Set Environment Variables

```bash
export AWS_ACCOUNT_ID="027277540377"
export AWS_REGION="us-east-1"
export DATABASE_URL="postgresql://user:password@hostname:5432/anora_prod"
export APP_RUNNER_SERVICE_NAME="anora-backend"
export APP_RUNNER_RUNTIME_ROLE_ARN="arn:aws:iam::027277540377:role/anora-apprunner-runtime-role"

# Required auth/OTP runtime vars for backend
export AUTH_JWT_SECRET="replace-with-long-random-secret"
export AUTH_JWT_EXP_SECONDS="86400"
export OTP_TTL_SECONDS="300"
export OTP_MAX_ATTEMPTS="5"
export OTP_DEBUG_ECHO="false"
export AWS_SMS_TYPE="Transactional"
export AWS_SNS_SMS_SENDER_ID="ANORA"
```

**Where to get these values:**
- **AWS_ACCOUNT_ID**: Click account name (top-right) → see Account ID
- **AWS_REGION**: Top-right dropdown or `us-east-1` (default)
- **DATABASE_URL**: AWS RDS console → Copy endpoint and credentials
- **APP_RUNNER_SERVICE_NAME**: AWS App Runner console → Your service name
- **APP_RUNNER_RUNTIME_ROLE_ARN**: App Runner service → Instance configuration → Instance role ARN
- **AUTH_JWT_SECRET**: Generate a strong random secret and store in a secure secret manager

Before deploying, verify runtime role permission for OTP SMS:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "$APP_RUNNER_RUNTIME_ROLE_ARN" \
  --action-names sns:Publish \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text

# Expected output: allowed
```

### 3. Clone Repository & Run Deployment Script

```bash
cd /tmp
git clone https://github.com/aaryxnblondead/anora.git anora-deploy
cd anora-deploy
chmod +x deploy.sh

./deploy.sh \
  --aws-account "$AWS_ACCOUNT_ID" \
  --aws-region "$AWS_REGION" \
  --db-url "$DATABASE_URL" \
  --runtime-role-arn "$APP_RUNNER_RUNTIME_ROLE_ARN"
```

**If you already have an App Runner service, add this flag:**

```bash
./deploy.sh \
  --aws-account "$AWS_ACCOUNT_ID" \
  --aws-region "$AWS_REGION" \
  --db-url "$DATABASE_URL" \
  --runtime-role-arn "$APP_RUNNER_RUNTIME_ROLE_ARN" \
  --app-runner-arn "arn:aws:apprunner:us-east-1:027277540377:service/anora-backend/..."
```

### 4. Watch the Script Run

The script will:
- ✅ Clone your repository
- ✅ Build Docker image
- ✅ Push to AWS ECR
- ✅ Deploy to App Runner (if ARN provided)
- ✅ Initialize database (create FL tables, round 0)
- ✅ Test health endpoint

**Output will show:**
```
✅ Repository ready at /tmp/anora-deployment
✅ Docker image built: anora-backend:latest
✅ ECR authentication successful
✅ Image pushed to ECR: 027277540377.dkr.ecr.us-east-1.amazonaws.com/anora-backend:latest
✅ Found App Runner service: arn:aws:apprunner:...
✅ App Runner deployment initiated
✅ App Runner service is ACTIVE
✅ Database initialization complete
✅ Health check passed!

API: https://xydctnf6j6.us-east-1.awsapprunner.com
```

---

## Step-by-Step Guide (If Copy-Paste Fails)

### Prerequisites Checklist

- [ ] AWS Console access with permissions to:
  - ECR (create/push images)
  - App Runner (update services)
  - RDS (database access)
  - CloudShell (run scripts)

- [ ] PostgreSQL database running and accessible
  - Test: `psql "$DATABASE_URL" -c "SELECT 1;"`

- [ ] App Runner service created (you can create it manually first, or script does later)

---

### Step 1: Verify CloudShell Environment

```bash
# Check Docker (should be available)
docker --version

# Check AWS CLI
aws --version

# Check Python
python3 --version

# Verify AWS credentials
aws sts get-caller-identity
```

Expected output:
```
{
    "UserId": "AIDAI...",
    "Account": "027277540377",
    "Arn": "arn:aws:iam::027277540377:user/your-user"
}
```

---

### Step 2: Create Environment Variables File

Instead of exporting each time, create a `.env.cloudshell` file:

```bash
cat > ~/.env.cloudshell << 'EOF'
export AWS_ACCOUNT_ID="027277540377"
export AWS_REGION="us-east-1"
export DATABASE_URL="postgresql://anora_user:SecurePassword123@anora-prod.c9akciq32.us-east-1.rds.amazonaws.com:5432/anora_prod"
export ALLOWED_ORIGINS="https://d1p1fpleu1yzws.cloudfront.net"
export APP_RUNNER_SERVICE_NAME="anora-backend"
export APP_RUNNER_RUNTIME_ROLE_ARN="arn:aws:iam::027277540377:role/anora-apprunner-runtime-role"
export AUTH_JWT_SECRET="replace-with-long-random-secret"
export AUTH_JWT_EXP_SECONDS="86400"
export OTP_TTL_SECONDS="300"
export OTP_MAX_ATTEMPTS="5"
export OTP_DEBUG_ECHO="false"
export AWS_SMS_TYPE="Transactional"
export AWS_SNS_SMS_SENDER_ID="ANORA"
EOF

# Load it
source ~/.env.cloudshell
```

Then in future CloudShell sessions:
```bash
source ~/.env.cloudshell
```

---

### Step 3: Download Deployment Script

```bash
# Clone repo
git clone https://github.com/aaryxnblondead/anora.git ~/anora-prod
cd ~/anora-prod

# Make script executable
chmod +x deploy.sh

# Verify it exists
ls -lh deploy.sh
```

---

### Step 4: Run Deployment

**First time (no App Runner ARN yet):**

```bash
./deploy.sh \
  --aws-account "$AWS_ACCOUNT_ID" \
  --aws-region "$AWS_REGION" \
  --db-url "$DATABASE_URL" \
  --runtime-role-arn "$APP_RUNNER_RUNTIME_ROLE_ARN"
```

**If App Runner exists:**

Find your service ARN:
```bash
aws apprunner list-services \
  --region "$AWS_REGION" \
  --query "ServiceSummaryList[*].[ServiceName,ServiceArn]" \
  --output table
```

Copy the ARN, then:

```bash
APP_RUNNER_ARN="arn:aws:apprunner:us-east-1:027277540377:service/anora-backend/abc123def456"

./deploy.sh \
  --aws-account "$AWS_ACCOUNT_ID" \
  --aws-region "$AWS_REGION" \
  --db-url "$DATABASE_URL" \
  --runtime-role-arn "$APP_RUNNER_RUNTIME_ROLE_ARN" \
  --app-runner-arn "$APP_RUNNER_ARN"
```

---

### Step 5: Monitor Deployment

While script runs, you can open new CloudShell tab and monitor:

```bash
# Watch App Runner deployment
aws apprunner describe-service \
  --service-arn "$APP_RUNNER_ARN" \
  --region "$AWS_REGION" \
  --query 'Service.[Status,ServiceUrl]' \
  --output table

# Stream backend logs (after App Runner is ACTIVE)
aws logs tail /aws/apprunner/anora-backend --follow --region "$AWS_REGION"

# Check ECR repository
aws ecr describe-repositories \
  --repository-names anora-backend \
  --region "$AWS_REGION" \
  --output table
```

---

### Step 6: Verify Deployment

Once script completes:

```bash
# Get the service URL
SERVICE_URL=$(aws apprunner describe-service \
  --service-arn "$APP_RUNNER_ARN" \
  --region "$AWS_REGION" \
  --query 'Service.ServiceUrl' \
  --output text)

# Test health endpoint
curl -s "https://$SERVICE_URL/health" | jq .

# Expected output:
# {
#   "status": "ok",
#   "db_ready": true,
#   "db_connected": true,
#   "db_error": null
# }

# Test FL dashboard (from browser)
echo "Open in browser: https://$SERVICE_URL/fl/dashboard/overview"

# Check FL round 0
curl -s "https://$SERVICE_URL/fl/rounds/0" | jq .
```

---

## Troubleshooting

### Problem: "Docker daemon is not running"

**Solution:** CloudShell has Docker available. Try restarting CloudShell:
```bash
exit  # Close terminal
# Wait 30 seconds, open new CloudShell tab
docker ps  # Should work now
```

---

### Problem: "ECR authentication failed"

**Solution:** Verify AWS credentials:
```bash
aws sts get-caller-identity

# If error, check IAM permissions:
# - ecr:GetAuthorizationToken
# - ecr:GetDownloadUrlForLayer
# - ecr:BatchGetImage
# - ecr:PutImage
# - ecr:InitiateLayerUpload
# - ecr:UploadLayerPart
# - ecr:CompleteLayerUpload
```

---

### Problem: "Database connection refused"

**Solution:** Test database connectivity:
```bash
# Install psql if needed
sudo yum install -y postgresql

# Test connection
psql "$DATABASE_URL" -c "SELECT 1;"

# If fails, check:
# 1. DATABASE_URL is correct: echo "$DATABASE_URL"
# 2. RDS security group allows inbound on port 5432
# 3. DB credentials are valid
```

---

### Problem: "App Runner service not found"

**Solution:** Create it manually first:
```bash
# List existing services
aws apprunner list-services --region "$AWS_REGION" --output table

# If none exist, create in AWS Console:
# 1. App Runner → Services
# 2. Create service
# 3. Source: Container registry
# 4. Use ECR image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/anora-backend:latest
# 5. Port: 8000
# 6. Environment variables: DATABASE_URL, AUTH_JWT_SECRET, AUTH_JWT_EXP_SECONDS, OTP_TTL_SECONDS,
#    OTP_MAX_ATTEMPTS, OTP_DEBUG_ECHO, AWS_SMS_TYPE, AWS_SNS_SMS_SENDER_ID, AWS_REGION, ALLOWED_ORIGINS, etc.
# 7. Create

# Then re-run deploy.sh with --app-runner-arn flag
```

---

### Problem: "Health check fails"

**Solution:**
```bash
# Check App Runner logs
aws logs tail /aws/apprunner/anora-backend --follow --region "$AWS_REGION"

# If database error:
# 1. Verify DATABASE_URL is set correctly
# 2. Check database is running and accessible
# 3. Re-run init_prod_db.py: cd backend && python3 init_prod_db.py

# If connection timeout:
# 1. Check CloudFront/load balancer is responding
# 2. Verify CORS is configured: ALLOWED_ORIGINS env var
```

---

## Manual Deployment (Alternative to Script)

If the script fails, you can run steps manually:

### Manual Step 1: Build & Push to ECR

```bash
# Navigate to repo
cd ~/anora-prod

# Build image
docker build -t anora-backend:latest ./backend/

# Authenticate with ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Tag for ECR
docker tag anora-backend:latest "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/anora-backend:latest"

# Push
docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/anora-backend:latest"
```

### Manual Step 2: Initialize Database

```bash
# Install dependencies
pip install -q psycopg2-binary python-dotenv

# Run init script
cd backend
DATABASE_URL="$DATABASE_URL" python3 init_prod_db.py
```

### Manual Step 3: Update App Runner

```bash
aws apprunner update-service \
  --service-arn "$APP_RUNNER_ARN" \
  --region "$AWS_REGION" \
  --source-configuration "ImageRepository={ImageIdentifier=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/anora-backend:latest,ImageRepositoryType=ECR,ImageConfiguration={Port=8000,RuntimeEnvironmentVariables={DATABASE_URL=$DATABASE_URL,AWS_REGION=$AWS_REGION,AUTH_JWT_SECRET=$AUTH_JWT_SECRET,AUTH_JWT_EXP_SECONDS=$AUTH_JWT_EXP_SECONDS,OTP_TTL_SECONDS=$OTP_TTL_SECONDS,OTP_MAX_ATTEMPTS=$OTP_MAX_ATTEMPTS,OTP_DEBUG_ECHO=$OTP_DEBUG_ECHO,AWS_SMS_TYPE=$AWS_SMS_TYPE,AWS_SNS_SMS_SENDER_ID=$AWS_SNS_SMS_SENDER_ID}}}" \
  --instance-configuration "InstanceRoleArn=$APP_RUNNER_RUNTIME_ROLE_ARN"
```

---

## Monitoring After Deployment

### View Live Logs

```bash
# Stream logs in real-time
aws logs tail /aws/apprunner/anora-backend --follow --region "$AWS_REGION"

# Or view last 100 lines
aws logs tail /aws/apprunner/anora-backend --max-items 100 --region "$AWS_REGION"
```

### Monitor Service Health

```bash
# Every 30 seconds, check service status
watch -n 30 "aws apprunner describe-service --service-arn \"$APP_RUNNER_ARN\" --region \"$AWS_REGION\" --query 'Service.[Status,ServiceUrl]' --output table"

# Press Ctrl+C to stop
```

### Check FL Metrics

```bash
SERVICE_URL=$(aws apprunner describe-service \
  --service-arn "$APP_RUNNER_ARN" \
  --region "$AWS_REGION" \
  --query 'Service.ServiceUrl' \
  --output text)

# Dashboard
curl -s "https://$SERVICE_URL/fl/dashboard/overview" | jq .

# Rounds
curl -s "https://$SERVICE_URL/fl/dashboard/rounds" | jq .

# Clients
curl -s "https://$SERVICE_URL/fl/dashboard/clients" | jq .
```

---

## Next: Deploy Flutter App

Once backend is live:

```bash
# On your local machine (not CloudShell)
cd anora_frontend/anora

# Build release APK (use default API URL)
flutter build apk --release

# Build iOS IPA
flutter build ios --release

# Distribute to Play Store / App Store / TestFlight
```

See `RELEASE_BUILD_GUIDE.md` for details.

---

## Cost & Time Estimates

| Step | Cost | Time |
|------|------|------|
| Docker build & push to ECR | ~$0.10 | 3-5 min |
| App Runner deployment | ~$0.50/day | 5-10 min |
| Database (RDS) | ~$15-30/month | N/A |
| CloudFront CDN | ~$0.085/GB | N/A |
| **Total first deployment** | **~$0.60** | **15-20 min** |
| **Monthly (backend only)** | **~$15-20** | N/A |

---

## Need Help?

- **Deployment verification:** See `DEPLOYMENT_VERIFICATION_GUIDE.md`
- **Architecture:** See `README.md`
- **Flutter builds:** See `RELEASE_BUILD_GUIDE.md`
- **AWS CloudShell docs:** https://docs.aws.amazon.com/cloudshell/latest/userguide/
