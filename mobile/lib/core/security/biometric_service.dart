import 'package:local_auth/local_auth.dart';

/// Re-autenticación con huella/rostro/PIN del dispositivo.
/// Úsala antes de operaciones sensibles (ver tarjeta, firmar un pago).
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    final canCheck = await _auth.canCheckBiometrics;
    final supported = await _auth.isDeviceSupported();
    return canCheck || supported;
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
