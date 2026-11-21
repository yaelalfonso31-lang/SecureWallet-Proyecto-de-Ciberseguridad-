import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_repository.dart';

/// Compra y consulta de tickets electrónicos emitidos por el Banco ($50, $100, $200, $500).
class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key});

  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  static const _denominations = [5000, 10000, 20000, 50000];

  final _biometric = BiometricService();
  int _selectedCents = 10000; // $100 por defecto
  int _quantity = 1;
  bool _buying = false;
  String? _error;

  Future<void> _buy() async {
    final total = _selectedCents * _quantity;
    setState(() {
      _buying = true;
      _error = null;
    });
    try {
      if (await _biometric.isAvailable()) {
        final ok = await _biometric.authenticate(
          'Confirma la compra de $_quantity ticket(s) por ${formatMoney(total)}',
        );
        if (!ok) {
          if (mounted) {
            setState(() {
              _buying = false;
              _error = 'Autenticación biométrica cancelada';
            });
          }
          return;
        }
      }
      await ref.read(bankRepositoryProvider).purchaseTickets(
            denominationCents: _selectedCents,
            quantity: _quantity,
          );
      ref.invalidate(bankAccountProvider);
      ref.invalidate(bankTicketsProvider);
      if (!mounted) return;
      showWalletSnack(context, '¡Tickets emitidos y firmados por el Banco!');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(bankAccountProvider);
    final tickets = ref.watch(bankTicketsProvider);
    final total = _selectedCents * _quantity;

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Tickets electrónicos')),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: () async {
          ref.invalidate(bankAccountProvider);
          ref.invalidate(bankTicketsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Adquirir tickets del Banco',
                          style: WalletText.h3),
                      account.maybeWhen(
                        data: (a) => Text(
                          'Saldo: ${formatMoney(a.balanceCents)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: WalletColors.blue),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Selecciona una denominación predefinida. Cada ticket se firma con Ed25519 para pagar en la Tienda.',
                    style: WalletText.muted,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final d in _denominations)
                        ChoiceChip(
                          label: Text(
                            '\$${d ~/ 100}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _selectedCents == d
                                  ? WalletColors.navy
                                  : WalletColors.ink,
                            ),
                          ),
                          selected: _selectedCents == d,
                          selectedColor: WalletColors.yellow,
                          onSelected: _buying
                              ? null
                              : (_) => setState(() => _selectedCents = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Cantidad:',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: (!_buying && _quantity > 1)
                            ? () => setState(() => _quantity--)
                            : null,
                      ),
                      Text('$_quantity',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: (!_buying && _quantity < 10)
                            ? () => setState(() => _quantity++)
                            : null,
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    InfoBanner(kind: BannerKind.danger, text: _error!),
                  ],
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Comprar por ${formatMoney(total)}',
                    icon: Icons.confirmation_number_rounded,
                    loading: _buying,
                    onPressed: _buy,
                  ),
                ],
              ),
            ),
            const SectionTitle('Mis tickets emitidos'),
            tickets.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) =>
                  InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Aún no tienes tickets',
                    message:
                        'Adquiere tickets de \$50, \$100, \$200 o \$500 para pagar en la tienda.',
                  );
                }
                return Column(
                  children: [
                    for (final t in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              IconBadge(
                                Icons.confirmation_number_rounded,
                                size: 46,
                                color: t.isActive
                                    ? WalletColors.navy
                                    : WalletColors.muted,
                                background: t.isActive
                                    ? WalletColors.yellowSoft
                                    : WalletColors.ice,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(formatMoney(t.amountCents),
                                        style: WalletText.h3),
                                    Text(
                                      t.ticketId,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: WalletText.muted,
                                    ),
                                    const SizedBox(height: 4),
                                    StatusChip(
                                      label: t.isActive
                                          ? 'Disponible · Firmado Ed25519'
                                          : 'Usado en ${t.spentInOrderId ?? "orden"}',
                                      color: t.isActive
                                          ? WalletColors.success
                                          : WalletColors.muted,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
