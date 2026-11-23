import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/receipt_verifier.dart';
import 'cart_provider.dart';

/// Clave pública Ed25519 del Banco (base64url). Se pasa al compilar con
/// --dart-define=BANK_PUBLIC_KEY=... Es pública, pero cada backend local tiene la suya.
const String _bankPublicKey = String.fromEnvironment('BANK_PUBLIC_KEY');

class QuoteLine {
  const QuoteLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  final int productId;
  final String name;
  final int quantity;
  final int unitPriceCents;
  final int lineTotalCents;

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        productId: j['product_id'] as int,
        name: j['name'] as String,
        quantity: j['quantity'] as int,
        unitPriceCents: j['unit_price_cents'] as int,
        lineTotalCents: j['line_total_cents'] as int,
      );
}

/// Cotización calculada por el servidor. La app solo la muestra, nunca calcula precios.
class Quote {
  const Quote({
    required this.lines,
    required this.subtotalCents,
    required this.discountCents,
    required this.totalCents,
    this.couponCode,
  });

  final List<QuoteLine> lines;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final String? couponCode;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        lines: [for (final l in j['items'] as List) QuoteLine.fromJson(l as Map<String, dynamic>)],
        subtotalCents: j['subtotal_cents'] as int,
        discountCents: j['discount_cents'] as int,
        totalCents: j['total_cents'] as int,
        couponCode: j['coupon_code'] as String?,
      );
}

class OrderDraft {
  const OrderDraft({required this.orderId, required this.merchant, required this.amountCents});

  final String orderId;
  final String merchant;
  final int amountCents;

  factory OrderDraft.fromJson(Map<String, dynamic> j) => OrderDraft(
        orderId: j['order_id'] as String,
        merchant: j['merchant'] as String,
        amountCents: j['amount_cents'] as int,
      );
}

enum ReceiptStatus { verified, invalid, unchecked }

class PaidOrder {
  const PaidOrder({
    required this.orderId,
    required this.amountCents,
    required this.receiptStatus,
  });

  final String orderId;
  final int amountCents;
  final ReceiptStatus receiptStatus;
}

class StoreRepository {
  StoreRepository(this._store, this._wallet, this._verifier);

  final Dio _store;
  final Dio _wallet;
  final ReceiptVerifier _verifier;

  Future<Quote> quote(List<CartLine> lines, {String? coupon}) async {
    final res = await _store.post('/cart/quote', data: _orderBody(lines, coupon));
    return Quote.fromJson(res.data as Map<String, dynamic>);
  }

  Future<OrderDraft> createOrder(List<CartLine> lines, {String? coupon}) async {
    final res = await _store.post('/orders', data: _orderBody(lines, coupon));
    return OrderDraft.fromJson(res.data as Map<String, dynamic>);
  }

  /// La Wallet firma la orden de pago (Ed25519). Devuelve la orden firmada tal cual.
  Future<Map<String, dynamic>> authorize(OrderDraft order) async {
    final res = await _wallet.post('/payments/authorize', data: {
      'order_id': order.orderId,
      'merchant': order.merchant,
      'amount_cents': order.amountCents,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<PaidOrder> pay(OrderDraft order, Map<String, dynamic> signed) async {
    final res = await _store.post('/orders/${order.orderId}/pay', data: signed);
    final data = res.data as Map<String, dynamic>;
    final receipt = Map<String, dynamic>.from(data['receipt'] as Map);
    final signature = data['signature'] as String;
    return PaidOrder(
      orderId: order.orderId,
      amountCents: order.amountCents,
      receiptStatus: await _checkReceipt(order, receipt, signature),
    );
  }

  /// Verifica la firma del Banco y que el recibo corresponda a ESTA compra.
  Future<ReceiptStatus> _checkReceipt(
    OrderDraft order,
    Map<String, dynamic> receipt,
    String signature,
  ) async {
    if (_bankPublicKey.isEmpty) return ReceiptStatus.unchecked;
    try {
      final signatureOk = await _verifier.verify(
        payload: receipt,
        signatureB64: signature,
        publicKeyB64: _bankPublicKey,
      );
      final matches = receipt['status'] == 'approved' &&
          receipt['order_id'] == order.orderId &&
          receipt['amount_cents'] == order.amountCents;
      return signatureOk && matches ? ReceiptStatus.verified : ReceiptStatus.invalid;
    } catch (_) {
      return ReceiptStatus.invalid;
    }
  }

  Map<String, dynamic> _orderBody(List<CartLine> lines, String? coupon) => {
        'items': [
          for (final l in lines) {'product_id': l.productId, 'quantity': l.quantity},
        ],
        if (coupon != null && coupon.isNotEmpty) 'coupon_code': coupon,
      };
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(
    ref.watch(storeDioProvider),
    ref.watch(walletDioProvider),
    ReceiptVerifier(),
  ),
);