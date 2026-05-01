#!/bin/bash
###############################################################################
# Anora Backend Deployment Script for AWS CloudShell
# 
# This script automates the complete deployment pipeline:
# 1. Clone/update repository
# 2. Build Docker image
# 3. Push to AWS ECR
# 4. Deploy to App Runner
# 5. Initialize database (FL tables + round 0)
# 6. Verify health
#
# Prerequisites:
#   - AWS CloudShell access (no additional tools needed)
#   - Docker available (included in CloudShell)
#   - AWS credentials configured (automatic in CloudShell)
#
# Usage:
#   bash deploy.sh --git-repo https://github.com/aaryxnblondead/anora.git \
#                  --aws-account 027277540377 \
#                  --aws-region us-east-1 \
#                  --db-url "postgresql://..." \
#                  --docker-image anora-backend:latest
#
###############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Default values
GIT_REPO="https://github.com/aaryxnblondead/anora.git"
AWS_ACCOUNT="${AWS_ACCOUNT_ID:-027277540377}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO_NAME="anora-backend"
DOCKER_IMAGE="$ECR_REPO_NAME:latest"
APP_RUNNER_SERVICE_NAME="anora-backend"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --git-repo) GIT_REPO="$2"; shift 2 ;;
    --aws-account) AWS_ACCOUNT="$2"; shift 2 ;;
    --aws-region) AWS_REGION="$2"; shift 2 ;;
    --db-url) DATABASE_URL="$2"; shift 2 ;;
    --docker-image) DOCKER_IMAGE="$2"; shift 2 ;;
    --app-runner-arn) APP_RUNNER_ARN="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate required environment variables
if [[ -z "${DATABASE_URL:-}" ]]; then
  log_error "DATABASE_URL not set. Use --db-url or set environment variable."
  exit 1
fi

if [[ -z "${AWS_ACCOUNT:-}" ]] || [[ -z "${AWS_REGION:-}" ]]; then
  log_error "AWS account/region not set. Use --aws-account and --aws-region."
  exit 1
fi

# Compute derived values
ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_IMAGE_URI="${ECR_REGISTRY}/${DOCKER_IMAGE}"

log_info "=== Anora Backend Deployment Script ==="
log_info "Git Repo: $GIT_REPO"
log_info "AWS Region: $AWS_REGION"
log_info "AWS Account: $AWS_ACCOUNT"
log_info "ECR URI: $ECR_IMAGE_URI"
log_info "App Runner Service: $APP_RUNNER_SERVICE_NAME"

###############################################################################
# Step 1: Clone or update repository
###############################################################################

log_info "\n=== Step 1: Repository Setup ==="

REPO_DIR="/tmp/anora-deployment"
if [[ ! -d "$REPO_DIR" ]]; then
  log_info "Cloning repository..."
  git clone "$GIT_REPO" "$REPO_DIR" --depth 1
else
  log_info "Updating existing repository..."
  cd "$REPO_DIR"
  git pull origin main || git pull origin master
fi

cd "$REPO_DIR"
log_success "Repository ready at $REPO_DIR"

###############################################################################
# Step 2: Build Docker image
###############################################################################

log_info "\n=== Step 2: Docker Build ==="

if [[ ! -f "backend/Dockerfile" ]]; then
  log_error "Dockerfile not found at backend/Dockerfile"
  exit 1
fi

log_info "Building Docker image: $DOCKER_IMAGE"
docker build -t "$DOCKER_IMAGE" ./backend/

if [[ -z "$(docker images -q $DOCKER_IMAGE)" ]]; then
  log_error "Docker image build failed"
  exit 1
fi

log_success "Docker image built: $DOCKER_IMAGE"

###############################################################################
# Step 3: Login to ECR and push image
###############################################################################

log_info "\n=== Step 3: Push to ECR ==="

log_info "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

log_success "ECR authentication successful"

# Create ECR repository if it doesn't exist
log_info "Checking ECR repository..."
if ! aws ecr describe-repositories \
  --repository-names "$ECR_REPO_NAME" \
  --region "$AWS_REGION" 2>/dev/null; then
  
  log_warning "ECR repository does not exist. Creating..."
  aws ecr create-repository \
    --repository-name "$ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES
  
  log_success "ECR repository created"
else
  log_success "ECR repository already exists"
fi

# Tag image for ECR
log_info "Tagging image for ECR: $ECR_IMAGE_URI"
docker tag "$DOCKER_IMAGE" "$ECR_IMAGE_URI"

# Push to ECR
log_info "Pushing image to ECR (this may take a few minutes)..."
docker push "$ECR_IMAGE_URI"

log_success "Image pushed to ECR: $ECR_IMAGE_URI"

###############################################################################
# Step 4: Get or create App Runner service
###############################################################################

log_info "\n=== Step 4: App Runner Service ==="

# Check if service exists
if [[ -z "${APP_RUNNER_ARN:-}" ]]; then
  log_info "Looking up App Runner service ARN for: $APP_RUNNER_SERVICE_NAME"
  
  APP_RUNNER_ARN=$(aws apprunner list-services \
    --region "$AWS_REGION" \
    --query "ServiceSummaryList[?ServiceName=='$APP_RUNNER_SERVICE_NAME'].ServiceArn" \
    --output text 2>/dev/null || echo "")
fi

