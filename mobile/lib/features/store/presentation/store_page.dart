import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final productsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(storeDioProvider).get('/products');
  return res.data as List<dynamic>;
});

String formatPrice(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// TODO equipo Tienda: carrito y checkout "Pagar con Wallet":
///   1) POST {store}/orders   2) POST {wallet}/payments/authorize (con biometría)
///   3) POST {store}/orders/{id}/pay   4) verificar el recibo con ReceiptVerifier.
class StorePage extends ConsumerWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    return products.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (items) => ListView(
        children: [
          for (final p in items)
            ListTile(
              leading: const Icon(Icons.shopping_bag),
              title: Text('${p['name']}'),
              subtitle: Text('${p['description']}'),
              trailing: Text(formatPrice(p['price_cents'] as int)),
            ),
        ],
      ),
    );
  }
}
