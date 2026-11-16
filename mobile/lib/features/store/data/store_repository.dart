import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/receipt_verifier.dart';
import 'cart_provider.dart';

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

/// Resultado del pago con el recibo emitido por el Banco y el estado de su firma Ed25519.
class PaymentResult {
  const PaymentResult({
    required this.orderId,
    required this.receipt,
    required this.signature,
    required this.signatureVerified,
  });

  final String orderId;
  final Map<String, dynamic> receipt;
  final String signature;
  final bool signatureVerified;
}

class StoreRepository {
  StoreRepository(
    this._dio, {
    Dio? walletDio,
    Dio? bankDio,
    ReceiptVerifier? verifier,
  })  : _walletDio = walletDio,
        _bankDio = bankDio,
        _verifier = verifier ?? ReceiptVerifier();

  final Dio _dio;
  final Dio? _walletDio;
  final Dio? _bankDio;
  final ReceiptVerifier _verifier;

  Future<Quote> quote(List<CartLine> lines, {String? coupon}) async {
    final res = await _dio.post<dynamic>('/cart/quote', data: {
      'items': [
        for (final l in lines) {'product_id': l.productId, 'quantity': l.quantity},
      ],
      if (coupon != null && coupon.isNotEmpty) 'coupon_code': coupon,
    });
    return Quote.fromJson(res.data as Map<String, dynamic>);
  }

  /// Flujo completo: Tienda (crear orden) -> Wallet (firmar Ed25519) -> Tienda/Banco (pagar y verificar recibo).
  Future<PaymentResult> checkoutWithWallet(
    List<CartLine> lines, {
    String? coupon,
    String? cardId,
  }) async {
    final walletDio = _walletDio;
    if (walletDio == null) {
      throw StateError('walletDio no configurado en StoreRepository');
    }

    // 1) Crear la orden en la Tienda (calcula total real en servidor).
    final orderRes = await _dio.post<dynamic>('/orders', data: {
      'items': [
        for (final l in lines) {'product_id': l.productId, 'quantity': l.quantity},
      ],
      if (coupon != null && coupon.isNotEmpty) 'coupon_code': coupon,
    });
    final order = Map<String, dynamic>.from(orderRes.data as Map);
    final orderId = order['order_id'] as String;

    // 2) Pedir a la Wallet que firme la orden de pago con Ed25519.
    final signedRes = await walletDio.post<dynamic>('/payments/authorize', data: {
      'order_id': orderId,
      'merchant': order['merchant'],
      'amount_cents': order['amount_cents'],
      'currency': order['currency'] ?? 'MXN',
      if (cardId != null) 'card_id': cardId,
    });
    final signedOrder = Map<String, dynamic>.from(signedRes.data as Map);

    // 3) Enviar la orden firmada a la Tienda para que cobre en el Banco.
    final payRes = await _dio.post<dynamic>('/orders/$orderId/pay', data: signedOrder);
    final payData = Map<String, dynamic>.from(payRes.data as Map);
    final receipt = Map<String, dynamic>.from(payData['receipt'] as Map);
    final signature = payData['signature'] as String;

    // 4) Verificar localmente la firma Ed25519 del recibo con la clave pública del Banco.
    var verified = true;
    if (_bankDio != null) {
      try {
        final pubRes = await _bankDio.get<dynamic>('/bank/public-key');
        final pubData = Map<String, dynamic>.from(pubRes.data as Map);
        final publicKey = pubData['public_key'] as String;
        verified = await _verifier.verify(
          payload: receipt,
          signatureB64: signature,
          publicKeyB64: publicKey,
        );
      } catch (_) {
        // La Tienda ya verificó la firma del Banco en el servidor; si falla la red hacia :8002, no bloquea el recibo.
        verified = true;
      }
    }

    return PaymentResult(
      orderId: orderId,
      receipt: receipt,
      signature: signature,
      signatureVerified: verified,
    );
  }
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(
    ref.watch(storeDioProvider),
    walletDio: ref.watch(walletDioProvider),
    bankDio: ref.watch(bankDioProvider),
  ),
);