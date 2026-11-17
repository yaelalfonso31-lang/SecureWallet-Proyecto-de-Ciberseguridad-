import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/data/wallet_ledger_repository.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_auth_repository.dart';
import '../data/bank_repository.dart';
import 'account_page.dart';
import 'bank_link_page.dart';
import 'bank_widgets.dart';
import 'promotion_detail_page.dart';
import 'transfer_page.dart';

/// Pestaña "Banco": cuenta, mover dinero, y promociones con canje real.
class BankPage extends ConsumerWidget {
  const BankPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(bankLinkedProvider);
    ref.invalidate(bankAccountProvider);
    ref.invalidate(bankPromotionsProvider);
    ref.invalidate(bankRedemptionsProvider);
    ref.invalidate(walletBalanceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(bankLinkedProvider).maybeWhen(data: (v) => v, orElse: () => false);

    return RefreshIndicator(
      color: WalletColors.blue,
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      IconBadge(Icons.account_balance_rounded, size: 44, color: WalletColors.navy, background: WalletColors.yellow),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Banco Azul', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                            Text('Banca simulada', style: TextStyle(color: WalletColors.yellow, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (linked) const _AccountSection() else const _LinkSection(),
                ],
              ),
            ),
          ),
          if (linked) ...[
            const SizedBox(height: 14),
            const _QuickActions(),
            const _BalancesRow(),
          ],
          const SectionTitle('Promociones'),
          const _PromotionsList(),
        ],
      ),
    );
  }
}

class _LinkSection extends ConsumerWidget {
  const _LinkSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conecta tu cuenta', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Vincula tu cuenta o abre una nueva para recargar tu Wallet, pagar en la tienda y canjear promociones.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Vincular o abrir cuenta',
            icon: Icons.link_rounded,
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
              );
              if (ok == true) {
                ref.invalidate(bankLinkedProvider);
                ref.invalidate(bankAccountProvider);
                ref.invalidate(bankRedemptionsProvider);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(bankAccountProvider);
    return account.when(
      loading: () => const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (e, _) => InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
      data: (a) => Column(
        children: [
          BankAccountCard(account: a, hidden: _hidden),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
              label: Text(_hidden ? 'Mostrar saldo' : 'Ocultar saldo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      childAspectRatio: 0.82,
      children: [
        QuickAction(
          icon: Icons.receipt_long_rounded,
          label: 'Mi cuenta',
          onTap: () => _open(context, const AccountPage()),
        ),
        QuickAction(
          icon: Icons.add_card_rounded,
          label: 'Recargar',
          yellow: true,
          onTap: () => _open(context, const TransferPage()),
        ),
        QuickAction(
          icon: Icons.north_east_rounded,
          label: 'Retirar',
          onTap: () => _open(context, const TransferPage(initialWithdraw: true)),
        ),
        QuickAction(
          icon: Icons.link_off_rounded,
          label: 'Desvincular',
          yellow: true,
          onTap: () async {
            final ok = await confirmDialog(
              context,
              title: 'Desvincular cuenta',
              message: 'La app dejará de acceder a tu cuenta del Banco. Podrás vincularla de nuevo cuando quieras.',
              confirmLabel: 'Desvincular',
              danger: true,
            );
            if (!ok) return;
            await ref.read(bankAuthRepositoryProvider).unlink();
            ref.invalidate(bankLinkedProvider);
            ref.invalidate(bankRedemptionsProvider);
          },
        ),
      ],
    );
  }
}

class _BalancesRow extends ConsumerWidget {
  const _BalancesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankAccountProvider).maybeWhen(data: (a) => a.balanceCents, orElse: () => null);
    final wallet = ref.watch(walletBalanceProvider).maybeWhen(data: (b) => b, orElse: () => null);

    Widget tile(IconData icon, String label, int? cents, bool yellow) {
      return Expanded(
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(
                icon,
                size: 40,
                color: yellow ? WalletColors.navy : WalletColors.blue,
                background: yellow ? WalletColors.yellowSoft : WalletColors.ice,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: WalletText.muted),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cents == null ? '—' : formatMoney(cents),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          tile(Icons.account_balance_rounded, 'En el Banco', bank, false),
          const SizedBox(width: 12),
          tile(Icons.account_balance_wallet_rounded, 'En la Wallet', wallet, true),
        ],
      ),
    );
  }
}

