import 'package:local_auth/local_auth.dart';

/// Device authentication, including biometrics and the device PIN or password.
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  /// Checks device support; successful authentication also proves enrollment.
  Future<bool> canAuthenticate() => _auth.isDeviceSupported();

  /// Requests device authentication without carrying an attempt across apps.
  Future<bool> authenticate({required String reason}) => _auth.authenticate(
    localizedReason: reason,
    biometricOnly: false,
    persistAcrossBackgrounding: false,
  );

  /// Cancels a native prompt whose result can no longer grant access.
  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {
      // The controller also invalidates the result if native cancellation fails.
    }
  }
}
