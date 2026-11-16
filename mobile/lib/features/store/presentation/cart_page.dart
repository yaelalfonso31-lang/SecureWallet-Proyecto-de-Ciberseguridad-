import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../wallet/data/cards_repository.dart';
import '../data/cart_provider.dart';
import '../data/store_repository.dart';
import 'store_page.dart' show formatPrice, productsProvider;

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  final _couponCtrl = TextEditingController();
  final _biometric = BiometricService();
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

      // 2) Ejecutar el flujo completo de pago (Tienda -> Wallet -> Tienda -> Banco).
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

      // 3) Limpiar el carrito y refrescar el catálogo para actualizar el stock.
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider);
      setState(() => _paying = false);

      // 4) Mostrar el recibo firmado por el Banco.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _ReceiptSheet(result: result),
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cartProvider, (_, __) => _refresh());
    final lines = ref.watch(cartProvider);
    final cart = ref.read(cartProvider.notifier);
    final priceByProduct = {for (final l in _quote?.lines ?? const <QuoteLine>[]) l.productId: l};
    final appliedCoupon = _quote?.couponCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      body: lines.isEmpty
          ? const Center(child: Text('Tu carrito está vacío'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading || _paying) const LinearProgressIndicator(),
                for (final l in lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: priceByProduct[l.productId] == null
                        ? null
                        : Text(formatPrice(priceByProduct[l.productId]!.unitPriceCents)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _paying ? null : () => cart.decrement(l.productId),
                        ),
                        Text('${l.quantity}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: (!_paying && l.quantity < kMaxQtyPerProduct)
                              ? () => cart.add(l.productId, l.name)
                              : null,
                        ),
                        IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _paying ? null : () => cart.remove(l.productId),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 32),
                if (appliedCoupon != null)
                  Chip(
                    avatar: const Icon(Icons.local_offer, size: 18),
                    label: Text('Cupón $appliedCoupon'),
                    onDeleted: _paying ? null : _removeCoupon,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponCtrl,
                          enabled: !_paying,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 32,
                          decoration: InputDecoration(
                            labelText: 'Cupón de descuento',
                            counterText: '',
                            errorText: _couponError,
                          ),
                          onSubmitted: (_) => _applyCoupon(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (_loading || _paying) ? null : _applyCoupon,
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                if (_quote != null) ...[
                  _row('Subtotal', formatPrice(_quote!.subtotalCents)),
                  if (_quote!.discountCents > 0)
                    _row('Descuento cupón', '-${formatPrice(_quote!.discountCents)}'),
                  const SizedBox(height: 4),
                  _row('Total', formatPrice(_quote!.totalCents), bold: true),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: (_loading || _paying) ? null : _payWithWallet,
                    icon: _paying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint),
                    label: Text(
                      _paying
                          ? 'Procesando pago seguro…'
                          : 'Pagar con Wallet (${formatPrice(_quote!.totalCents)})',
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.result});

  final PaymentResult result;

  @override
  Widget build(BuildContext context) {
    final receipt = result.receipt;
    final amountCents = (receipt['amount_cents'] as int?) ?? 0;
    final bankDiscountCents = (receipt['discount_cents'] as int?) ?? 0;
    final chargedCents = (receipt['charged_cents'] as int?) ?? amountCents;
    final receiptId = '${receipt['receipt_id'] ?? ''}';
    final orderHash = '${receipt['order_hash'] ?? ''}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 56),
            const SizedBox(height: 12),
            Text(
              '¡Pago aprobado!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Firma Ed25519 del Banco verificada',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 28),
            _detail('Orden', result.orderId),
            _detail('Recibo', receiptId),
            _detail('Monto de la orden', formatPrice(amountCents)),
            if (bankDiscountCents > 0)
              _detail('Descuento promoción Banco', '-${formatPrice(bankDiscountCents)}'),
            _detail('Total cargado en Banco', formatPrice(chargedCents), bold: true),
            if (orderHash.isNotEmpty)
              _detail(
                'Hash SHA-256 orden',
                orderHash.length > 16 ? '${orderHash.substring(0, 16)}…' : orderHash,
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}