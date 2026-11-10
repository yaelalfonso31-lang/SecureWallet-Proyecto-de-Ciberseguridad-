import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/cart_provider.dart';
import '../data/store_repository.dart';
import 'store_page.dart' show formatPrice;

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  final _couponCtrl = TextEditingController();
  Quote? _quote;
  String? _coupon; // cupón que se está intentando aplicar
  String? _couponError;
  String? _error;
  bool _loading = false;
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
                if (_loading) const LinearProgressIndicator(),
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
                          onPressed: () => cart.decrement(l.productId),
                        ),
                        Text('${l.quantity}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: l.quantity < kMaxQtyPerProduct
                              ? () => cart.add(l.productId, l.name)
                              : null,
                        ),
                        IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => cart.remove(l.productId),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 32),
                if (appliedCoupon != null)
                  Chip(
                    avatar: const Icon(Icons.local_offer, size: 18),
                    label: Text('Cupón $appliedCoupon'),
                    onDeleted: _removeCoupon,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponCtrl,
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
                      FilledButton(onPressed: _loading ? null : _applyCoupon, child: const Text('Aplicar')),
                    ],
                  ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                else if (_quote != null) ...[
                  _row('Subtotal', formatPrice(_quote!.subtotalCents)),
                  if (_quote!.discountCents > 0) _row('Descuento', '-${formatPrice(_quote!.discountCents)}'),
                  const SizedBox(height: 4),
                  _row('Total', formatPrice(_quote!.totalCents), bold: true),
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