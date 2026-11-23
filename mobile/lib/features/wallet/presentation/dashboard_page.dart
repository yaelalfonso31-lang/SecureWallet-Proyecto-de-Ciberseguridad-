import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bank/data/bank_auth_repository.dart';
import '../../bank/data/bank_repository.dart';
import '../../bank/presentation/bank_link_page.dart';
import '../../bank/presentation/tickets_page.dart';
import '../data/auth_repository.dart';
import '../data/cards_repository.dart';
import '../data/demo_wallet_store.dart';
import '../data/wallet_ledger_repository.dart';
import 'home_page.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/balance_card.dart';
import 'widgets/credit_card_view.dart';
import 'widgets/wallet_widgets.dart';

class _Action {
  const _Action(this.icon, this.label, this.onTap, {this.yellow = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool yellow;
}

/// Pestaña "Inicio": saldo, saldo en tickets, accesos rápidos, seguridad, tarjetas y últimos movimientos.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _hidden = false;

  Future<void> _refresh() async {
    ref.invalidate(cardsProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletMovementsProvider);
    ref.invalidate(bankLinkedProvider);
    ref.invalidate(bankAccountProvider);
    ref.invalidate(bankTicketsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _openTickets() async {
    var linked = await ref.read(bankAuthRepositoryProvider).isLinked();
    if (!linked) {
      if (!mounted) return;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
      );
      if (ok != true) return;
      ref.invalidate(bankLinkedProvider);
      ref.invalidate(bankAccountProvider);
      ref.invalidate(bankTicketsProvider);
      linked = true;
    }
    if (!mounted || !linked) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TicketsPage()),
    );
    ref.invalidate(bankTicketsProvider);
    ref.invalidate(bankAccountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final cards = ref.watch(cardsProvider);
    final settings = ref.watch(securitySettingsProvider);
    final realBalance = ref
        .watch(walletBalanceProvider)
        .maybeWhen(data: (b) => b, orElse: () => null);
    final ticketsBalanceCents = ref.watch(activeTicketsBalanceProvider);
    final ticketsCount = ref.watch(activeTicketsCountProvider);
    final blocked = ref.watch(blockedCardsProvider);
    final defaultId = ref.watch(defaultCardIdProvider);

    final fullName =
        profile.maybeWhen(data: (p) => p.fullName, orElse: () => '');
    final firstName =
        fullName.isEmpty ? 'bienvenido' : fullName.split(' ').first;

    final actions = <_Action>[
      _Action(Icons.send_rounded, 'Enviar', () => context.push('/money/send')),
      _Action(
        Icons.qr_code_2_rounded,
        'Recibir',
        () => context.push('/receive'),
        yellow: true,
      ),
      _Action(
        Icons.add_card_rounded,
        'Recargar',
        () => context.push('/money/topup'),
      ),
      _Action(
        Icons.account_balance_rounded,
        'Retirar',
        () => context.push('/money/withdraw'),
        yellow: true,
      ),
      _Action(
        Icons.qr_code_scanner_rounded,
        'Escanear',
        () => showWalletSnack(
          context,
          'El escáner de QR llegará pronto (demostración)',
        ),
      ),
      _Action(
        Icons.history_rounded,
        'Historial',
        () => context.push('/history'),
        yellow: true,
      ),
      _Action(
        Icons.contacts_rounded,
        'Contactos',
        () => context.push('/contacts'),
      ),
      _Action(
        Icons.shield_rounded,
        'Seguridad',
        () => context.push('/security'),
        yellow: true,
      ),
    ];

    final movementsAsync = ref.watch(walletMovementsProvider);

    return RefreshIndicator(
      color: WalletColors.blue,
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      InitialsAvatar(fullName.isEmpty ? 'SW' : fullName,
                          radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola,',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              firstName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Notificaciones',
                        onPressed: () => context.push('/notifications'),
                        icon: const Badge(
                          smallSize: 9,
                          backgroundColor: WalletColors.yellow,
                          child: Icon(
                            Icons.notifications_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BalanceCard(
                    balanceCents: realBalance ?? 0,
                    hidden: _hidden,
                    onToggle: () => setState(() => _hidden = !_hidden),
                    onSend: () => context.push('/money/send'),
                    onTopUp: () => context.push('/money/topup'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SoftCard(
              onTap: _openTickets,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const IconBadge(
                    Icons.confirmation_number_rounded,
                    size: 44,
                    color: WalletColors.navy,
                    background: WalletColors.yellowSoft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saldo en tickets', style: WalletText.muted),
                        Text(
                          _hidden
                              ? '\$ ••••••'
                              : formatMoney(ticketsBalanceCents),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: WalletColors.navy,
                          ),
                        ),
                        Text(
                          '$ticketsCount ${ticketsCount == 1 ? 'ticket disponible' : 'tickets disponibles'}',
                          style: WalletText.muted,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: WalletColors.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            childAspectRatio: 0.82,
            children: [
              for (final a in actions)
                QuickAction(
                  icon: a.icon,
                  label: a.label,
                  yellow: a.yellow,
                  onTap: a.onTap,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SoftCard(
              onTap: () => context.push('/security'),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: settings.score / 100,
                            strokeWidth: 6,
                            backgroundColor: WalletColors.line,
                            color: settings.score >= 70
                                ? WalletColors.success
                                : WalletColors.yellowDark,
                          ),
                        ),
                        Text(
                          '${settings.score}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Seguridad de tu cuenta',
                            style: WalletText.h3),
                        const SizedBox(height: 2),
                        Text(
                          settings.score >= 70
                              ? 'Muy bien, tu cuenta está bien protegida'
                              : 'Activa la huella y la verificación en dos pasos',
                          style: WalletText.muted,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: WalletColors.muted),
                ],
              ),
            ),
          ),
          SectionTitle(
            'Mis tarjetas',
            actionLabel: 'Ver todas',
            onAction: () => ref.read(homeTabProvider.notifier).select(1),
          ),
          cards.when(
            loading: () => const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: InfoBanner(
                kind: BannerKind.danger,
                text:
                    'No pudimos cargar tus tarjetas. Desliza hacia abajo para reintentar.',
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SoftCard(
                    onTap: () => context.push('/cards/add'),
                    child: const Row(
                      children: [
                        IconBadge(
                          Icons.add_card_rounded,
                          color: WalletColors.navy,
                          background: WalletColors.yellowSoft,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Agrega tu primera tarjeta para recargar y pagar',
                            style: WalletText.body,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: WalletColors.muted),
                      ],
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 165,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: list.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    if (i == list.length) {
                      return SizedBox(
                        width: 120,
                        child: SoftCard(
                          onTap: () => context.push('/cards/add'),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconBadge(
                                Icons.add_rounded,
                                color: WalletColors.navy,
                                background: WalletColors.yellowSoft,
                              ),
                              SizedBox(height: 8),
                              Text('Agregar', style: WalletText.h3),
                            ],
                          ),
                        ),
                      );
                    }
                    final card = list[i];
                    return SizedBox(
                      width: 255,
                      child: GestureDetector(
                        onTap: () => context.push('/cards/detail', extra: card),
                        child: CreditCardView(
                          brand: card.brand,
                          holder: card.holderName,
                          expiry: card.expiry,
                          last4: card.last4,
                          compact: true,
                          blocked: blocked.contains(card.id),
                          isDefault: defaultId == card.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: WalletColors.goldGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.local_offer_rounded,
                      color: WalletColors.navy, size: 34),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Promociones para ti',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: WalletColors.navy,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Revisa bonos y descuentos en la pestaña Banco',
                          style:
                              TextStyle(fontSize: 13, color: WalletColors.navy),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(
            'Últimos movimientos',
            actionLabel: 'Ver todo',
            onAction: () => context.push('/history'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: movementsAsync.when(
              loading: () => const SoftCard(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const InfoBanner(
                kind: BannerKind.danger,
                text: 'No pudimos cargar los movimientos.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const SoftCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Aún no tienes movimientos. Recarga desde tu Banco o envía dinero.',
                        style: WalletText.muted,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final recent = list.take(4).toList();
                return SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: IconBadge(
                            recent[i].isCredit
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: recent[i].isCredit
                                ? WalletColors.success
                                : WalletColors.navy,
                            background: recent[i].isCredit
                                ? const Color(0xFFE6F6EF)
                                : WalletColors.yellowSoft,
                          ),
                          title: Text(
                            recent[i].concept,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: WalletColors.ink,
                            ),
                          ),
                          subtitle: Text(
                            '${formatDate(recent[i].createdAt.toLocal())} · Saldo ${formatMoney(recent[i].balanceAfterCents)}',
                            style: WalletText.muted,
                          ),
                          trailing: Text(
                            '${recent[i].isCredit ? '+' : '-'}${formatMoney(recent[i].amountCents)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: recent[i].isCredit
                                  ? WalletColors.success
                                  : WalletColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
