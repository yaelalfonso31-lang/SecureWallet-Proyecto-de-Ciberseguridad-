import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final promotionsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(bankDioProvider).get('/promotions');
  return res.data as List<dynamic>;
});

/// TODO equipo Banco: vincular cuenta (OAuth2 simulado), saldo, movimientos, canjear promociones.
class BankPage extends ConsumerWidget {
  const BankPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotions = ref.watch(promotionsProvider);
    return promotions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (items) => ListView(
        children: [
          for (final p in items)
            ListTile(
              leading: const Icon(Icons.local_offer),
              title: Text('${p['title']}'),
              subtitle: Text('${p['description']}'),
              trailing: Text('${p['discount_percent']}%'),
            ),
        ],
      ),
    );
  }
}
