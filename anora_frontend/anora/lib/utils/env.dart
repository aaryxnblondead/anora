class Environment {
  static const String appwriteProjectId = '69ed9e800034b5f788e5';
  static const String appwriteProjectName = 'Anora';
  static const String appwritePublicEndpoint = 'https://sgp.cloud.appwrite.io/v1';
}

class Env {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String appwriteProjectId = Environment.appwriteProjectId;
  static const String appwriteProjectName = Environment.appwriteProjectName;
  static const String appwritePublicEndpoint = Environment.appwritePublicEndpoint;

  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String firebaseIosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
}