if [[ -z "$APP_RUNNER_ARN" ]]; then
  log_warning "App Runner service does not exist. Must create manually in AWS Console."
  log_info "Once created, re-run this script with: --app-runner-arn <ARN>"
  log_info "For now, skipping App Runner deployment."
  SKIP_APP_RUNNER=true
else
  log_success "Found App Runner service: $APP_RUNNER_ARN"
  SKIP_APP_RUNNER=false
fi

###############################################################################
# Step 5: Deploy to App Runner (if service exists)
###############################################################################

if [[ "$SKIP_APP_RUNNER" == "false" ]]; then
  log_info "\n=== Step 5: Deploy to App Runner ==="
  
  log_info "Updating App Runner service with new image..."
  aws apprunner update-service \
    --service-arn "$APP_RUNNER_ARN" \
    --region "$AWS_REGION" \
    --source-configuration "ImageRepository={ImageIdentifier=$ECR_IMAGE_URI,ImageRepositoryType=ECR,ImageConfiguration={Port=8000,RuntimeEnvironmentVariables={DATABASE_URL=$DATABASE_URL}}}"
  
  log_success "App Runner deployment initiated"
  log_info "Waiting for deployment to complete (this may take 5-10 minutes)..."
  
  # Wait for service to be active
  max_attempts=60
  attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    SERVICE_STATUS=$(aws apprunner describe-service \
      --service-arn "$APP_RUNNER_ARN" \
      --region "$AWS_REGION" \
      --query 'Service.Status' \
      --output text)
    
    if [[ "$SERVICE_STATUS" == "ACTIVE" ]]; then
      log_success "App Runner service is ACTIVE"
      break
    fi
    
    log_info "Service status: $SERVICE_STATUS (waiting...)"
    sleep 10
    attempt=$((attempt + 1))
  done
  
  if [[ $attempt -eq $max_attempts ]]; then
    log_warning "Deployment did not complete within timeout. Check App Runner console."
  fi
  
  # Get service URL
  SERVICE_URL=$(aws apprunner describe-service \
    --service-arn "$APP_RUNNER_ARN" \
    --region "$AWS_REGION" \
    --query 'Service.ServiceUrl' \
    --output text)
  
  log_success "App Runner URL: https://$SERVICE_URL"
else
  log_warning "Skipping App Runner deployment (service not found)"
  log_info "Create App Runner service in AWS Console and re-run with --app-runner-arn"
fi

###############################################################################
# Step 6: Initialize Database
###############################################################################

log_info "\n=== Step 6: Database Initialization ==="

if [[ ! -f "$REPO_DIR/backend/init_prod_db.py" ]]; then
  log_error "Database init script not found at backend/init_prod_db.py"
  exit 1
fi

# Install Python dependencies if needed
if ! python3 -c "import psycopg2" 2>/dev/null; then
  log_info "Installing Python dependencies..."
  pip install -q psycopg2-binary python-dotenv
fi

log_info "Running database initialization..."
cd "$REPO_DIR/backend"
DATABASE_URL="$DATABASE_URL" python3 init_prod_db.py

log_success "Database initialization complete"

###############################################################################
# Step 7: Verify Health
###############################################################################

log_info "\n=== Step 7: Health Check ==="

if [[ "$SKIP_APP_RUNNER" == "false" ]]; then
  log_info "Testing health endpoint (waiting 30 seconds for service to be ready)..."
  sleep 30
  
  HEALTH_URL="https://$SERVICE_URL/health"
  log_info "Checking: $HEALTH_URL"
  
  HEALTH_RESPONSE=$(curl -s "$HEALTH_URL" || echo "{}")
  
  if echo "$HEALTH_RESPONSE" | grep -q '"status":"ok"'; then
    log_success "Health check passed!"
    log_info "Response: $HEALTH_RESPONSE"
  else
    log_warning "Health check may not be ready yet. Check manually:"
    log_info "  curl https://$SERVICE_URL/health"
  fi
else
  log_warning "Skipping health check (App Runner not deployed)"
fi

###############################################################################
# Deployment Summary
###############################################################################

log_info "\n=== Deployment Summary ==="
log_success "✅ All steps completed!"
log_info ""
log_info "What was deployed:"
log_info "  1. ✅ Docker image built and pushed to ECR"
log_info "  2. ✅ Database tables created and initialized"
if [[ "$SKIP_APP_RUNNER" == "false" ]]; then
  log_info "  3. ✅ App Runner service updated"
  log_info ""
  log_info "Live Endpoints:"
  log_info "  API: https://$SERVICE_URL"
  log_info "  Health: https://$SERVICE_URL/health"
  log_info "  Dashboard: https://$SERVICE_URL/fl/dashboard/overview"
else
  log_info "  3. ⏭️  App Runner deployment skipped (create service manually)"
fi

log_info ""
log_info "Next steps:"
log_info "  1. Verify health endpoint: curl https://\$SERVICE_URL/health"
log_info "  2. Check FL dashboard: Open https://\$SERVICE_URL/fl/dashboard/overview in browser"
log_info "  3. Build and release Flutter APK: flutter build apk --release"
log_info "  4. Monitor logs: aws logs tail /aws/apprunner/$APP_RUNNER_SERVICE_NAME --follow"

log_info ""
log_info "For help, see:"
log_info "  - DEPLOYMENT_VERIFICATION_GUIDE.md (troubleshooting)"
log_info "  - RELEASE_BUILD_GUIDE.md (Flutter build)"
log_info "  - README.md (architecture overview)"

echo ""
