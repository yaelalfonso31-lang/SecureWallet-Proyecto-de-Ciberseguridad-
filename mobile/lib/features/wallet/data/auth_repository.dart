import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/secure_storage.dart';

class AuthRepository {
  AuthRepository(this._dio, this._store);

  final Dio _dio;
  final SecureStore _store;

  Future<void> register({
    required String email,
    required String fullName,
    required String password,
  }) async {
    await _dio.post('/auth/register', data: {
      'email': email,
      'full_name': fullName,
      'password': password,
    });
  }

  Future<void> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    await _store.saveToken(res.data['access_token'] as String);
  }

  Future<void> logout() => _store.clear();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(walletDioProvider), ref.watch(secureStoreProvider)),
);
