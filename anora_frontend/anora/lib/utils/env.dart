class Env {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'us-east-1',
  );
  static const String appRunnerServiceUrl = String.fromEnvironment('APP_RUNNER_SERVICE_URL');
  static const String s3Bucket = String.fromEnvironment('S3_BUCKET');
}
