import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bank/presentation/bank_page.dart';
import '../../store/presentation/store_page.dart';
import 'cards_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'theme/wallet_palette.dart';

/// Pestaña activa de la barra inferior. Otras pantallas pueden cambiarla con
class HomeTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    state = index;
  }
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, int>(HomeTabNotifier.new);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const _titles = ['Inicio', 'Mis tarjetas', 'Banco', 'Tienda', 'Mi perfil'];
  static const _pages = <Widget>[
    DashboardPage(),
    CardsPage(),
    BankPage(),
    StorePage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider);
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: index == 0
          ? null
          : AppBar(
              backgroundColor: WalletColors.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              title: Text(_titles[index], style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: [
                IconButton(
                  tooltip: 'Notificaciones',
                  icon: const Icon(Icons.notifications_rounded),
                  onPressed: () => context.push('/notifications'),
                ),
              ],
            ),
      body: _pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: Colors.white,
        indicatorColor: WalletColors.yellow,
        onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).select(i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: WalletColors.navy),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon: Icon(Icons.credit_card_rounded, color: WalletColors.navy),
            label: 'Tarjetas',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance_rounded, color: WalletColors.navy),
            label: 'Banco',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded, color: WalletColors.navy),
            label: 'Tienda',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: WalletColors.navy),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
