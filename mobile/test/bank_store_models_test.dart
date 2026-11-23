import 'package:flutter_test/flutter_test.dart';
import 'package:secure_wallet/features/bank/data/bank_repository.dart';
import 'package:secure_wallet/features/store/data/store_models.dart';
import 'package:secure_wallet/features/wallet/presentation/theme/wallet_format.dart';

void main() {
  test('BankAccount y BankMovement leen el JSON del backend', () {
    final account = BankAccount.fromJson({
      'account_number_masked': '•••• 1234',
      'balance_cents': 500000,
      'status': 'active',
    });
    expect(account.balanceCents, 500000);
    expect(account.isFrozen, isFalse);

    final movement = BankMovement.fromJson({
      'id': 7,
      'kind': 'credit',
      'amount_cents': 2500,
      'balance_after_cents': 502500,
      'concept': 'Depósito',
      'created_at': '2026-11-10T22:54:52',
    });
    expect(movement.isCredit, isTrue);
    expect(movement.id, 7);
  });

  test('BankRedemption distingue canjes pendientes y usados', () {
    final pending = BankRedemption.fromJson({
      'promotion_id': 1,
      'title': 'Bono',
      'discount_percent': 10,
      'status': 'pending',
      'used_in_order_id': null,
    });
    final used = BankRedemption.fromJson({
      'promotion_id': 2,
      'title': 'Otro',
      'discount_percent': 5,
      'status': 'used',
      'used_in_order_id': 'ord_1',
    });
    expect(pending.isPending, isTrue);
    expect(used.isPending, isFalse);
  });

  test('StoreProduct calcula existencias', () {
    final product = StoreProduct.fromJson({
      'id': 1,
      'name': 'Teclado',
      'description': 'x',
      'price_cents': 1000,
      'stock': 3,
    });
    expect(product.category, 'General');
    expect(product.lowStock, isTrue);
    expect(product.soldOut, isFalse);
  });

  test('StoreOrder lee el historial y arma el resumen', () {
    final order = StoreOrder.fromJson({
      'order_id': 'ord_abc',
      'status': 'paid',
      'amount_cents': 10000,
      'subtotal_cents': 11000,
      'discount_cents': 1000,
      'coupon_code': 'PROMO10',
      'created_at': '2026-11-10T10:00:00',
      'items': [
        {'product_id': 1, 'name': 'Teclado', 'quantity': 1, 'unit_price_cents': 6000},
        {'product_id': 2, 'name': 'Mouse', 'quantity': 2, 'unit_price_cents': 2500},
      ],
      'charged_cents': 9000,
      'bank_discount_cents': 1000,
      'receipt': {'status': 'approved'},
      'signature': 'firma',
    });
    expect(order.isPaid, isTrue);
    expect(order.itemsCount, 3);
    expect(order.summary, 'Teclado y 1 más');
    expect(order.chargedCents, 9000);
  });

  test('formatMoney agrega separador de miles', () {
    expect(formatMoney(129900), '\$1,299.00');
    expect(formatMoney(-8500), '-\$85.00');
  });
}
