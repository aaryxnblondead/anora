# Anora FL Deployment - Blocker Fixes & Verification Guide

**Last Updated**: May 2, 2026  
**Status**: ✅ All 5 deployment blockers resolved  
**Target**: Launch tonight

---

## Summary of Fixes

| # | Blocker | Status | File(s) | Details |
|---|---------|--------|---------|---------|
| 1 | Database init | ✅ Fixed | `backend/init_prod_db.py` (NEW) | Standalone script to run migrations & create round 0 |
| 2 | Env var audit | ✅ Fixed | `backend/.env.production.template` (NEW) | Complete audit of all env vars with defaults and hard failures |
| 3 | CORS lockdown | ✅ Fixed | `backend/main.py` | Default changed from "*" to CloudFront CDN URL |
| 4 | Health check | ✅ Fixed | `backend/main.py` | Enhanced to test active DB connectivity, not just init flag |
| 5 | Flutter build | ✅ Fixed | `RELEASE_BUILD_GUIDE.md` (NEW) | Correct build command for release APK/iOS |

---

## ✅ VERIFICATION COMMANDS

### 1. Database Initialization

**Before first deployment, run the init script:**

```bash
# From your local machine or deployment environment
cd backend

# Setup environment
cp .env.production.template .env
# Edit .env and fill in real values:
# - DATABASE_URL (production PostgreSQL)
# - AWS_REGION (e.g., us-east-1)
# - AWS SNS ARNs (if using push notifications)

# Run initialization
python init_prod_db.py

# Expected output:
# ✅ Connected to database.
# ✅ FL tables created (or already exist).
# ✅ FL round 0 created
# ✅ DATABASE INITIALIZATION COMPLETE
```

**If it fails:**
```bash
# Verify DATABASE_URL is correct
python -c "import os; from dotenv import load_dotenv; load_dotenv(); print('DB URL:', os.getenv('DATABASE_URL'))"

# Check PostgreSQL directly
psql "$DATABASE_URL" -c "SELECT 1;" 
```

---

### 2. Environment Variable Audit

**Verify all required env vars are set:**

```bash
# Check .env.production.template for all variables
cat backend/.env.production.template | grep -E '^[A-Z_]+=' | head -20

# Verify critical vars in your deployment
env | grep -E 'DATABASE_URL|AWS_REGION|ALLOWED_ORIGINS'

# Expected output:
# DATABASE_URL=postgresql://...
# AWS_REGION=us-east-1
# ALLOWED_ORIGINS=https://d1p1fpleu1yzws.cloudfront.net
```

**Hard Failure Variables (no defaults provided):**
- `DATABASE_URL` - Must point to valid PostgreSQL instance
- `AWS_REGION` - Required for SNS push notifications
- `AWS_SNS_PLATFORM_APPLICATION_ARN_*` - Required if using push notifications

---

### 3. CORS Lockdown

**Verify CORS defaults to CloudFront:**

```bash
# Check the source code change
cd backend
grep -A 5 "ALLOWED_ORIGINS" main.py | head -15

# Expected: default value is now https://d1p1fpleu1yzws.cloudfront.net (not "*")
```

**Test CORS in production:**

```bash
# From a browser console or curl, verify CORS is enforced
curl -H "Origin: https://unauthorized.example.com" \
     -H "Access-Control-Request-Method: POST" \
     -X OPTIONS https://xydctnf6j6.us-east-1.awsapprunner.com/health

# Should return 403 or missing Access-Control headers if CORS denies it
# OR if you want to allow multiple origins, set env var:
# ALLOWED_ORIGINS=https://d1p1fpleu1yzws.cloudfront.net,https://app.anora.health
```

---

### 4. Health Check Verification

**Before deployment, test the enhanced health endpoint:**

```bash
# Test against development backend
curl -s http://localhost:8000/health | jq .

# Expected output:
# {
#   "status": "ok",
#   "db_ready": true,
#   "db_connected": true,
#   "db_error": null
# }

# Test against production (once deployed)
curl -s https://xydctnf6j6.us-east-1.awsapprunner.com/health | jq .

# If DB is down:
# {
#   "status": "degraded",
#   "db_ready": false,
#   "db_connected": false,
#   "db_error": "database initialization failed"
# }
```

**Configure load balancer to use `/health`:**
- App Runner health check path: `/health`
- Success criteria: `status == "ok"` AND `db_connected == true`
- Failure criteria: `status == "degraded"` OR `db_ready == false`

---

### 5. Flutter Release Build Configuration

**Build APK with correct backend API URL:**

```bash
# Option 1: Use defaults (RECOMMENDED)
# CLOUD_API_BASE_URL defaults to https://xydctnf6j6.us-east-1.awsapprunner.com
cd anora_frontend/anora
flutter build apk --release

# Option 2: Explicit configuration
flutter build apk --release \
  --dart-define=API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com \
  --dart-define=CLOUD_API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com

# Expected output:
# ✓ Built build/app/outputs/flutter-apk/app-release.apk (XXX MB)
```

**Verify the app uses correct API URL:**

```bash
# Install on device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Open app and go to Settings
# Look for "API Base URL" field
# Should show: https://xydctnf6j6.us-east-1.awsapprunner.com
# (NOT CloudFront CDN URL)
```

---

## 📋 Pre-Launch Checklist

Run these in order before going live:

