class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.stock,
    required this.category,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) => StoreProduct(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String,
        priceCents: json['price_cents'] as int,
        stock: json['stock'] as int,
        category: (json['category'] as String?) ?? 'General',
      );

  final int id;
  final String name;
  final String description;
  final int priceCents;
  final int stock;
  final String category;

  bool get soldOut => stock <= 0;
  bool get lowStock => stock > 0 && stock <= 5;
}

class StoreOrderItem {
  const StoreOrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
  });

  factory StoreOrderItem.fromJson(Map<String, dynamic> json) => StoreOrderItem(
        productId: json['product_id'] as int,
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        unitPriceCents: json['unit_price_cents'] as int,
      );

  final int productId;
  final String name;
  final int quantity;
  final int unitPriceCents;
}

/// Orden del historial (`GET /orders`).
class StoreOrder {
  const StoreOrder({
    required this.orderId,
    required this.status,
    required this.amountCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.createdAt,
    required this.items,
    this.couponCode,
    this.chargedCents,
    this.bankDiscountCents = 0,
    this.receipt,
    this.signature,
  });

  factory StoreOrder.fromJson(Map<String, dynamic> json) => StoreOrder(
        orderId: json['order_id'] as String,
        status: json['status'] as String,
        amountCents: json['amount_cents'] as int,
        subtotalCents: (json['subtotal_cents'] as int?) ?? (json['amount_cents'] as int),
        discountCents: (json['discount_cents'] as int?) ?? 0,
        couponCode: json['coupon_code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        items: [
          for (final i in json['items'] as List<dynamic>) StoreOrderItem.fromJson(i as Map<String, dynamic>),
        ],
        chargedCents: json['charged_cents'] as int?,
        bankDiscountCents: (json['bank_discount_cents'] as int?) ?? 0,
        receipt: json['receipt'] == null ? null : Map<String, dynamic>.from(json['receipt'] as Map),
        signature: json['signature'] as String?,
      );

  final String orderId;
  final String status; // pending | paid | cancelled
  final int amountCents;
  final int subtotalCents;
  final int discountCents;
  final String? couponCode;
  final DateTime createdAt;
  final List<StoreOrderItem> items;
  final int? chargedCents;
  final int bankDiscountCents;
  final Map<String, dynamic>? receipt;
  final String? signature;

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';
  int get itemsCount => items.fold(0, (sum, i) => sum + i.quantity);

  String get summary {
    if (items.isEmpty) return 'Sin artículos';
    final first = items.first.name;
    return items.length == 1 ? first : '$first y ${items.length - 1} más';
  }
}
