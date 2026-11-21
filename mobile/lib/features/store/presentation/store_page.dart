import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/cart_provider.dart';
import '../data/store_models.dart';
import '../data/store_repository.dart';
import 'cart_page.dart';
import 'orders_page.dart';
import 'product_detail_page.dart';
import 'store_widgets.dart';

// `formatPrice` y `productsProvider` se siguen exportando desde aquí para no romper imports existentes.
export '../data/store_repository.dart' show productsProvider;
export 'store_widgets.dart' show formatPrice;

/// Pestaña "Tienda": búsqueda, categorías y catálogo en cuadrícula.
class StorePage extends ConsumerStatefulWidget {
  const StorePage({super.key});

  @override
  ConsumerState<StorePage> createState() => _StorePageState();
}

class _StorePageState extends ConsumerState<StorePage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(storeSearchProvider.notifier).setQuery(value);
    });
    setState(() {});
  }

  void _clearSearch() {
    _search.clear();
    ref.read(storeSearchProvider.notifier).setQuery('');
    setState(() {});
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _add(StoreProduct p) {
    ref.read(cartProvider.notifier).add(p.id, p.name);
    showWalletSnack(context, '${p.name} agregado al carrito');
  }

  Future<void> _refresh() async {
    ref.invalidate(productsProvider);
    ref.invalidate(categoriesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final categories = ref.watch(categoriesProvider).maybeWhen(data: (c) => c, orElse: () => const <String>[]);
    final selected = ref.watch(storeCategoryProvider);
    final count = ref.watch(cartCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const CartPage()),
        backgroundColor: WalletColors.yellow,
        foregroundColor: WalletColors.ink,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.shopping_cart_rounded),
        ),
        label: const Text('Carrito', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GradientHeader(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const IconBadge(Icons.storefront_rounded, size: 44, color: WalletColors.navy, background: WalletColors.yellow),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('SecureStore', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                                Text('Paga seguro con tu Wallet', style: TextStyle(color: WalletColors.yellow, fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Mis pedidos',
                            onPressed: () => _open(const OrdersPage()),
                            icon: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextField(
                          controller: _search,
                          onChanged: _onSearchChanged,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.ink),
                          decoration: InputDecoration(
                            hintText: 'Buscar productos',
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search_rounded, color: WalletColors.blue),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clearSearch),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  children: [
                    _CategoryChip(
                      label: 'Todo',
                      icon: Icons.apps_rounded,
                      selected: selected == null,
                      onTap: () => ref.read(storeCategoryProvider.notifier).select(null),
                    ),
                    for (final c in categories)
                      _CategoryChip(
                        label: c,
                        icon: categoryIcon(c),
                        selected: selected == c,
                        onTap: () => ref.read(storeCategoryProvider.notifier).select(c),
                      ),
                  ],
                ),
              ),
            ),
            products.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Sin resultados',
                      message: 'No encontramos productos con esa búsqueda o categoría.',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final p = list[i];
                        return ProductCard(
                          product: p,
                          onTap: () => _open(ProductDetailPage(product: p)),
                          onAdd: () => _add(p),
                        );
                      },
                      childCount: list.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 18, color: selected ? WalletColors.navy : WalletColors.blue),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: WalletColors.yellow,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? WalletColors.yellowDark : WalletColors.line),
        labelStyle: TextStyle(fontWeight: FontWeight.w800, color: selected ? WalletColors.ink : WalletColors.muted),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