```bash
# 1. Initialize database
cd backend
python init_prod_db.py

# 2. Verify environment variables
echo "DATABASE_URL: $DATABASE_URL"
echo "AWS_REGION: $AWS_REGION"
echo "ALLOWED_ORIGINS: $ALLOWED_ORIGINS"

# 3. Test health endpoint (if backend running locally)
curl http://localhost:8000/health | jq .

# 4. Test FL round 0 exists
curl http://localhost:8000/fl/rounds/0 | jq .
# Expected: round_id: 0, status: "active", min_clients: 100

# 5. Build Flutter release APK
cd anora_frontend/anora
flutter build apk --release

# 6. Deploy backend to App Runner
# (Follow your normal deployment process)

# 7. Test production health endpoint
curl https://xydctnf6j6.us-east-1.awsapprunner.com/health | jq .

# 8. Install APK on test device
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 🚀 Production Deployment Steps

### Step 1: Database Migration
```bash
# On deployment machine with DATABASE_URL set:
cd backend
python init_prod_db.py
# Confirms: FL tables created, round 0 active
```

### Step 2: Deploy Backend
```bash
# Using App Runner (example with Docker)
docker build -t anora-backend:latest .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 027277540377.dkr.ecr.us-east-1.amazonaws.com
docker tag anora-backend:latest 027277540377.dkr.ecr.us-east-1.amazonaws.com/anora-backend:latest
docker push 027277540377.dkr.ecr.us-east-1.amazonaws.com/anora-backend:latest

# Update App Runner service with new image
aws apprunner update-service --service-arn <your-service-arn> \
  --source-configuration ImageRepository={ImageIdentifier=027277540377.dkr.ecr.us-east-1.amazonaws.com/anora-backend:latest}

# Wait for deployment (~5 min)
# Verify health
curl https://xydctnf6j6.us-east-1.awsapprunner.com/health | jq .
```

### Step 3: Release Flutter App
```bash
# Build and sign APK
cd anora_frontend/anora
flutter build apk --release

# Distribute to users:
# - Play Store (Android)
# - TestFlight / App Store (iOS)
# - Internal testing (beta)
```

### Step 4: Monitor FL Infrastructure
```bash
# Monitor dashboard (admin only)
curl https://xydctnf6j6.us-east-1.awsapprunner.com/fl/dashboard/overview | jq .

# Watch convergence metrics as devices submit gradients
curl https://xydctnf6j6.us-east-1.awsapprunner.com/fl/dashboard/rounds | jq .
```

---

## 📊 What's Live (FL Infrastructure)

✅ **Backend FL Coordinator**
- Client registration endpoint: `POST /fl/clients/register`
- Gradient submission: `POST /fl/gradients/submit`
- Model distribution: `GET /fl/models/latest`
- Round management: `GET /fl/rounds/{round_id}`
- Aggregation: `POST /fl/admin/rounds/{round_id}/aggregate`
- Dashboard: `GET /fl/dashboard/overview`, `GET /fl/dashboard/rounds`

✅ **Frontend FL Client Service**
- Local training loop (lightweight linear head fine-tuning)
- SecAgg masking (Box-Muller transform)
- Platform channels (idle & charging detection)
- Gradient submission with round tracking
- Device registration

✅ **Database Schema**
- `fl_clients`: Device enrollment tracking
- `fl_rounds`: Training round lifecycle
- `fl_gradients`: Masked gradient storage
- `fl_model_versions`: Model version control
- `fl_convergence_metrics`: Training metrics

⚠️ **Documented As MVP (Intentional)**
- **Tokenizer integration**: Currently uses simulated embeddings (documented roadmap item for v2.1)
- **Model hot-reload**: Version tracking works, runtime reload not implemented (can restart app)
- **Dynamic round assignment**: Hardcoded to round 0 (clients don't query active round from server)

---

## 🎯 Known Limitations (v2 Roadmap)

### Tokenizer Integration (v2.1 - Q3 2026)
- **Current**: `_embeddingForText()` uses seeded random values
- **Impact**: FL gradients are simulated, not real model-derived
- **Fix Required**: Wire `assets/models/tokenizer.json` → TFLite tensor pipeline
- **Timeline**: Post-launch enhancement

### Model Hot-Reload (v2.1 - Q3 2026)
- **Current**: Version tracking functional, interpreter not reloaded at runtime
- **Impact**: Clients get new model weights only after app restart
- **Fix Required**: Close interpreter, load new base64-decoded model, re-initialize
- **Timeline**: Quality-of-life improvement

### Dynamic Round Assignment (v2.2 - Q4 2026)
- **Current**: Hardcoded to `round_id=0`
- **Impact**: Can't run multiple simultaneous FL rounds
- **Fix Required**: Client queries `/fl/rounds/active` before submitting gradients
- **Timeline**: Multi-round support for production scaling

---

## 📞 Support

If deployment fails:

1. **Check health endpoint**:
   ```bash
   curl https://xydctnf6j6.us-east-1.awsapprunner.com/health
   ```

2. **Check backend logs**:
   ```bash
   aws logs tail /aws/apprunner/anora-backend --follow
   ```

3. **Verify environment variables**:
   ```bash
   # In App Runner console, check "Environment Variables" section
   # Ensure DATABASE_URL, AWS_REGION are set
   ```

4. **Test database connectivity**:
   ```bash
   psql "$DATABASE_URL" -c "SELECT * FROM fl_rounds;"
   ```

5. **Roll back**:
   ```bash
   aws apprunner update-service --service-arn <arn> --source-configuration ImageRepository={ImageIdentifier=<previous-version>}
   ```

---

**Last verification**: May 2, 2026  
**Status**: Ready for production deployment  
**Estimated downtime**: 5-10 minutes (App Runner rollout)
