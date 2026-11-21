import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class WalletLedgerMovement {
  const WalletLedgerMovement({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.concept,
    required this.createdAt,
  });

  factory WalletLedgerMovement.fromJson(Map<String, dynamic> json) =>
      WalletLedgerMovement(
        id: json['id'] as int,
        kind: json['kind'] as String,
        amountCents: json['amount_cents'] as int,
        balanceAfterCents: json['balance_after_cents'] as int,
        concept: json['concept'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String kind; // credit | debit
  final int amountCents;
  final int balanceAfterCents;
  final String concept;
  final DateTime createdAt;

  bool get isCredit => kind == 'credit';
}

/// Saldo real de la Wallet (backend `/wallet/*`).
class WalletLedgerRepository {
  WalletLedgerRepository(this._dio);

  final Dio _dio;

  Future<int> balance() async {
    final res = await _dio.get<dynamic>('/wallet/balance');
    return (res.data as Map<String, dynamic>)['balance_cents'] as int;
  }

  Future<List<WalletLedgerMovement>> movements(
      {int limit = 20, int? before}) async {
    final res = await _dio.get<dynamic>(
      '/wallet/movements',
      queryParameters: {'limit': limit, if (before != null) 'before': before},
    );
    return [
      for (final m in res.data as List<dynamic>)
        WalletLedgerMovement.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// Entrega a la Wallet el comprobante firmado por el Banco. Devuelve el saldo nuevo.
  /// Es idempotente: reenviar el mismo comprobante no abona dos veces.
  Future<int> topup(Map<String, dynamic> signedVoucher) async {
    final res = await _dio.post<dynamic>('/wallet/topup', data: signedVoucher);
    return (res.data as Map<String, dynamic>)['balance_cents'] as int;
  }

  /// Descuenta el saldo y devuelve el comprobante `{voucher, signature}` firmado por la Wallet.
  Future<Map<String, dynamic>> withdraw(int amountCents) async {
    final res = await _dio
        .post<dynamic>('/wallet/withdraw', data: {'amount_cents': amountCents});
    return Map<String, dynamic>.from(res.data as Map);
  }
}

final walletLedgerRepositoryProvider = Provider<WalletLedgerRepository>(
  (ref) => WalletLedgerRepository(ref.watch(walletDioProvider)),
);

/// Saldo real de la Wallet. Falla si el backend no tiene `/wallet/balance` (versión antigua).
final walletBalanceProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(walletLedgerRepositoryProvider).balance(),
);
