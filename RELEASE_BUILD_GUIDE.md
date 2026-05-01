# Flutter Release Build Configuration for Anora

## Current Issue
The previous build command used an incorrect API URL:
```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://d1p1fpleu1yzws.cloudfront.net \
  --dart-define=CLOUD_API_BASE_URL_BACKUP=https://xydctnf6j6.us-east-1.awsapprunner.com
```

**Problem**: 
- `API_BASE_URL=https://d1p1fpleu1yzws.cloudfront.net` points to CloudFront CDN (static frontend files)
- Backend API requests will fail because CloudFront doesn't host the `/fl/*` endpoints
- Should use App Runner URL instead

## Correct Release Build Configuration

### Option 1: Use Default (Recommended for Production)
Let the app use the default backend API URL (App Runner):

```bash
# Build for Android (APK)
flutter build apk --release

# Build for iOS
flutter build ios --release
```

**Why this works:**
- `CLOUD_API_BASE_URL` defaults to `https://xydctnf6j6.us-east-1.awsapprunner.com`
- In release mode, if `API_BASE_URL` is not set, it uses the default Cloud URL
- App Router connects to backend API automatically

### Option 2: Explicit Configuration (Alternative)
Explicitly set the backend API URL:

```bash
# Build for Android (APK)
flutter build apk --release \
  --dart-define=API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com \
  --dart-define=CLOUD_API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com

# Build for iOS  
flutter build ios --release \
  --dart-define=API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com \
  --dart-define=CLOUD_API_BASE_URL=https://xydctnf6j6.us-east-1.awsapprunner.com
```

## API URL Resolution in Release Builds

The Dart `Env.apiBaseUrl` getter follows this priority in **release mode** (`kDebugMode = false`):

1. **API_BASE_URL** env var (if set and not localhost)
2. **APP_RUNNER_SERVICE_URL** env var (if set and not localhost)
3. **CLOUD_API_BASE_URL** env var (if set, defaults to: `https://xydctnf6j6.us-east-1.awsapprunner.com`)
4. Falls back to normalized CLOUD_API_BASE_URL default

## What Each URL Is For

| URL | Purpose | Example |
|-----|---------|---------|
| **API_BASE_URL** | Primary backend API endpoint | `https://xydctnf6j6.us-east-1.awsapprunner.com` |
| **CLOUD_API_BASE_URL** | Fallback backend API endpoint | `https://xydctnf6j6.us-east-1.awsapprunner.com` |
| **CloudFront CDN** | Frontend static files (HTML, JS, CSS) | `https://d1p1fpleu1yzws.cloudfront.net` |

## Verification Commands

### Test APK Installation
```bash
# Install on connected Android device/emulator
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Verify API connectivity (device must be running the app)
adb shell am start -n com.anorahealth.anora/.MainActivity
```

### Test iOS Build
```bash
# Archive for release
flutter build ios --release

# Verify build succeeded
ls -lh build/ios/iphoneos/Runner.app
```

### Verify Backend Connectivity
Once app is installed and running:

```bash
# From your development machine, verify backend is reachable
curl -I https://xydctnf6j6.us-east-1.awsapprunner.com/health

# Response should be:
# HTTP/1.1 200 OK
# {"status":"ok","db_ready":true,"db_connected":true}
```

## Deployment Checklist

- [ ] Backend is deployed and healthy (`/health` returns 200 with `db_ready: true`)
- [ ] Flutter app built with correct API URL
- [ ] CORS is configured to allow your CloudFront domain
- [ ] Android APK signed and uploaded to Play Store or deployed to devices
- [ ] iOS IPA signed and uploaded to App Store or deployed to TestFlight
- [ ] Test device registration: Open app → Settings → Verify device ID is generated
- [ ] Test gradient submission: Device sends masked gradient → Check backend logs

## Troubleshooting

### APK Reports "Cannot reach server"
- Verify backend health: `curl https://xydctnf6j6.us-east-1.awsapprunner.com/health`
- Check app's actual API URL: Open app → Settings → Search for "API" override field
- If overridden, clear it and restart app

### iOS App Crashes on FL Endpoint
- Verify Flutter build used correct API URL (check env.dart apiBaseUrl getter)
- Check App Transport Security in iOS (localhost URLs blocked in release)
- Ensure HTTPS URLs are used (no http:// in production)

### Build Fails
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --release
```
