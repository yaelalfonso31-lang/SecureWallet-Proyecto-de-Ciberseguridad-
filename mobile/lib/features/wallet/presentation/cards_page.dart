import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final cardsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(walletDioProvider).get('/cards');
  return res.data as List<dynamic>;
});

/// TODO equipo Wallet: formulario "Agregar tarjeta" (POST /cards), eliminar tarjeta,
/// re-autenticación biométrica antes de mostrar datos, saldo e historial.
class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return cards.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('Aún no tienes tarjetas guardadas'));
        }
        return ListView(
          children: [
            for (final c in items)
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text('${c['brand']} •••• ${c['last4']}'),
                subtitle: Text('${c['holder_name']}  ·  vence ${c['exp_month']}/${c['exp_year']}'),
              ),
          ],
        );
      },
    );
  }
}
