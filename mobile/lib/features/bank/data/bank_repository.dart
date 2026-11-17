import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/data/wallet_ledger_repository.dart';
import 'bank_auth_repository.dart';

class BankAccount {
  const BankAccount({
    required this.numberMasked,
    required this.balanceCents,
    required this.status,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
        numberMasked: json['account_number_masked'] as String,
        balanceCents: json['balance_cents'] as int,
        status: json['status'] as String,
      );

  final String numberMasked;
  final int balanceCents;
  final String status;

  bool get isFrozen => status == 'frozen';
}

class BankMovement {
  const BankMovement({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.concept,
    required this.createdAt,
  });

  factory BankMovement.fromJson(Map<String, dynamic> json) => BankMovement(
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

class BankPromotion {
  const BankPromotion({
    required this.id,
    required this.title,
    required this.description,
    required this.discountPercent,
    this.validUntil,
  });

  factory BankPromotion.fromJson(Map<String, dynamic> json) => BankPromotion(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String,
        discountPercent: json['discount_percent'] as int,
        validUntil: json['valid_until'] == null ? null : DateTime.parse(json['valid_until'] as String),
      );

  final int id;
  final String title;
  final String description;
  final int discountPercent;
  final DateTime? validUntil;
}

/// Canje propio de una promoción: `pending` se aplicará en la próxima compra; `used` ya se usó.
class BankRedemption {
  const BankRedemption({
    required this.promotionId,
    required this.title,
    required this.discountPercent,
    required this.status,
    this.usedInOrderId,
  });

  factory BankRedemption.fromJson(Map<String, dynamic> json) => BankRedemption(
        promotionId: json['promotion_id'] as int,
        title: json['title'] as String,
        discountPercent: json['discount_percent'] as int,
        status: json['status'] as String,
        usedInOrderId: json['used_in_order_id'] as String?,
      );

  final int promotionId;
  final String title;
  final int discountPercent;
  final String status;
  final String? usedInOrderId;

  bool get isPending => status == 'pending';
}

/// Resultado de mover dinero entre el Banco y la Wallet.
class TransferOutcome {
  const TransferOutcome({required this.walletBalanceCents, required this.bankBalanceCents});

  final int walletBalanceCents;
  final int bankBalanceCents;
}

class BankRepository {
  BankRepository({required Dio publicDio, required Dio authDio, required WalletLedgerRepository ledger})
      : _publicDio = publicDio,
        _authDio = authDio,
        _ledger = ledger;

  final Dio _publicDio; // rutas públicas del Banco (promociones)
  final Dio _authDio; // rutas protegidas con el token del Banco
  final WalletLedgerRepository _ledger;

  Future<BankAccount> account() async {
    final res = await _authDio.get<dynamic>('/accounts/me');
    return BankAccount.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<BankMovement>> movements({int limit = 20, int? before}) async {
    final res = await _authDio.get<dynamic>(
      '/accounts/me/movements',
      queryParameters: {'limit': limit, if (before != null) 'before': before},
    );
    return [for (final m in res.data as List<dynamic>) BankMovement.fromJson(m as Map<String, dynamic>)];
  }

  Future<List<BankPromotion>> promotions() async {
    final res = await _publicDio.get<dynamic>('/promotions');
    return [for (final p in res.data as List<dynamic>) BankPromotion.fromJson(p as Map<String, dynamic>)];
  }

  /// Canjes propios, por id de promoción.
  Future<Map<int, BankRedemption>> redemptions() async {
    final res = await _authDio.get<dynamic>('/promotions/me/redemptions');
    final result = <int, BankRedemption>{};
    for (final raw in res.data as List<dynamic>) {
      final redemption = BankRedemption.fromJson(raw as Map<String, dynamic>);
      result[redemption.promotionId] = redemption;
    }
    return result;
  }

  Future<void> redeem(int promotionId) async {
    await _authDio.post<dynamic>('/promotions/$promotionId/redeem');
  }

  /// Banco → Wallet: el Banco descuenta y firma un comprobante; la Wallet lo verifica y abona.
  Future<TransferOutcome> rechargeWallet(int amountCents) async {
    final res = await _authDio.post<dynamic>('/transfers/to-wallet', data: {
      'amount_cents': amountCents,
      'idempotency_key': randomUrlSafe(16),
    });
    final signed = Map<String, dynamic>.from(res.data as Map);
    // El dinero ya salió del Banco: si la red falla al entregar el comprobante se reintenta
    // una vez, y el backend no abona dos veces el mismo comprobante.
    final walletBalance = await _retryOnce(() => _ledger.topup(signed));
    final bank = await account();
    return TransferOutcome(walletBalanceCents: walletBalance, bankBalanceCents: bank.balanceCents);
  }

  /// Wallet → Banco: la Wallet descuenta y firma; el Banco verifica y abona.
  Future<TransferOutcome> withdrawToBank(int amountCents) async {
    final signed = await _ledger.withdraw(amountCents);
    final res = await _retryOnce(() => _authDio.post<dynamic>('/transfers/from-wallet', data: signed));
    final wallet = await _ledger.balance();
    return TransferOutcome(
      walletBalanceCents: wallet,
      bankBalanceCents: (res.data as Map<String, dynamic>)['balance_cents'] as int,
    );
  }

  Future<T> _retryOnce<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final network = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!network) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return action();
    }
  }
}

final bankRepositoryProvider = Provider<BankRepository>(
  (ref) => BankRepository(
    publicDio: ref.watch(bankDioProvider),
    authDio: ref.watch(bankAuthDioProvider),
    ledger: ref.watch(walletLedgerRepositoryProvider),
  ),
);

final bankAccountProvider = FutureProvider.autoDispose<BankAccount>(
  (ref) => ref.watch(bankRepositoryProvider).account(),
);

final bankPromotionsProvider = FutureProvider.autoDispose<List<BankPromotion>>(
  (ref) => ref.watch(bankRepositoryProvider).promotions(),
);

/// Canjes propios. Si no hay cuenta vinculada devuelve vacío sin llamar al Banco.
final bankRedemptionsProvider = FutureProvider.autoDispose<Map<int, BankRedemption>>((ref) async {
  final linked = await ref.watch(bankLinkedProvider.future);
  if (!linked) return <int, BankRedemption>{};
  return ref.watch(bankRepositoryProvider).redemptions();
});
