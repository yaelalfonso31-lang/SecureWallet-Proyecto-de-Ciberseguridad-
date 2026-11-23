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

  Future<void> login(String email, String password, {String? totpCode}) async {
    final res = await _dio.post<dynamic>('/auth/login', data: {
      'email': email,
      'password': password,
      if (totpCode != null && totpCode.trim().isNotEmpty)
        'totp_code': totpCode.trim(),
    });
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

// 1. En el modelo de perfil (UserProfile / UserOut):
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.totpEnabled = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        totpEnabled: (json['totp_enabled'] as bool?) ?? false,
      );

  final String id;
  final String email;
  final String fullName;
  final bool totpEnabled;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
      ref.watch(walletDioProvider), ref.watch(secureStoreProvider)),
);

final profileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(authRepositoryProvider).fetchProfile(),
);
