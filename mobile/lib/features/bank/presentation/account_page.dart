import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_repository.dart';
import 'bank_widgets.dart';

/// Detalle de la cuenta: tarjeta de saldo y movimientos agrupados por día, con paginación.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  static const _pageSize = 20;

  final List<BankMovement> _movements = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final before = reset || _movements.isEmpty ? null : _movements.last.id;
      final page = await ref.read(bankRepositoryProvider).movements(limit: _pageSize, before: before);
      if (!mounted) return;
      setState(() {
        if (reset) _movements.clear();
        _movements.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(bankAccountProvider);
    await _load(reset: true);
  }

  List<Widget> _rows() {
    final rows = <Widget>[];
    String? lastDay;
    for (final m in _movements) {
      final label = dayLabel(m.createdAt.toLocal());
      if (label != lastDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              label.toUpperCase(),
              style: WalletText.muted.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        );
        lastDay = label;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SoftCard(padding: EdgeInsets.zero, child: BankMovementTile(movement: m)),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(bankAccountProvider);
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: account.when(
                loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
                data: (a) => BankAccountCard(account: a),
              ),
            ),
            const SectionTitle('Movimientos'),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InfoBanner(kind: BannerKind.danger, text: _error!),
              )
            else if (_movements.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Sin movimientos',
                message: 'Tus depósitos, compras y transferencias aparecerán aquí.',
              )
            else
              ..._rows(),
            if (_hasMore && !_loading && _error == null && _movements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: SecondaryButton(
                  label: _loadingMore ? 'Cargando…' : 'Cargar más movimientos',
                  icon: Icons.expand_more_rounded,
                  onPressed: _loadingMore ? null : _load,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
