import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../security/secure_storage.dart';

/// Crea un cliente HTTP. Si `auth` es true, agrega el token JWT guardado de forma segura.
///
/// TODO equipo de seguridad: certificate pinning (comparar el hash del certificado del
/// servidor) y rechazar HTTP en producción.
Dio buildDio(String baseUrl, SecureStore store, {bool auth = false}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );
  if (auth) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await store.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }
  return dio;
}

/// Convierte un error de Dio en un mensaje legible para el usuario.
String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'No se pudo conectar con el servidor';
    }
  }
  return 'Ocurrió un error inesperado';
}

final walletDioProvider = Provider<Dio>(
  (ref) => buildDio(AppConfig.walletUrl, ref.watch(secureStoreProvider), auth: true),
);
final bankDioProvider = Provider<Dio>(
  (ref) => buildDio(AppConfig.bankUrl, ref.watch(secureStoreProvider)),
);
final storeDioProvider = Provider<Dio>(
  (ref) => buildDio(AppConfig.storeUrl, ref.watch(secureStoreProvider)),
);
