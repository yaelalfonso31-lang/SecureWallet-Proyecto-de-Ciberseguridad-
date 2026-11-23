import 'package:flutter/material.dart';

import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/store_models.dart';
import '../data/store_repository.dart';

/// Precio en pesos con separador de miles ($1,299.00).
String formatPrice(int cents) => formatMoney(cents);

/// Icono según el nombre del producto (y la categoría como respaldo).
IconData iconForName(String name, [String category = '']) {
  final n = name.toLowerCase();
  if (n.contains('audífono') || n.contains('audifono')) {
    return Icons.headphones_rounded;
  }
  if (n.contains('bocina')) return Icons.speaker_rounded;
  if (n.contains('teclado')) return Icons.keyboard_rounded;
  if (n.contains('mouse')) return Icons.mouse_rounded;
  if (n.contains('cargador')) return Icons.bolt_rounded;
  if (n.contains('cable')) return Icons.usb_rounded;
  if (n.contains('mochila')) return Icons.backpack_rounded;
  if (n.contains('soporte')) return Icons.laptop_mac_rounded;
  if (n.contains('libro')) return Icons.menu_book_rounded;
  return categoryIcon(category);
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'Audio':
      return Icons.headphones_rounded;
    case 'Computación':
      return Icons.computer_rounded;
    case 'Accesorios':
      return Icons.backpack_rounded;
    case 'Libros':
      return Icons.menu_book_rounded;
    default:
      return Icons.shopping_bag_rounded;
  }
}

IconData productIcon(StoreProduct p) => iconForName(p.name, p.category);

String orderStatusLabel(String status) {
  switch (status) {
    case 'paid':
      return 'Pagada';
    case 'cancelled':
      return 'Cancelada';
    default:
      return 'Pendiente de pago';
  }
}

Color orderStatusColor(String status) {
  switch (status) {
    case 'paid':
      return WalletColors.success;
    case 'cancelled':
      return WalletColors.muted;
    default:
      return WalletColors.yellowDark;
  }
}

IconData orderStatusIcon(String status) {
  switch (status) {
    case 'paid':
      return Icons.check_circle_rounded;
    case 'cancelled':
      return Icons.cancel_rounded;
    default:
      return Icons.schedule_rounded;
  }
}

/// Tarjeta de producto del catálogo.
class ProductCard extends StatelessWidget {
  const ProductCard(
      {super.key,
      required this.product,
      required this.onTap,
      required this.onAdd});

  final StoreProduct product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [WalletColors.ice, WalletColors.yellowSoft],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(
              children: [
                Center(
                    child: Icon(productIcon(product),
                        size: 52, color: WalletColors.navy)),
                if (product.soldOut)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: StatusChip(
                        label: 'Agotado', color: WalletColors.danger),
                  )
                else if (product.lowStock)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StatusChip(
                        label: 'Quedan ${product.stock}',
                        color: WalletColors.yellowDark),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: WalletColors.ink,
                        height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(product.category,
                      style: WalletText.muted.copyWith(fontSize: 12)),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatPrice(product.priceCents),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: WalletColors.blue),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Agregar al carrito',
                        onPressed: product.soldOut ? null : onAdd,
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: WalletColors.yellow,
                          foregroundColor: WalletColors.navy,
                          disabledBackgroundColor: WalletColors.line,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _short(String value, [int keep = 16]) =>
    value.length > keep ? '${value.substring(0, keep)}…' : value;

/// Recibo firmado por el Banco: montos, método de pago (cuenta o tickets), huella y estado de firma.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.orderId,
    required this.receipt,
    required this.signature,
    this.verified,
  });

  final String orderId;
  final Map<String, dynamic> receipt;
  final String signature;

  /// true = firma válida, false = inválida, null = aún no se verifica.
  final bool? verified;

  @override
  Widget build(BuildContext context) {
    final amount = (receipt['amount_cents'] as int?) ?? 0;
    final bankDiscount = (receipt['discount_cents'] as int?) ?? 0;
    final charged = (receipt['charged_cents'] as int?) ?? amount;
    final orderHash = '${receipt['order_hash'] ?? ''}';

    final isTickets = receipt['payment_method'] == 'tickets';
    final ticketIds = (receipt['ticket_ids'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final ticketsTotal = (receipt['tickets_total_cents'] as int?) ?? 0;
    final changeCents = (receipt['change_cents'] as int?) ?? 0;

    final StatusChip badge;
    if (verified == null) {
      badge = const StatusChip(
          label: 'Firma sin verificar',
          color: WalletColors.muted,
          icon: Icons.help_outline_rounded);
    } else if (verified!) {
      badge = const StatusChip(
          label: 'Firma Ed25519 del Banco válida',
          icon: Icons.verified_rounded);
    } else {
      badge = const StatusChip(
          label: 'Firma NO válida',
          color: WalletColors.danger,
          icon: Icons.gpp_bad_rounded);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(height: 8),
        DetailRow('Orden', _short(orderId, 18), icon: Icons.tag_rounded),
        DetailRow('Recibo', _short('${receipt['receipt_id'] ?? ''}', 18),
            icon: Icons.receipt_long_rounded),
        DetailRow('Monto de la orden', formatPrice(amount),
            icon: Icons.shopping_bag_rounded),
        if (isTickets) ...[
          DetailRow(
            'Método de pago',
            'Tickets electrónicos (${ticketIds.length})',
            icon: Icons.confirmation_number_rounded,
          ),
          if (ticketIds.isNotEmpty)
            DetailRow(
              'Tickets usados',
              ticketIds.map((id) => _short(id, 12)).join(', '),
              icon: Icons.qr_code_rounded,
            ),
          if (ticketsTotal > 0)
            DetailRow('Valor en tickets', formatPrice(ticketsTotal),
                icon: Icons.payments_rounded),
          if (changeCents > 0)
            DetailRow('Cambio devuelto al Banco', formatPrice(changeCents),
                icon: Icons.savings_rounded),
        ] else ...[
          if (bankDiscount > 0)
            DetailRow('Promoción del Banco', '-${formatPrice(bankDiscount)}',
                icon: Icons.local_offer_rounded),
          DetailRow('Cargado en tu cuenta', formatPrice(charged),
              icon: Icons.account_balance_rounded),
        ],
        if (orderHash.isNotEmpty)
          DetailRow('Huella SHA-256', _short(orderHash),
              icon: Icons.fingerprint_rounded),
        if (signature.isNotEmpty)
          DetailRow('Firma', _short(signature), icon: Icons.draw_rounded),
      ],
    );
  }
}

/// Hoja con el recibo después de pagar.
Future<void> showReceiptSheet(BuildContext context, PaymentResult result) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                    gradient: WalletColors.goldGradient,
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 52, color: WalletColors.navy),
              ),
            ),
            const SizedBox(height: 14),
            const Text('¡Pago aprobado!',
                textAlign: TextAlign.center, style: WalletText.h1),
            const SizedBox(height: 14),
            ReceiptView(
              orderId: result.orderId,
              receipt: result.receipt,
              signature: result.signature,
              verified: result.signatureVerified,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
                label: 'Listo',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    ),
  );
}
