import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../data/cards_repository.dart';
import '../data/wallet_models.dart';
import 'theme/wallet_palette.dart';
import 'widgets/credit_card_view.dart';
import 'widgets/wallet_widgets.dart';

/// Detalle de una tarjeta: datos enmascarados, predeterminada, bloqueo y eliminación.
class CardDetailPage extends ConsumerStatefulWidget {
  const CardDetailPage({super.key, required this.card});

  final WalletCard card;

  @override
  ConsumerState<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends ConsumerState<CardDetailPage> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Eliminar tarjeta',
      message: '¿Seguro que quieres eliminar la ${widget.card.brandLabel} terminada en ${widget.card.last4}? Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final bio = BiometricService();
    if (await bio.isAvailable()) {
      final ok = await bio.authenticate('Confirma con tu huella o PIN para eliminar la tarjeta');
      if (!ok) {
        if (mounted) showWalletSnack(context, 'No se pudo verificar tu identidad', error: true);
        return;
      }
    }
    if (!mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(cardsRepositoryProvider).delete(widget.card.id);
      ref.invalidate(cardsProvider);
      if (!mounted) return;
      showWalletSnack(context, 'Tarjeta eliminada');
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showWalletSnack(context, errorMessage(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final blocked = ref.watch(blockedCardsProvider).contains(card.id);
    final isDefault = ref.watch(defaultCardIdProvider) == card.id;

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: Text('${card.brandLabel} •••• ${card.last4}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CreditCardView(
            brand: card.brand,
            holder: card.holderName,
            expiry: card.expiry,
            last4: card.last4,
            blocked: blocked,
            isDefault: isDefault,
          ),
          const SizedBox(height: 20),
          SoftCard(
            child: Column(
              children: [
                DetailRow('Titular', card.holderName, icon: Icons.person_rounded),
                const Divider(height: 1),
                DetailRow('Marca', card.brandLabel, icon: Icons.credit_card_rounded),
                const Divider(height: 1),
                DetailRow('Vencimiento', card.expiry, icon: Icons.event_rounded),
                const Divider(height: 1),
                const DetailRow('Número completo', 'Protegido', icon: Icons.lock_rounded),
                const Divider(height: 1),
                DetailRow(
                  'Token de pago',
                  card.token,
                  icon: Icons.key_rounded,
                  trailing: IconButton(
                    tooltip: 'Copiar token',
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: card.token));
                      if (context.mounted) showWalletSnack(context, 'Token copiado');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  value: isDefault,
                  onChanged: (v) => ref.read(defaultCardIdProvider.notifier).select(v ? card.id : null),
                  secondary: const IconBadge(Icons.star_rounded, color: WalletColors.navy, background: WalletColors.yellowSoft),
                  title: const Text('Tarjeta predeterminada', style: WalletText.h3),
                  subtitle: const Text('Se usará primero al pagar', style: WalletText.muted),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: blocked,
                  onChanged: (v) => ref.read(blockedCardsProvider.notifier).setBlocked(card.id, v),
                  secondary: const IconBadge(Icons.lock_rounded),
                  title: const Text('Bloquear temporalmente', style: WalletText.h3),
                  subtitle: const Text('Evita usos mientras no la necesitas', style: WalletText.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const InfoBanner(
            kind: BannerKind.warning,
            text: 'Predeterminada y bloqueo son de demostración: se guardan solo en este teléfono por ahora.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(_deleting ? 'Eliminando…' : 'Eliminar tarjeta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WalletColors.danger,
                side: const BorderSide(color: WalletColors.danger, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
