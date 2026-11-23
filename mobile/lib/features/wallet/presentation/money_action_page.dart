import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../bank/data/bank_auth_repository.dart';
import '../../bank/data/bank_repository.dart';
import '../../bank/presentation/bank_link_page.dart';
import '../data/cards_repository.dart';
import '../data/demo_wallet_store.dart';
import '../data/wallet_ledger_repository.dart';
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

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Pantalla única para Enviar (P2P), Recargar y Retirar contra el backend real.
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
  final _recipientEmail = TextEditingController();
  WalletCard? _card;
  bool _useBankAccount = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Los contactos de demostración tienen alias tipo "@ana.lopez", que no es un correo:
    // solo se precarga si el alias es un correo completo.
    final alias = widget.initialContact?.alias ?? '';
    if (_emailPattern.hasMatch(alias)) {
      _recipientEmail.text = alias;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _recipientEmail.dispose();
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

  Future<void> _openBankLink() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const BankLinkPage()),
    );
    if (ok == true) {
      ref.invalidate(bankLinkedProvider);
      ref.invalidate(bankAccountProvider);
      ref.invalidate(bankTicketsProvider);
      if (mounted) setState(() => _error = null);
    }
  }

  String? _validate({
    required bool bankLinked,
    required BankAccount? bankAccount,
    required int walletBalance,
  }) {
    final settings = ref.read(securitySettingsProvider);
    if (settings.emergencyLock) {
      return 'Tu wallet está bloqueada. Desactiva el bloqueo de emergencia en Seguridad.';
    }
    if (_cents <= 0) return 'Escribe un monto mayor a cero';
    if (_cents > settings.perTxLimitCents) {
      return 'Supera tu límite por operación (${formatMoney(settings.perTxLimitCents)})';
    }

    if (widget.action == MoneyAction.send) {
      if (_cents > walletBalance) return 'Saldo insuficiente en tu Wallet';
      if (!_emailPattern.hasMatch(_recipientEmail.text.trim())) {
        return 'Escribe el correo electrónico completo del destinatario';
      }
      return null;
    }

    if (!bankLinked) {
      return 'Primero vincula o abre tu cuenta del Banco para mover dinero real';
    }

    if (widget.action == MoneyAction.topUp) {
      if (bankAccount != null && _cents > bankAccount.balanceCents) {
        return 'Tu cuenta del Banco solo tiene ${formatMoney(bankAccount.balanceCents)}';
      }
      if (_card == null && !_useBankAccount) {
        return 'Elige tu tarjeta o cuenta bancaria de origen';
      }
    }

    if (widget.action == MoneyAction.withdraw) {
      if (_cents > walletBalance) {
        return 'Tu Wallet solo tiene ${formatMoney(walletBalance)}';
      }
    }

    return null;
  }

  String _targetLabel(BankAccount? bankAccount) {
    final masked = bankAccount?.numberMasked ?? 'Cuenta Azul';
    switch (widget.action) {
      case MoneyAction.send:
        return _recipientEmail.text.trim();
      case MoneyAction.topUp:
        if (_card != null) {
          return '${_card!.brandLabel} •••• ${_card!.last4} (Banco $masked)';
        }
        return 'Cuenta Azul $masked';
      case MoneyAction.withdraw:
        return 'Cuenta Azul $masked';
    }
  }

  Future<void> _continue({
    required bool bankLinked,
    required BankAccount? bankAccount,
    required int walletBalance,
  }) async {
    final error = _validate(
      bankLinked: bankLinked,
      bankAccount: bankAccount,
      walletBalance: walletBalance,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);

    final target = _targetLabel(bankAccount);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _ConfirmSheet(
        title: _title,
        icon: _icon,
        amountCents: _cents,
        target: target,
        note: _note.text.trim(),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final bio = BiometricService();
      if (await bio.isAvailable()) {
        final ok =
            await bio.authenticate('Confirma la operación con tu huella o PIN');
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

      // Comprobante que se muestra en la pantalla de éxito. El importe lleva signo:
      // positivo si entra dinero a la Wallet y negativo si sale.
      final WalletTransaction tx;
      if (widget.action == MoneyAction.topUp) {
        await ref.read(bankRepositoryProvider).rechargeWallet(_cents);
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(walletMovementsProvider);
        ref.invalidate(bankAccountProvider);
        tx = WalletTransaction(
          id: 'topup_${DateTime.now().millisecondsSinceEpoch}',
          kind: TxKind.topUp,
          title: 'Recarga desde Banco',
          subtitle: target,
          amountCents: _cents,
          date: DateTime.now(),
          counterparty: '',
          createdAt: DateTime.now(),
        );
      } else if (widget.action == MoneyAction.withdraw) {
        await ref.read(bankRepositoryProvider).withdrawToBank(_cents);
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(walletMovementsProvider);
        ref.invalidate(bankAccountProvider);
        tx = WalletTransaction(
          id: 'withdraw_${DateTime.now().millisecondsSinceEpoch}',
          kind: TxKind.withdraw,
          title: 'Retiro a Banco',
          subtitle: target,
          amountCents: -_cents,
          date: DateTime.now(),
          counterparty: '',
          createdAt: DateTime.now(),
        );
      } else {
        final transfer =
            await ref.read(walletLedgerRepositoryProvider).transfer(
                  recipientEmail: _recipientEmail.text.trim(),
                  amountCents: _cents,
                  note: _note.text.trim(),
                );
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(walletMovementsProvider);
        tx = WalletTransaction(
          id: transfer.transferId,
          kind: TxKind.sent,
          title: 'Envío a ${transfer.recipientName}',
          subtitle: transfer.recipientEmail,
          amountCents: -transfer.amountCents,
          date: transfer.createdAt.toLocal(),
          counterparty: '',
          createdAt: transfer.createdAt.toLocal(),
        );
      }

      if (!mounted) return;
      context.pushReplacement('/success', extra: tx);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  Widget _linkBankCard(String message) {
    return Column(
      children: [
        InfoBanner(kind: BannerKind.warning, text: message),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Vincular o abrir cuenta del Banco',
          icon: Icons.link_rounded,
          onPressed: _busy ? null : _openBankLink,
        ),
      ],
    );
  }

  Widget _selector({
    required bool bankLinked,
    required BankAccount? bankAccount,
  }) {
    switch (widget.action) {
      case MoneyAction.send:
        return WalletTextField(
          controller: _recipientEmail,
          label: 'Correo del destinatario',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() => _error = null),
        );

      case MoneyAction.topUp:
        if (!bankLinked) {
          return _linkBankCard(
            'Vincula tu cuenta del Banco para que tus recargas se reflejen en el saldo real de tu Wallet.',
          );
        }
        final cards = ref.watch(cardsProvider);
        return Column(
          children: [
            _SelectTile(
              icon: Icons.account_balance_rounded,
              title: 'Cuenta Azul ${bankAccount?.numberMasked ?? ''}',
              subtitle: bankAccount == null
                  ? 'Cargando saldo del Banco…'
                  : 'Disponible en Banco: ${formatMoney(bankAccount.balanceCents)}',
              selected: _useBankAccount && _card == null,
              onTap: () => setState(() {
                _useBankAccount = true;
                _card = null;
                _error = null;
              }),
            ),
            cards.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (list) => Column(
                children: [
                  for (final c in list)
                    _SelectTile(
                      icon: Icons.credit_card_rounded,
                      title: '${c.brandLabel} •••• ${c.last4}',
                      subtitle:
                          'Vence ${c.expiry} · Cargo a tu cuenta bancaria',
                      selected: _card?.id == c.id,
                      onTap: () => setState(() {
                        _card = c;
                        _useBankAccount = false;
                        _error = null;
                      }),
                    ),
                ],
              ),
            ),
          ],
        );

      case MoneyAction.withdraw:
        if (!bankLinked) {
          return _linkBankCard(
            'Vincula tu cuenta del Banco para recibir tus retiros con comprobante firmado.',
          );
        }
        return _SelectTile(
          icon: Icons.account_balance_rounded,
          title: 'Cuenta Azul ${bankAccount?.numberMasked ?? ''}',
          subtitle: bankAccount == null
              ? 'Cargando cuenta vinculada…'
              : 'Saldo actual en Banco: ${formatMoney(bankAccount.balanceCents)}',
          selected: true,
          onTap: () => setState(() => _error = null),
        );
    }
  }

  String get _selectorTitle {
    switch (widget.action) {
      case MoneyAction.send:
        return 'Enviar a';
      case MoneyAction.topUp:
        return 'Origen de fondos (sincronizado con Banco)';
      case MoneyAction.withdraw:
        return 'Cuenta bancaria vinculada';
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletBalance = ref
        .watch(walletBalanceProvider)
        .maybeWhen(data: (b) => b, orElse: () => 0);

    final bankLinked = ref
        .watch(bankLinkedProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final bankAccount = bankLinked
        ? ref
            .watch(bankAccountProvider)
            .maybeWhen(data: (a) => a, orElse: () => null)
        : null;

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
                IconBadge(
                  _icon,
                  size: 52,
                  color: WalletColors.navy,
                  background: WalletColors.yellowSoft,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,7}(\.\d{0,2})?')),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: WalletColors.navy,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0.00',
                    prefixText: '\$ ',
                  ),
                ),
                Text(
                  'Saldo en Wallet: ${formatMoney(walletBalance)}',
                  style: WalletText.muted,
                ),
                if (bankAccount != null && widget.action != MoneyAction.send)
                  Text(
                    'Saldo en Banco: ${formatMoney(bankAccount.balanceCents)}',
                    style: WalletText.muted,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final q in quick)
                      ActionChip(
                        label: Text('\$$q',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
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
          SectionTitle(_selectorTitle,
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
          _selector(bankLinked: bankLinked, bankAccount: bankAccount),
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
            onPressed: () => _continue(
              bankLinked: bankLinked,
              bankAccount: bankAccount,
              walletBalance: walletBalance,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint_rounded,
                  size: 16, color: WalletColors.muted),
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
        border: Border.all(
          color: selected ? WalletColors.yellowDark : WalletColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: IconBadge(icon),
        title: Text(title, style: WalletText.h3),
        subtitle: Text(subtitle, style: WalletText.muted),
        trailing: Icon(
          selected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
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
              decoration: BoxDecoration(
                color: WalletColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            IconBadge(
              icon,
              size: 56,
              color: WalletColors.navy,
              background: WalletColors.yellowSoft,
            ),
            const SizedBox(height: 12),
            Text('Confirmar: $title', style: WalletText.h2),
            const SizedBox(height: 4),
            Text(
              formatMoney(amountCents),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: WalletColors.blue,
              ),
            ),
            const SizedBox(height: 12),
            DetailRow(
              'Destinatario / Cuenta',
              target,
              icon: Icons.flag_rounded,
            ),
            if (note.isNotEmpty)
              DetailRow(
                'Mensaje',
                note,
                icon: Icons.chat_bubble_outline_rounded,
              ),
            const DetailRow('Comisión', 'Sin costo',
                icon: Icons.savings_rounded),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Confirmar',
              icon: Icons.fingerprint_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
