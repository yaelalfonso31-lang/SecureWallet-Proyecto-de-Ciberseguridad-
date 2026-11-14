import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage.dart';

/// Id con el que la app se registra ante el Banco (lista permitida en `routers/oauth.py`).
const bankClientId = 'securewallet-mobile';

/// Texto aleatorio base64url sin relleno, a partir de [bytes] bytes de `Random.secure()`.
String randomUrlSafe(int bytes) {
  final random = Random.secure();
  final data = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(data).replaceAll('=', '');
}

/// `code_verifier` de PKCE: 32 bytes aleatorios → 43 caracteres (RFC 7636 pide 43–128).
String generateCodeVerifier() => randomUrlSafe(32);

/// `code_challenge` S256 = BASE64URL(SHA256(verifier)) sin relleno.
Future<String> codeChallengeS256(String verifier) async {
  final hash = await Sha256().hash(ascii.encode(verifier));
  return base64Url.encode(hash.bytes).replaceAll('=', '');
}

/// Token del Banco en Keystore/Keychain, separado del token de la Wallet.
class BankTokenStore {
  BankTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'bank_access_token';

  Future<void> save(String token) => _storage.write(key: _key, value: token);
  Future<String?> read() => _storage.read(key: _key);
  Future<void> delete() => _storage.delete(key: _key);
}

class BankLinkException implements Exception {
  const BankLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Vinculación Wallet ↔ Banco con OAuth2 Authorization Code + PKCE.
class BankAuthRepository {
  BankAuthRepository(this._walletDio, this._bankDio, this._tokens);

  final Dio _walletDio;
  final Dio _bankDio;
  final BankTokenStore _tokens;

  Future<void> link({required String email, required String password}) async {
    final verifier = generateCodeVerifier();
    final challenge = await codeChallengeS256(verifier);
    final state = randomUrlSafe(16);

    // 1) La Wallet firma quién es el usuario; el Banco no confía en un id que mande la app.
    final assertion = await _walletDio.post<dynamic>('/bank-link/assertion');

    // 2) Login en el Banco → código de un solo uso, ligado al challenge.
    final auth = await _bankDio.post<dynamic>('/oauth/authorize', data: {
      'email': email,
      'password': password,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'client_id': bankClientId,
      'state': state,
      'wallet_assertion': assertion.data,
    });
    // `state` debe volver igual: si no, la respuesta no corresponde a esta solicitud.
    if (auth.data['state'] != state) {
      throw const BankLinkException('Respuesta del Banco no válida');
    }

    // 3) Solo quien tiene el verifier puede canjear el código.
    final token = await _bankDio.post<dynamic>('/oauth/token', data: {
      'code': auth.data['code'],
      'code_verifier': verifier,
      'client_id': bankClientId,
    });
    await _tokens.save(token.data['access_token'] as String);
  }

  Future<bool> isLinked() async => (await _tokens.read()) != null;

  Future<void> unlink() => _tokens.delete();
}

final bankTokenStoreProvider = Provider<BankTokenStore>((ref) => BankTokenStore());

final bankAuthRepositoryProvider = Provider<BankAuthRepository>(
  (ref) => BankAuthRepository(
    ref.watch(walletDioProvider),
    ref.watch(bankDioProvider),
    ref.watch(bankTokenStoreProvider),
  ),
);

/// true si hay un token del Banco guardado.
final bankLinkedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(bankAuthRepositoryProvider).isLinked(),
);

/// Cliente HTTP para rutas protegidas del Banco (cuenta, canjes, transferencias).
/// Si el Banco responde 401 (token vencido o inválido), borra el token para pedir
/// de nuevo la vinculación.
final bankAuthDioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(bankTokenStoreProvider);
  final dio = buildDio(AppConfig.bankUrl, ref.watch(secureStoreProvider));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokens.read();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await tokens.delete();
          ref.invalidate(bankLinkedProvider);
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
