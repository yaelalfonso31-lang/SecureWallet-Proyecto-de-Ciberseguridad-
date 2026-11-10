import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../data/cards_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/credit_card_view.dart';
import 'widgets/wallet_widgets.dart';

/// Pestaña "Tarjetas": lista de tarjetas reales (GET /cards) como tarjetas visuales.
class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    final blocked = ref.watch(blockedCardsProvider);
    final defaultId = ref.watch(defaultCardIdProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/cards/add'),
        backgroundColor: WalletColors.yellow,
        foregroundColor: WalletColors.ink,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Agregar tarjeta', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: () async {
          ref.invalidate(cardsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: cards.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
              const SizedBox(height: 12),
              const Text('Desliza hacia abajo para reintentar.', style: WalletText.muted),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.credit_card_off_rounded,
                    title: 'Aún no tienes tarjetas',
                    message: 'Agrega una tarjeta para recargar saldo y pagar. Se guarda cifrada y nunca pedimos el CVV.',
                    actionLabel: 'Agregar tarjeta',
                    onAction: () => context.push('/cards/add'),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                const InfoBanner(
                  icon: Icons.verified_user_rounded,
                  text: 'Tus tarjetas se guardan cifradas (AES-256). Nunca guardamos el CVV.',
                ),
                const SizedBox(height: 16),
                for (final card in list) ...[
                  GestureDetector(
                    onTap: () => context.push('/cards/detail', extra: card),
                    child: CreditCardView(
                      brand: card.brand,
                      holder: card.holderName,
                      expiry: card.expiry,
                      last4: card.last4,
                      blocked: blocked.contains(card.id),
                      isDefault: defaultId == card.id,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${card.brandLabel} •••• ${card.last4}', style: WalletText.h3),
                      const Spacer(),
                      if (defaultId == card.id) const StatusChip(label: 'Predeterminada', color: WalletColors.yellowDark, icon: Icons.star_rounded),
                      if (blocked.contains(card.id)) const StatusChip(label: 'Bloqueada', color: WalletColors.danger, icon: Icons.lock_rounded),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
