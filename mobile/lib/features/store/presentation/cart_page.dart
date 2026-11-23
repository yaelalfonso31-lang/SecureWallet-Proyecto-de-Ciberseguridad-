import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../bank/data/bank_repository.dart';
import '../../wallet/data/cards_repository.dart';
import '../../wallet/data/wallet_ledger_repository.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/cart_provider.dart';
import '../data/store_repository.dart';
import 'store_widgets.dart';
import '../../bank/presentation/tickets_page.dart';

/// Carrito: cantidades, cupón, total calculado por el servidor y pago con la Wallet.
class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  final _couponCtrl = TextEditingController();
  final _biometric = BiometricService();
  final Set<String> _selectedTicketIds = {};
  Quote? _quote;
  String? _coupon; // cupón que se está intentando aplicar
  String? _couponError;
  String? _error;
  bool _loading = false;
  bool _paying = false;
  int _seq = 0; // descarta respuestas viejas si el carrito cambia rápido

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty) {
      setState(() {
        _quote = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    final repo = ref.read(storeRepositoryProvider);
    try {
      Quote q;
      try {
        q = await repo.quote(lines, coupon: _coupon);
      } on DioException catch (e) {
        if (_coupon == null || e.response?.statusCode != 400) rethrow;
        // El servidor rechazó el cupón: se muestra el motivo y se cotiza sin él.
        _couponError = errorMessage(e);
        _coupon = null;
        q = await repo.quote(lines);
      }
      if (!mounted || seq != _seq) return;
      setState(() {
        _quote = q;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _coupon = code;
      _couponError = null;
    });
    await _refresh();
  }

  void _removeCoupon() {
    setState(() {
      _coupon = null;
      _couponError = null;
      _couponCtrl.clear();
    });
    _refresh();
  }

  Future<void> _payWithTickets(List<BankTicket> selectedTickets) async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty || _quote == null || selectedTickets.isEmpty) return;

    setState(() {
      _paying = true;
      _error = null;
    });

    try {
      if (await _biometric.isAvailable()) {
        final ok = await _biometric.authenticate(
          'Confirma el pago con ${selectedTickets.length} ticket(s) por ${formatPrice(_quote!.totalCents)}',
        );
        if (!ok) {
          if (mounted) {
            setState(() {
              _paying = false;
              _error = 'Autenticación biométrica cancelada';
            });
          }
          return;
        }
      }

      final result =
          await ref.read(storeRepositoryProvider).checkoutWithTickets(
                lines,
                signedTickets: [
                  for (final t in selectedTickets) t.toSignedPayload()
                ],
                coupon: _quote!.couponCode,
              );

      if (!mounted) return;
      if (!result.signatureVerified) {
        setState(() {
          _paying = false;
          _error = 'La firma Ed25519 del recibo bancario no es válida';
        });
        return;
      }

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider);
      ref.invalidate(ordersProvider);
      ref.invalidate(bankAccountProvider);
      ref.invalidate(bankTicketsProvider);
      setState(() {
        _paying = false;
        _selectedTicketIds.clear();
      });

      await showReceiptSheet(context, result);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = errorMessage(e);
      });
    }
  }

  Future<void> _payWithWallet() async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty || _quote == null) return;

    setState(() {
      _paying = true;
      _error = null;
    });

    try {
      // 1) Re-autenticación biométrica si el dispositivo lo soporta.
      if (await _biometric.isAvailable()) {
        final ok = await _biometric.authenticate(
          'Confirma el pago de ${formatPrice(_quote!.totalCents)} en SecureStore',
        );
        if (!ok) {
          if (mounted) {
            setState(() {
              _paying = false;
              _error = 'Autenticación biométrica cancelada';
            });
          }
          return;
        }
      }

      // 2) Flujo completo de pago (Tienda -> Wallet -> Tienda -> Banco).
      final defaultCardId = ref.read(defaultCardIdProvider);
      final result = await ref.read(storeRepositoryProvider).checkoutWithWallet(
            lines,
            coupon: _quote!.couponCode,
            cardId: defaultCardId,
          );

      if (!mounted) return;
      if (!result.signatureVerified) {
        setState(() {
          _paying = false;
          _error = 'La firma Ed25519 del recibo bancario no es válida';
        });
        return;
      }

      // 3) Limpiar el carrito y refrescar todo lo que cambió con la compra.
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider);
      ref.invalidate(ordersProvider);
      ref.invalidate(bankAccountProvider);
      ref.invalidate(bankRedemptionsProvider);
      ref.invalidate(walletBalanceProvider);
      setState(() => _paying = false);

      // 4) Recibo firmado por el Banco.
      await showReceiptSheet(context, result);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = errorMessage(e);
      });
    }
  }

  Widget _line(CartLine l, QuoteLine? priced) {
    final cart = ref.read(cartProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconBadge(iconForName(l.name),
                size: 48,
                color: WalletColors.navy,
                background: WalletColors.yellowSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: WalletColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    priced == null ? '…' : formatPrice(priced.lineTotalCents),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: WalletColors.blue),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                  color: WalletColors.ice,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Quitar uno',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed:
                        _paying ? null : () => cart.decrement(l.productId),
                  ),
                  Text('${l.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Agregar uno',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: (!_paying && l.quantity < kMaxQtyPerProduct)
                        ? () => cart.add(l.productId, l.name)
                        : null,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: WalletColors.danger),
              onPressed: _paying ? null : () => cart.remove(l.productId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontSize: bold ? 18 : 14,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      color: color ?? (bold ? WalletColors.ink : WalletColors.muted),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cartProvider, (previous, next) => _refresh());
    final lines = ref.watch(cartProvider);
    final priceByProduct = {
      for (final l in _quote?.lines ?? const <QuoteLine>[]) l.productId: l
    };
    final appliedCoupon = _quote?.couponCode;
    final pendingPromos = ref.watch(bankRedemptionsProvider).maybeWhen(
          data: (m) => m.values.where((r) => r.isPending).toList(),
          orElse: () => const <BankRedemption>[],
        );
    final activeTickets = ref.watch(bankTicketsProvider).maybeWhen(
          data: (list) => list.where((t) => t.isActive).toList(),
          orElse: () => const <BankTicket>[],
        );
    final selectedTickets = [
      for (final t in activeTickets)
        if (_selectedTicketIds.contains(t.ticketId)) t,
    ];
    final selectedTotalCents =
        selectedTickets.fold<int>(0, (sum, t) => sum + t.amountCents);
    final ticketsCoverOrder =
        _quote != null && selectedTotalCents >= _quote!.totalCents;

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Mi carrito')),
      body: lines.isEmpty
          ? EmptyState(
              icon: Icons.remove_shopping_cart_rounded,
              title: 'Tu carrito está vacío',
              message: 'Explora el catálogo y agrega lo que te guste.',
              actionLabel: 'Ver productos',
              actionIcon: Icons.storefront_rounded,
              onAction: () => Navigator.of(context).pop(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading || _paying) ...[
                  const LinearProgressIndicator(color: WalletColors.yellow),
                  const SizedBox(height: 10),
                ],
                for (final l in lines) _line(l, priceByProduct[l.productId]),
                const SizedBox(height: 6),
                SoftCard(
                  padding: const EdgeInsets.all(14),
                  child: appliedCoupon != null
                      ? Row(
                          children: [
                            const IconBadge(Icons.local_offer_rounded,
                                size: 40,
                                color: WalletColors.navy,
                                background: WalletColors.yellowSoft),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text('Cupón $appliedCoupon aplicado',
                                    style: WalletText.h3)),
                            IconButton(
                              tooltip: 'Quitar cupón',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _paying ? null : _removeCoupon,
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponCtrl,
                                enabled: !_paying,
                                textCapitalization:
                                    TextCapitalization.characters,
                                maxLength: 32,
                                onSubmitted: (_) => _applyCoupon(),
                                decoration: InputDecoration(
                                  labelText: '¿Tienes un cupón?',
                                  counterText: '',
                                  errorText: _couponError,
                                  prefixIcon: const Icon(
                                      Icons.local_offer_rounded,
                                      color: WalletColors.blue),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                onPressed:
                                    (_loading || _paying) ? null : _applyCoupon,
                                style: FilledButton.styleFrom(
                                  backgroundColor: WalletColors.blue,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('Aplicar'),
                              ),
                            ),
                          ],
                        ),
                ),
                if (pendingPromos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    kind: BannerKind.success,
                    icon: Icons.redeem_rounded,
                    text:
                        'Tienes la promoción "${pendingPromos.first.title}" (${pendingPromos.first.discountPercent}%) canjeada: '
                        'el Banco la aplicará sola al cobrar.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  InfoBanner(kind: BannerKind.danger, text: _error!),
                ],
                if (_quote != null) ...[
                  const SizedBox(height: 14),
                  SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row('Subtotal', formatPrice(_quote!.subtotalCents)),
                        if (_quote!.discountCents > 0)
                          _row('Descuento por cupón',
                              '-${formatPrice(_quote!.discountCents)}',
                              color: WalletColors.success),
                        const Divider(height: 20),
                        _row('Total', formatPrice(_quote!.totalCents),
                            bold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pagar con tickets del Banco',
                                style: WalletText.h3),
                            TextButton(
                              onPressed: _paying
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const TicketsPage()),
                                      ),
                              child: const Text('Comprar tickets'),
                            ),
                          ],
                        ),
                        if (activeTickets.isEmpty)
                          const Text(
                            'No tienes tickets activos. Adquiere tickets de \$50, \$100, \$200 o \$500 en el Banco.',
                            style: WalletText.muted,
                          )
                        else ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in activeTickets)
                                FilterChip(
                                  label: Text(
                                    '${formatPrice(t.amountCents)} (${t.ticketId.substring(0, 8)})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  selected:
                                      _selectedTicketIds.contains(t.ticketId),
                                  selectedColor: WalletColors.yellow,
                                  onSelected: _paying
                                      ? null
                                      : (yes) => setState(() {
                                            if (yes) {
                                              _selectedTicketIds
                                                  .add(t.ticketId);
                                            } else {
                                              _selectedTicketIds
                                                  .remove(t.ticketId);
                                            }
                                          }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ticketsCoverOrder
                                ? 'Seleccionados: ${formatPrice(selectedTotalCents)} · Cambio a tu cuenta: ${formatPrice(selectedTotalCents - _quote!.totalCents)}'
                                : 'Seleccionados: ${formatPrice(selectedTotalCents)} · Faltan ${formatPrice(_quote!.totalCents - selectedTotalCents)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ticketsCoverOrder
                                  ? WalletColors.success
                                  : WalletColors.muted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          PrimaryButton(
                            label:
                                'Pagar con Tickets (${formatPrice(selectedTotalCents)})',
                            icon: Icons.confirmation_number_rounded,
                            loading: _paying,
                            onPressed: (!_loading && ticketsCoverOrder)
                                ? () => _payWithTickets(selectedTickets)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: _paying
                        ? 'Procesando pago seguro…'
                        : 'Pagar con Wallet · ${formatPrice(_quote!.totalCents)}',
                    icon: Icons.fingerprint_rounded,
                    loading: _paying,
                    onPressed: _loading ? null : _payWithWallet,
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 14, color: WalletColors.muted),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Tu Wallet firma la orden y el Banco emite un recibo firmado',
                          textAlign: TextAlign.center,
                          style: WalletText.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
