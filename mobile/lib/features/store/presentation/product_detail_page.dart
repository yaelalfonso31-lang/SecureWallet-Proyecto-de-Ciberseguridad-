import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/cart_provider.dart';
import '../data/store_models.dart';
import 'cart_page.dart';
import 'store_widgets.dart';

/// Detalle del producto con botón para agregarlo al carrito.
class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage({super.key, required this.product});

  final StoreProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    final inCart = ref.watch(cartProvider).where((l) => l.productId == product.id).fold<int>(0, (s, l) => s + l.quantity);

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: Text(product.category)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [WalletColors.ice, WalletColors.yellowSoft],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: WalletColors.softShadow,
            ),
            child: Center(child: Icon(productIcon(product), size: 110, color: WalletColors.navy)),
          ),
          const SizedBox(height: 20),
          Text(product.name, style: WalletText.h1),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusChip(label: product.category, color: WalletColors.blue, icon: categoryIcon(product.category)),
              const SizedBox(width: 8),
              if (product.soldOut)
                const StatusChip(label: 'Agotado', color: WalletColors.danger, icon: Icons.block_rounded)
              else if (product.lowStock)
                StatusChip(label: 'Quedan ${product.stock}', color: WalletColors.yellowDark, icon: Icons.hourglass_bottom_rounded)
              else
                const StatusChip(label: 'Disponible', icon: Icons.check_circle_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatPrice(product.priceCents),
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: WalletColors.blue),
          ),
          const SizedBox(height: 12),
          Text(product.description, style: WalletText.body.copyWith(fontSize: 15)),
          if (inCart > 0) ...[
            const SizedBox(height: 14),
            InfoBanner(icon: Icons.shopping_cart_rounded, text: 'Ya tienes $inCart en tu carrito.'),
          ],
          const SizedBox(height: 18),
          const SoftCard(
            child: Column(
              children: [
                DetailRow('Pago', 'Con tu Wallet', icon: Icons.account_balance_wallet_rounded),
                Divider(height: 1),
                DetailRow('Seguridad', 'Orden firmada digitalmente', icon: Icons.verified_user_rounded),
                Divider(height: 1),
                DetailRow('Comprobante', 'Recibo firmado por el Banco', icon: Icons.receipt_long_rounded),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PrimaryButton(
                  label: product.soldOut ? 'Agotado' : 'Agregar al carrito',
                  icon: Icons.add_shopping_cart_rounded,
                  onPressed: product.soldOut
                      ? null
                      : () {
                          ref.read(cartProvider.notifier).add(product.id, product.name);
                          showWalletSnack(context, '${product.name} agregado al carrito');
                        },
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 10),
                SizedBox(
                  height: 54,
                  width: 64,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CartPage())),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WalletColors.blue,
                      side: const BorderSide(color: WalletColors.blue, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Badge(label: Text('$count'), child: const Icon(Icons.shopping_cart_rounded)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
