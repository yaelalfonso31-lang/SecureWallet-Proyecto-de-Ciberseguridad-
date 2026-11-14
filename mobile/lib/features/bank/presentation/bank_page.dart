import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/bank_auth_repository.dart';
import 'account_page.dart';
import 'bank_link_page.dart';

final promotionsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(bankDioProvider).get('/promotions');
  return res.data as List<dynamic>;
});

/// Tablero del Banco: estado de la vinculación y promociones.
/// TODO equipo Banco: canje de promociones (B4-a) y transferencias (B5).
class BankPage extends ConsumerWidget {
  const BankPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(bankLinkedProvider);
    final promotions = ref.watch(promotionsProvider);
    return ListView(
      children: [
        linked.when<Widget>(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => const _LinkCard(linked: false),
          data: (isLinked) => _LinkCard(linked: isLinked),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Promociones', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...promotions.when<List<Widget>>(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (e, _) => [Center(child: Text(errorMessage(e)))],
          data: (items) => [
            for (final p in items)
              ListTile(
                leading: const Icon(Icons.local_offer),
                title: Text('${p['title']}'),
                subtitle: Text('${p['description']}'),
                trailing: Text('${p['discount_percent']}%'),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinkCard extends ConsumerWidget {
  const _LinkCard({required this.linked});

  final bool linked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (linked) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: const Text('Banco vinculado'),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(bankAuthRepositoryProvider).unlink();
                  ref.invalidate(bankLinkedProvider);
                },
                child: const Text('Desvincular'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Mi cuenta'),
              subtitle: const Text('Saldo y movimientos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AccountPage(dio: ref.read(bankAuthDioProvider)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Vincula tu cuenta bancaria para ver tu saldo, canjear promociones y recargar tu Wallet.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Vincular banco'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
