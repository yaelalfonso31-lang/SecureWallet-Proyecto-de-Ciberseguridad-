import 'dart:core';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class WalletMovement {
  const WalletMovement({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.concept,
    required this.createdAt,
    this.reference,
  });

  factory WalletMovement.fromJson(Map<String, dynamic> json) => WalletMovement(
        id: json['id'] as int,
        kind: json['kind'] as String,
        amountCents: json['amount_cents'] as int,
        balanceAfterCents: json['balance_after_cents'] as int,
        concept: json['concept'] as String,
        reference: json['reference'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String kind; // credit | debit
  final int amountCents;
  final int balanceAfterCents;
  final String concept;
  final String? reference;
  final DateTime createdAt;

  bool get isCredit => kind == 'credit';
}

class WalletTransferResult {
  const WalletTransferResult({
    required this.transferId,
    required this.recipientEmail,
    required this.recipientName,
    required this.amountCents,
    required this.balanceCents,
    required this.note,
    required this.createdAt,
  });

  factory WalletTransferResult.fromJson(Map<String, dynamic> json) =>
      WalletTransferResult(
        transferId: json['transfer_id'] as String,
        recipientEmail: json['recipient_email'] as String,
        recipientName: json['recipient_name'] as String,
        amountCents: json['amount_cents'] as int,
        balanceCents: json['balance_cents'] as int,
        note: (json['note'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String transferId;
  final String recipientEmail;
  final String recipientName;
  final int amountCents;
  final int balanceCents;
  final String note;
  final DateTime createdAt;
}

class WalletLedgerRepository {
  WalletLedgerRepository(this._dio);

  final Dio _dio;

  Future<int> balance() async {
    final res = await _dio.get<dynamic>('/wallet/balance');
    return (res.data as Map<String, dynamic>)['balance_cents'] as int;
  }

  Future<List<WalletMovement>> movements({int limit = 20, int? before}) async {
    final res = await _dio.get<dynamic>(
      '/wallet/movements',
      queryParameters: {'limit': limit, if (before != null) 'before': before},
    );
    return [
      for (final m in res.data as List<dynamic>)
        WalletMovement.fromJson(m as Map<String, dynamic>),
    ];
  }

  Future<int> topup(Map<String, dynamic> signedVoucher) async {
    final res = await _dio.post<dynamic>('/wallet/topup', data: signedVoucher);
    return (res.data as Map<String, dynamic>)['balance_cents'] as int;
  }

  Future<Map<String, dynamic>> withdraw(int amountCents) async {
    final res = await _dio.post<dynamic>(
      '/wallet/withdraw',
      data: {'amount_cents': amountCents},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<WalletTransferResult> transfer({
    required String recipientEmail,
    required int amountCents,
    String note = '',
  }) async {
    final res = await _dio.post<dynamic>(
      '/wallet/transfer',
      data: {
        'recipient_email': recipientEmail.trim(),
        'amount_cents': amountCents,
        'note': note.trim(),
      },
    );
    return WalletTransferResult.fromJson(res.data as Map<String, dynamic>);
  }
}

final walletLedgerRepositoryProvider = Provider<WalletLedgerRepository>(
  (ref) => WalletLedgerRepository(ref.watch(walletDioProvider)),
);

final walletBalanceProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(walletLedgerRepositoryProvider).balance(),
);

final walletMovementsProvider =
    FutureProvider.autoDispose<List<WalletMovement>>(
  (ref) => ref.watch(walletLedgerRepositoryProvider).movements(limit: 30),
);
