import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.event,
    required this.detail,
    required this.prevHash,
    required this.hash,
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] as int,
        event: json['event'] as String,
        detail: (json['detail'] as String?) ?? '',
        prevHash: json['prev_hash'] as String,
        hash: json['hash'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String event;
  final String detail;
  final String prevHash;
  final String hash;
  final DateTime createdAt;
}

class AuditChainReport {
  const AuditChainReport({
    required this.chainValid,
    required this.totalRecords,
    required this.entries,
  });

  factory AuditChainReport.fromJson(Map<String, dynamic> json) =>
      AuditChainReport(
        chainValid: json['chain_valid'] as bool,
        totalRecords: json['total_records'] as int,
        entries: [
          for (final e in json['entries'] as List<dynamic>)
            AuditEntry.fromJson(e as Map<String, dynamic>),
        ],
      );

  final bool chainValid;
  final int totalRecords;
  final List<AuditEntry> entries;
}

class TotpSetupData {
  const TotpSetupData({required this.secret, required this.provisioningUri});

  factory TotpSetupData.fromJson(Map<String, dynamic> json) => TotpSetupData(
        secret: json['secret'] as String,
        provisioningUri: json['provisioning_uri'] as String,
      );

  final String secret;
  final String provisioningUri;
}

class SecurityRepository {
  SecurityRepository(this._dio);

  final Dio _dio;

  Future<AuditChainReport> auditLog({int limit = 30}) async {
    final res = await _dio.get<dynamic>(
      '/security/audit',
      queryParameters: {'limit': limit},
    );
    return AuditChainReport.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TotpSetupData> setup2fa() async {
    final res = await _dio.post<dynamic>('/security/2fa/setup');
    return TotpSetupData.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> enable2fa(String code) async {
    await _dio
        .post<dynamic>('/security/2fa/enable', data: {'code': code.trim()});
  }

  Future<void> disable2fa(String code) async {
    await _dio
        .post<dynamic>('/security/2fa/disable', data: {'code': code.trim()});
  }
}

final securityRepositoryProvider = Provider<SecurityRepository>(
  (ref) => SecurityRepository(ref.watch(walletDioProvider)),
);

final auditChainProvider = FutureProvider.autoDispose<AuditChainReport>(
  (ref) => ref.watch(securityRepositoryProvider).auditLog(),
);
