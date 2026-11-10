import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/biometric_service.dart';
import '../data/cards_repository.dart';
import '../data/demo_wallet_store.dart';
import '../data/wallet_models.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

enum MoneyAction { send, topUp, withdraw }

MoneyAction moneyActionFromPath(String? value) {
  switch (value) {
    case 'topup':
      return MoneyAction.topUp;
    case 'withdraw':
      return MoneyAction.withdraw;
    default:
      return MoneyAction.send;
  }
}

/// Pantalla única para Enviar, Recargar y Retirar (cambia el selector según la acción).
/// DEMOSTRACIÓN: mueve el saldo local. TODO: conectar con el backend (firma de la orden de pago).
class MoneyActionPage extends ConsumerStatefulWidget {
  const MoneyActionPage({super.key, required this.action, this.initialContact});

  final MoneyAction action;
  final WalletContact? initialContact;

  @override
  ConsumerState<MoneyActionPage> createState() => _MoneyActionPageState();
}

class _MoneyActionPageState extends ConsumerState<MoneyActionPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  WalletContact? _contact;
  WalletCard? _card;
  BankAccountInfo? _account;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.initialContact;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _cents => ((double.tryParse(_amount.text) ?? 0) * 100).round();

  String get _title {
    switch (widget.action) {
      case MoneyAction.send:
        return 'Enviar dinero';
      case MoneyAction.topUp:
        return 'Recargar saldo';
      case MoneyAction.withdraw:
        return 'Retirar a banco';
    }
  }

  IconData get _icon {
    switch (widget.action) {
      case MoneyAction.send:
        return Icons.send_rounded;
      case MoneyAction.topUp:
        return Icons.add_card_rounded;
      case MoneyAction.withdraw:
        return Icons.account_balance_rounded;
    }
  }

  String? _validate() {
    final settings = ref.read(securitySettingsProvider);
    final balance = ref.read(demoWalletProvider).balanceCents;
    if (settings.emergencyLock) return 'Tu wallet está bloqueada. Desactiva el bloqueo de emergencia en Seguridad.';
    if (_cents <= 0) return 'Escribe un monto mayor a cero';
    if (_cents > settings.perTxLimitCents) return 'Supera tu límite por operación (${formatMoney(settings.perTxLimitCents)})';
    if (widget.action != MoneyAction.topUp && _cents > balance) return 'Saldo insuficiente';
    if (widget.action == MoneyAction.send && _contact == null) return 'Elige a quién quieres enviar';
    if (widget.action == MoneyAction.topUp && _card == null) return 'Elige la tarjeta de origen';
    if (widget.action == MoneyAction.withdraw && _account == null) return 'Elige la cuenta de destino';
    return null;
  }

  String get _targetLabel {
    switch (widget.action) {
      case MoneyAction.send:
        return _contact?.name ?? '';
      case MoneyAction.topUp:
        return _card == null ? '' : '${_card!.brandLabel} •••• ${_card!.last4}';
      case MoneyAction.withdraw:
        return _account == null ? '' : '${_account!.bank} •••• ${_account!.last4}';
    }
  }

  Future<void> _continue() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => _ConfirmSheet(
        title: _title,
        icon: _icon,
        amountCents: _cents,
        target: _targetLabel,
        note: _note.text.trim(),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final bio = BiometricService();
    if (await bio.isAvailable()) {
      final ok = await bio.authenticate('Confirma la operación con tu huella o PIN');
      if (!ok) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'No se pudo verificar tu identidad';
          });
        }
        return;
      }
    }
    if (!mounted) return;

    final notifier = ref.read(demoWalletProvider.notifier);
    final tx = switch (widget.action) {
      MoneyAction.send => notifier.send(_contact!, _cents, note: _note.text.trim()),
      MoneyAction.topUp => notifier.topUp(_targetLabel, _cents),
      MoneyAction.withdraw => notifier.withdraw(_targetLabel, _cents),
    };
    context.pushReplacement('/success', extra: tx);
  }

  Widget _selector() {
    switch (widget.action) {
      case MoneyAction.send:
        final contacts = ref.watch(demoWalletProvider).contacts;
        return SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: contacts.length + 1,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              if (i == contacts.length) {
                return GestureDetector(
                  onTap: () => context.push('/contacts'),
                  child: const Column(
                    children: [
                      IconBadge(Icons.person_add_alt_1_rounded, size: 56, color: WalletColors.navy, background: WalletColors.yellowSoft),
                      SizedBox(height: 6),
                      Text('Nuevo', style: WalletText.muted),
                    ],
                  ),
                );
              }
              final contact = contacts[i];
              final selected = _contact?.alias == contact.alias;
              return GestureDetector(
                onTap: () => setState(() {
                  _contact = contact;
                  _error = null;
                }),
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? WalletColors.yellowDark : Colors.transparent, width: 3),
                        ),
                        child: InitialsAvatar(
                          contact.name,
                          radius: 24,
                          background: selected ? WalletColors.yellow : WalletColors.ice,
                          foreground: WalletColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        contact.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      case MoneyAction.topUp:
        final cards = ref.watch(cardsProvider);
        return cards.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const InfoBanner(kind: BannerKind.danger, text: 'No pudimos cargar tus tarjetas.'),
          data: (list) {
            if (list.isEmpty) {
              return Column(
                children: [
                  const InfoBanner(kind: BannerKind.warning, text: 'Necesitas una tarjeta para recargar.'),
                  const SizedBox(height: 12),
                  SecondaryButton(label: 'Agregar tarjeta', icon: Icons.add_card_rounded, onPressed: () => context.push('/cards/add')),
                ],
              );
            }
            return Column(
              children: [
                for (final c in list)
                  _SelectTile(
                    icon: Icons.credit_card_rounded,
                    title: '${c.brandLabel} •••• ${c.last4}',
                    subtitle: 'Vence ${c.expiry}',
                    selected: _card?.id == c.id,
                    onTap: () => setState(() {
                      _card = c;
                      _error = null;
                    }),
                  ),
              ],
            );
          },
        );
      case MoneyAction.withdraw:
        return Column(
          children: [
            for (final a in demoBankAccounts)
              _SelectTile(
                icon: Icons.account_balance_rounded,
                title: a.bank,
                subtitle: 'Cuenta •••• ${a.last4}',
                selected: _account?.last4 == a.last4,
                onTap: () => setState(() {
                  _account = a;
                  _error = null;
                }),
              ),
          ],
        );
    }
  }

  String get _selectorTitle {
    switch (widget.action) {
      case MoneyAction.send:
        return 'Enviar a';
      case MoneyAction.topUp:
        return 'Desde qué tarjeta';
      case MoneyAction.withdraw:
        return 'A qué cuenta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(demoWalletProvider).balanceCents;
    final quick = [100, 200, 500, 1000];
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              children: [
                IconBadge(_icon, size: 52, color: WalletColors.navy, background: WalletColors.yellowSoft),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?'))],
                  onChanged: (_) => setState(() => _error = null),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: WalletColors.navy),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0.00',
                    prefixText: '\$ ',
                  ),
                ),
                Text('Saldo disponible: ${formatMoney(balance)}', style: WalletText.muted),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final q in quick)
                      ActionChip(
                        label: Text('\$$q', style: const TextStyle(fontWeight: FontWeight.w800)),
                        backgroundColor: WalletColors.yellowSoft,
                        side: BorderSide.none,
                        onPressed: () => setState(() {
                          _amount.text = '$q';
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SectionTitle(_selectorTitle, padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
          _selector(),
          if (widget.action == MoneyAction.send) ...[
            const SizedBox(height: 16),
            WalletTextField(
              controller: _note,
              label: 'Mensaje (opcional)',
              icon: Icons.chat_bubble_outline_rounded,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            InfoBanner(text: _error!, kind: BannerKind.danger),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Continuar',
            icon: Icons.arrow_forward_rounded,
            loading: _busy,
            onPressed: _continue,
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint_rounded, size: 16, color: WalletColors.muted),
              SizedBox(width: 6),
              Text('Confirmarás con tu huella o PIN', style: WalletText.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? WalletColors.yellowDark : WalletColors.line, width: selected ? 2 : 1),
      ),
      child: ListTile(
        onTap: onTap,
        leading: IconBadge(icon),
        title: Text(title, style: WalletText.h3),
        subtitle: Text(subtitle, style: WalletText.muted),
        trailing: Icon(
          selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: selected ? WalletColors.yellowDark : WalletColors.muted,
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.icon,
    required this.amountCents,
    required this.target,
    required this.note,
  });

  final String title;
  final IconData icon;
  final int amountCents;
  final String target;
  final String note;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: WalletColors.line, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 20),
            IconBadge(icon, size: 56, color: WalletColors.navy, background: WalletColors.yellowSoft),
            const SizedBox(height: 12),
            Text('Confirmar: $title', style: WalletText.h2),
            const SizedBox(height: 4),
            Text(
              formatMoney(amountCents),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: WalletColors.blue),
            ),
            const SizedBox(height: 12),
            DetailRow('Destino', target, icon: Icons.flag_rounded),
            if (note.isNotEmpty) DetailRow('Mensaje', note, icon: Icons.chat_bubble_outline_rounded),
            const DetailRow('Comisión', 'Sin costo', icon: Icons.savings_rounded),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Confirmar',
              icon: Icons.fingerprint_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}
