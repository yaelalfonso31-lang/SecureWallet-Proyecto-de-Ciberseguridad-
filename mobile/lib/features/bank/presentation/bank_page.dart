import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/bank_auth_repository.dart';
import 'account_page.dart';
import 'bank_link_page.dart';
import 'transfer_page.dart';

final promotionsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ref.watch(bankDioProvider).get<dynamic>('/promotions');
  return res.data as List<dynamic>;
});

/// Tablero del Banco: vinculación, cuenta, transferencias y canje de promociones.
class BankPage extends ConsumerStatefulWidget {
  const BankPage({super.key});

  @override
  ConsumerState<BankPage> createState() => _BankPageState();
}

class _BankPageState extends ConsumerState<BankPage> {
  final Set<int> _redeemedIds = <int>{};
  int? _busyPromoId;

  Future<void> _redeem(Map<String, dynamic> promo, {required bool isLinked}) async {
    if (!isLinked) {
      final linkedNow = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
      );
      if (linkedNow != true || !mounted) return;
    }

    final promoId = promo['id'] as int;
    setState(() => _busyPromoId = promoId);
    try {
      await ref.read(bankAuthDioProvider).post<dynamic>('/promotions/$promoId/redeem');
      if (!mounted) return;
      setState(() {
        _redeemedIds.add(promoId);
        _busyPromoId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Promoción "${promo['title']}" canjeada. Se aplicará en tu próxima compra con Wallet.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = errorMessage(e);
      setState(() {
        if (msg.toLowerCase().contains('canjeada')) {
          _redeemedIds.add(promoId);
        }
        _busyPromoId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = ref.watch(bankLinkedProvider);
    final promotions = ref.watch(promotionsProvider);
    final isLinked = linked.maybeWhen(data: (v) => v, orElse: () => false);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bankLinkedProvider);
        ref.invalidate(promotionsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          linked.when<Widget>(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const _LinkCard(linked: false),
            data: (value) => _LinkCard(linked: value),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Promociones del Banco', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...promotions.when<List<Widget>>(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text(errorMessage(e))),
              ),
            ],
            data: (items) => [
              for (final raw in items)
                Builder(
                  builder: (context) {
                    final p = Map<String, dynamic>.from(raw as Map);
                    final id = p['id'] as int;
                    final redeemed = _redeemedIds.contains(id);
                    final busy = _busyPromoId == id;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${p['discount_percent']}%'),
                        ),
                        title: Text('${p['title']}'),
                        subtitle: Text('${p['description']}'),
                        trailing: redeemed
                            ? const Chip(
                                avatar: Icon(Icons.check, size: 16),
                                label: Text('Canjeada'),
                              )
                            : FilledButton.tonal(
                                onPressed: busy ? null : () => _redeem(p, isLinked: isLinked),
                                child: busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Canjear'),
                              ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
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
            const Divider(height: 1),
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transferencias'),
              subtitle: const Text('Recargar o retirar entre Banco y Wallet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransferPage(dio: ref.read(bankAuthDioProvider)),
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
            const Text(
              'Vincula tu cuenta bancaria para ver tu saldo, canjear promociones y recargar tu Wallet.',
            ),
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