import 'package:flutter/foundation.dart';

class Env {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _cloudFallbackApiBaseUrl = String.fromEnvironment(
    'CLOUD_API_BASE_URL',
    defaultValue: 'https://xydctnf6j6.us-east-1.awsapprunner.com',
  );
  static const String _backupCloudApiBaseUrl = String.fromEnvironment(
    'CLOUD_API_BASE_URL_BACKUP',
    defaultValue: '',
  );

  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'us-east-1',
  );
  static const String appRunnerServiceUrl = String.fromEnvironment(
    'APP_RUNNER_SERVICE_URL',
    defaultValue: '',
  );
  static const String s3Bucket = String.fromEnvironment('S3_BUCKET');

  static String get apiBaseUrl {
    final fromApiBase = _definedApiBaseUrl.trim();
    if (fromApiBase.isNotEmpty) {
      final normalized = _normalize(fromApiBase);
      if (_isDisallowedLocalhost(normalized)) {
        return _normalize(_cloudFallbackApiBaseUrl);
      }
      return normalized;
    }

    final fromAppRunner = appRunnerServiceUrl.trim();
    if (fromAppRunner.isNotEmpty) {
      final normalized = _normalize(fromAppRunner);
      if (_isDisallowedLocalhost(normalized)) {
        return _normalize(_cloudFallbackApiBaseUrl);
      }
      return normalized;
    }

    if (kDebugMode) {
      return 'http://localhost:8000';
    }
    return _normalize(_cloudFallbackApiBaseUrl);
  }

  static String? get backupApiBaseUrl {
    final raw = _backupCloudApiBaseUrl.trim();
    if (raw.isEmpty) {
      return null;
    }
    final normalized = _normalize(raw);
    final parsed = Uri.tryParse(normalized);
    if (parsed == null || parsed.host.trim().isEmpty) {
      return null;
    }
    return normalized;
  }

  static String _normalize(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  static bool _isDisallowedLocalhost(String url) {
    if (kDebugMode) {
      return false;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return false;
    }
    final host = parsed.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}