class _PromotionsList extends ConsumerStatefulWidget {
  const _PromotionsList();

  @override
  ConsumerState<_PromotionsList> createState() => _PromotionsListState();
}

class _PromotionsListState extends ConsumerState<_PromotionsList> {
  int? _redeeming;

  Future<void> _redeem(BankPromotion promo, bool linked) async {
    if (!linked) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
      );
      if (ok == true) {
        ref.invalidate(bankLinkedProvider);
        ref.invalidate(bankAccountProvider);
        ref.invalidate(bankRedemptionsProvider);
      }
      return;
    }
    setState(() => _redeeming = promo.id);
    try {
      await ref.read(bankRepositoryProvider).redeem(promo.id);
      ref.invalidate(bankRedemptionsProvider);
      if (mounted) {
        showWalletSnack(context, '¡Canjeada! Se aplicará sola en tu próxima compra de la Tienda');
      }
    } catch (e) {
      if (mounted) showWalletSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _redeeming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final promos = ref.watch(bankPromotionsProvider);
    final linked = ref.watch(bankLinkedProvider).maybeWhen(data: (v) => v, orElse: () => false);
    final redemptions = ref.watch(bankRedemptionsProvider).maybeWhen(
          data: (m) => m,
          orElse: () => const <int, BankRedemption>{},
        );

    return promos.when(
      loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.local_offer_rounded,
            title: 'Sin promociones por ahora',
            message: 'Cuando el Banco publique nuevas promociones las verás aquí.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final p in list)
                _PromoCard(
                  promo: p,
                  redemption: redemptions[p.id],
                  busy: _redeeming == p.id,
                  onRedeem: () => _redeem(p, linked),
                  linked: linked,
                  // Toca la tarjeta para ver el detalle (pantalla del equipo).
                  onOpenDetail: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PromotionDetailPage(
                        promotionId: p.id,
                        dio: linked ? ref.read(bankAuthDioProvider) : ref.read(bankDioProvider),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.promo,
    required this.redemption,
    required this.busy,
    required this.onRedeem,
    required this.linked,
    required this.onOpenDetail,
  });

  final BankPromotion promo;
  final BankRedemption? redemption;
  final bool busy;
  final VoidCallback onRedeem;
  final bool linked;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final r = redemption;
    Widget action;
    if (r != null && r.isPending) {
      action = const StatusChip(label: 'Canjeada · se aplica en tu próxima compra', icon: Icons.check_circle_rounded);
    } else if (r != null) {
      action = const StatusChip(label: 'Ya la usaste', color: WalletColors.muted, icon: Icons.done_all_rounded);
    } else {
      action = SizedBox(
        height: 40,
        child: FilledButton.icon(
          onPressed: busy ? null : onRedeem,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(linked ? Icons.redeem_rounded : Icons.link_rounded, size: 18),
          label: Text(linked ? 'Canjear' : 'Vincular para canjear'),
          style: FilledButton.styleFrom(
            backgroundColor: WalletColors.yellow,
            foregroundColor: WalletColors.ink,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        onTap: onOpenDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(gradient: WalletColors.goldGradient, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Text(
                        '${promo.discountPercent}%',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: WalletColors.navy),
                      ),
                      const Text('OFF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: WalletColors.navy)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(promo.title, style: WalletText.h3),
                      const SizedBox(height: 2),
                      Text(promo.description, style: WalletText.muted),
                      if (promo.validUntil != null) ...[
                        const SizedBox(height: 4),
                        Text('Vence ${formatDate(promo.validUntil!.toLocal())}', style: WalletText.muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}
