class Env {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
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
      return _normalize(fromApiBase);
    }

    final fromAppRunner = appRunnerServiceUrl.trim();
    if (fromAppRunner.isNotEmpty) {
      return _normalize(fromAppRunner);
    }

    return 'http://localhost:8000';
  }

  static String _normalize(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }
}
