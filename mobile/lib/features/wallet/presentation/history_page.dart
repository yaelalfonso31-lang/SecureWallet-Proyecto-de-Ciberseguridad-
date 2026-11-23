import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/wallet_ledger_repository.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

enum _Filter { all, income, expense }

/// Historial real de movimientos de la Wallet con filtros, búsqueda y agrupación por día.
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

  Future<void> _refresh() async {
    ref.invalidate(walletMovementsProvider);
    ref.invalidate(walletBalanceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  List<WalletMovement> _filtered(List<WalletMovement> all) {
    final q = _query.text.trim().toLowerCase();
    return all.where((m) {
      final okFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.income => m.isCredit,
        _Filter.expense => !m.isCredit,
      };
      final okQuery = q.isEmpty ||
          m.concept.toLowerCase().contains(q) ||
          (m.reference?.toLowerCase().contains(q) ?? false);
      return okFilter && okQuery;
    }).toList();
  }

  Widget _summary(IconData icon, String label, int cents, Color color) {
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(
              icon,
              size: 40,
              color: color,
              background: color.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: WalletText.muted),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(cents),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _movementTile(WalletMovement m) {
    final credit = m.isCredit;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: IconBadge(
        credit ? Icons.south_west_rounded : Icons.north_east_rounded,
        color: credit ? WalletColors.success : WalletColors.navy,
        background: credit ? const Color(0xFFE6F6EF) : WalletColors.yellowSoft,
      ),
      title: Text(
        m.concept,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: WalletColors.ink,
        ),
      ),
      subtitle: Text(
        '${formatTime(m.createdAt.toLocal())} · Saldo ${formatMoney(m.balanceAfterCents)}',
        style: WalletText.muted,
      ),
      trailing: Text(
        '${credit ? '+' : '-'}${formatMoney(m.amountCents)}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: credit ? WalletColors.success : WalletColors.ink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movementsAsync = ref.watch(walletMovementsProvider);
    final all = movementsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <WalletMovement>[],
    );
    final items = _filtered(all);
    final income = all
        .where((m) => m.isCredit)
        .fold<int>(0, (sum, m) => sum + m.amountCents);
    final expense = all
        .where((m) => !m.isCredit)
        .fold<int>(0, (sum, m) => sum + m.amountCents);

    final rows = <Widget>[];
    String? lastDay;
    for (final m in items) {
      final label = dayLabel(m.createdAt.toLocal());
      if (label != lastDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              label.toUpperCase(),
              style: WalletText.muted.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        );
        lastDay = label;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SoftCard(
            padding: EdgeInsets.zero,
            child: _movementTile(m),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Historial')),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _summary(
                    Icons.arrow_downward_rounded,
                    'Ingresos',
                    income,
                    WalletColors.success,
                  ),
                  const SizedBox(width: 12),
                  _summary(
                    Icons.arrow_upward_rounded,
                    'Gastos',
                    expense,
                    WalletColors.yellowDark,
                  ),
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
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _filter == f
                            ? WalletColors.ink
                            : WalletColors.muted,
                      ),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
            if (movementsAsync.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (movementsAsync.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: InfoBanner(
                  kind: BannerKind.danger,
                  text: errorMessage(movementsAsync.error!),
                ),
              )
            else if (rows.isEmpty)
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
      ),
    );
  }
}
