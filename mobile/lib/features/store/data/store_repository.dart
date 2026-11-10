import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
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

class StoreRepository {
  StoreRepository(this._dio);
  final Dio _dio;

  Future<Quote> quote(List<CartLine> lines, {String? coupon}) async {
    final res = await _dio.post('/cart/quote', data: {
      'items': [
        for (final l in lines) {'product_id': l.productId, 'quantity': l.quantity},
      ],
      if (coupon != null && coupon.isNotEmpty) 'coupon_code': coupon,
    });
    return Quote.fromJson(res.data as Map<String, dynamic>);
  }
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(storeDioProvider)),
);