/// URLs de los servicios. Desde el emulador de Android, el localhost del PC es 10.0.2.2.
/// Para otro entorno:  flutter run --dart-define=WALLET_URL=https://...
class AppConfig {
  static const walletUrl =
      String.fromEnvironment('WALLET_URL', defaultValue: 'http://10.0.2.2:8001');
  static const bankUrl =
      String.fromEnvironment('BANK_URL', defaultValue: 'http://10.0.2.2:8002');
  static const storeUrl =
      String.fromEnvironment('STORE_URL', defaultValue: 'http://10.0.2.2:8003');
}
