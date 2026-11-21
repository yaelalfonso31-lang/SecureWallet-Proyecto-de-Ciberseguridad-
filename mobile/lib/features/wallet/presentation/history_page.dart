import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/demo_wallet_store.dart';
import '../data/wallet_models.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

enum _Filter { all, income, expense }

/// Historial con filtros (Todos / Ingresos / Gastos), búsqueda y agrupación por día.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<WalletTransaction> _filtered(List<WalletTransaction> all) {
    final q = _query.text.trim().toLowerCase();
    return all.where((t) {
      final okFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.income => t.amountCents > 0,
        _Filter.expense => t.amountCents < 0,
      };
      final okQuery = q.isEmpty || t.title.toLowerCase().contains(q) || t.subtitle.toLowerCase().contains(q);
      return okFilter && okQuery;
    }).toList();
  }

  Widget _summary(IconData icon, String label, int cents, Color color) {
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icon, size: 40, color: color, background: color.withValues(alpha: 0.12)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: WalletText.muted),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatMoney(cents), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(demoWalletProvider).transactions;
    final items = _filtered(all);
    final income = all.where((t) => t.amountCents > 0).fold<int>(0, (sum, t) => sum + t.amountCents);
    final expense = all.where((t) => t.amountCents < 0).fold<int>(0, (sum, t) => sum - t.amountCents);

    final rows = <Widget>[];
    String? lastDay;
    for (final t in items) {
      final label = dayLabel(t.date);
      if (label != lastDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(label.toUpperCase(), style: WalletText.muted.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        );
        lastDay = label;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SoftCard(
            padding: EdgeInsets.zero,
            child: TransactionTile(tx: t, onTap: () => context.push('/transaction', extra: t)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Historial')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                _summary(Icons.arrow_downward_rounded, 'Ingresos', income, WalletColors.success),
                const SizedBox(width: 12),
                _summary(Icons.arrow_upward_rounded, 'Gastos', expense, WalletColors.yellowDark),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: WalletTextField(
              controller: _query,
              label: 'Buscar movimiento',
              icon: Icons.search_rounded,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(
                      switch (f) {
                        _Filter.all => 'Todos',
                        _Filter.income => 'Ingresos',
                        _Filter.expense => 'Gastos',
                      },
                    ),
                    selected: _filter == f,
                    selectedColor: WalletColors.yellow,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _filter == f ? WalletColors.ink : WalletColors.muted),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Sin movimientos',
                message: 'No encontramos movimientos con ese filtro.',
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}
