import 'package:flutter_riverpod/flutter_riverpod.dart';

const int kMaxQtyPerProduct = 20; // igual que el límite del backend

class CartLine {
  const CartLine({required this.productId, required this.name, required this.quantity});

  final int productId;
  final String name;
  final int quantity;

  CartLine copyWith({int? quantity}) =>
      CartLine(productId: productId, name: name, quantity: quantity ?? this.quantity);
}

class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  void add(int productId, String name) {
    final i = state.indexWhere((l) => l.productId == productId);
    if (i == -1) {
      state = [...state, CartLine(productId: productId, name: name, quantity: 1)];
    } else if (state[i].quantity < kMaxQtyPerProduct) {
      state = [
        for (var j = 0; j < state.length; j++)
          if (j == i) state[j].copyWith(quantity: state[j].quantity + 1) else state[j],
      ];
    }
  }

  void decrement(int productId) {
    state = [
      for (final l in state)
        if (l.productId != productId)
          l
        else if (l.quantity > 1)
          l.copyWith(quantity: l.quantity - 1),
    ];
  }

  void remove(int productId) => state = state.where((l) => l.productId != productId).toList();

  void clear() => state = const [];
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (sum, l) => sum + l.quantity),
);