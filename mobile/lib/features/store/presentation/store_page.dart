import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/cart_provider.dart';
import 'cart_page.dart';

final productsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(storeDioProvider).get('/products');
  return res.data as List<dynamic>;
});

String formatPrice(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class StorePage extends ConsumerWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final count = ref.watch(cartCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CartPage()),
        ),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.shopping_cart),
        ),
        label: const Text('Carrito'),
      ),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (items) => ListView(
          padding: const EdgeInsets.only(bottom: 88), // deja espacio al botón flotante
          children: [
            for (final p in items)
              ListTile(
                leading: const Icon(Icons.shopping_bag),
                title: Text('${p['name']}'),
                subtitle: Text('${p['description']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatPrice(p['price_cents'] as int)),
                    IconButton(
                      tooltip: 'Agregar al carrito',
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: (p['stock'] as int) > 0
                          ? () => ref.read(cartProvider.notifier).add(p['id'] as int, '${p['name']}')
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}