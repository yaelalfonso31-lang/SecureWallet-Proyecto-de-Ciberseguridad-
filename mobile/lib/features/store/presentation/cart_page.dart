import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../data/cart_provider.dart';
import '../data/store_repository.dart';
import 'payment_result_page.dart';
import 'store_page.dart' show formatPrice, productsProvider;

class _PayException implements Exception {
  const _PayException(this.message);
  final String message;
}

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
  String? _payError;
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
    if (!mounted) return;
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

  Future<void> _pay() async {
    final quote = _quote;
    final lines = ref.read(cartProvider);
    if (quote == null || lines.isEmpty || _paying || _loading) return;

    setState(() {
      _paying = true;
      _payError = null;
    });
    final repo = ref.read(storeRepositoryProvider);

    try {
      // 1) Biometría antes de cualquier operación sensible.
      if (!await _biometric.isAvailable()) {
        throw const _PayException('Configura un PIN o huella en el dispositivo para poder pagar');
      }
      final confirmed = await _biometric.authenticate('Confirma el pago de ${formatPrice(quote.totalCents)}');
      if (!confirmed) throw const _PayException('Pago cancelado: no se confirmó tu identidad');

      // 2) Crear la orden. El servidor vuelve a calcular el total.
      final order = await repo.createOrder(lines, coupon: quote.couponCode);

      // 3) Solo se firma el monto que el usuario vio y confirmó.
      if (order.amountCents != quote.totalCents) {
        await _refresh();
        throw _PayException('El total cambió a ${formatPrice(order.amountCents)}. Revisa tu carrito.');
      }

      // 4) La Wallet firma la orden y 5) la Tienda la cobra con el Banco.
      final signed = await repo.authorize(order);
      final paid = await repo.pay(order, signed);

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider); // refresca existencias del catálogo
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PaymentResultPage(paid: paid)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _payError = e is _PayException ? e.message : errorMessage(e);
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
    final scheme = Theme.of(context).colorScheme;

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
                          onPressed: (_paying || l.quantity >= kMaxQtyPerProduct)
                              ? null
                              : () => cart.add(l.productId, l.name),
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
                if (_error != null)
                  Text(_error!, style: TextStyle(color: scheme.error))
                else if (_quote != null) ...[
                  _row('Subtotal', formatPrice(_quote!.subtotalCents)),
                  if (_quote!.discountCents > 0) _row('Descuento', '-${formatPrice(_quote!.discountCents)}'),
                  const SizedBox(height: 4),
                  _row('Total', formatPrice(_quote!.totalCents), bold: true),
                ],
                const SizedBox(height: 24),
                if (_payError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_payError!, style: TextStyle(color: scheme.error)),
                  ),
                FilledButton.icon(
                  onPressed: (_quote == null || _error != null || _loading || _paying) ? null : _pay,
                  icon: _paying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.account_balance_wallet),
                  label: Text(_paying ? 'Procesando…' : 'Pagar con Wallet'),
                ),
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