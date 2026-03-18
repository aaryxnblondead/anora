import 'package:local_auth/local_auth.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> canCheckBiometrics() async {
    final supported = await _localAuth.isDeviceSupported();
    if (!supported) {
      return false;
    }
    return _localAuth.canCheckBiometrics;
  }

  Future<bool> authenticate({required String reason}) async {
    final available = await canCheckBiometrics();
    if (!available) {
      return false;
    }

    return _localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }
}
