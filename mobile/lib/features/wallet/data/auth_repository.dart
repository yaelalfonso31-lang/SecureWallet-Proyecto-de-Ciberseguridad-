import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage.dart';
import 'wallet_models.dart';

class AuthRepository {
  AuthRepository(this._dio, this._store);

  final Dio _dio;
  final SecureStore _store;

  Future<void> register({
    required String email,
    required String fullName,
    required String password,
  }) async {
    await _dio.post<dynamic>('/auth/register', data: {
      'email': email,
      'full_name': fullName,
      'password': password,
    });
  }

  Future<void> login(String email, String password) async {
    final res = await _dio.post<dynamic>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    await _store.saveToken(res.data['access_token'] as String);
  }

  /// Datos del usuario autenticado (GET /auth/me).
  Future<UserProfile> fetchProfile() async {
    final res = await _dio.get<dynamic>('/auth/me');
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
  }

  /// true si hay un token guardado en el almacén seguro del teléfono.
  Future<bool> hasSession() async => (await _store.readToken()) != null;

  Future<void> logout() => _store.clear();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(walletDioProvider), ref.watch(secureStoreProvider)),
);

final profileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(authRepositoryProvider).fetchProfile(),
);
