import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/biometric_service.dart';
import '../../wallet/data/wallet_ledger_repository.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_repository.dart';
import 'bank_widgets.dart';

/// Mover dinero entre el Banco y la Wallet con comprobantes firmados (Ed25519) en ambos sentidos.
class TransferPage extends ConsumerStatefulWidget {
  const TransferPage({super.key, this.initialWithdraw = false});

  final bool initialWithdraw;

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final _amount = TextEditingController();
  final _biometric = BiometricService();
  late bool _withdraw = widget.initialWithdraw;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int get _cents => ((double.tryParse(_amount.text) ?? 0) * 100).round();

  Future<void> _submit() async {
    final cents = _cents;
    if (cents <= 0) {
      setState(() => _error = 'Escribe un monto mayor a cero');
      return;
    }
    final walletBalance = ref.read(walletBalanceProvider).maybeWhen(data: (b) => b, orElse: () => null);
    final bankBalance = ref.read(bankAccountProvider).maybeWhen(data: (a) => a.balanceCents, orElse: () => null);
    if (_withdraw && walletBalance != null && cents > walletBalance) {
      setState(() => _error = 'Tu Wallet solo tiene ${formatMoney(walletBalance)}');
      return;
    }
    if (!_withdraw && bankBalance != null && cents > bankBalance) {
      setState(() => _error = 'Tu cuenta del Banco solo tiene ${formatMoney(bankBalance)}');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await _biometric.isAvailable()) {
        final ok = await _biometric.authenticate(
          _withdraw ? 'Confirma el retiro de ${formatMoney(cents)}' : 'Confirma la recarga de ${formatMoney(cents)}',
        );
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
      final repo = ref.read(bankRepositoryProvider);
      final outcome = _withdraw ? await repo.withdrawToBank(cents) : await repo.rechargeWallet(cents);

      ref.invalidate(walletBalanceProvider);
      ref.invalidate(bankAccountProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _amount.clear();
      });
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) => _SuccessSheet(withdraw: _withdraw, amountCents: cents, outcome: outcome),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, validation: 'Revisa el monto e inténtalo de nuevo');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletBalanceProvider).maybeWhen(data: (b) => b, orElse: () => null);
    final bank = ref.watch(bankAccountProvider).maybeWhen(data: (a) => a.balanceCents, orElse: () => null);
    final quick = [100, 500, 1000, 2000];

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Mover dinero')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: false, icon: Icon(Icons.south_west_rounded), label: Text('Recargar Wallet')),
              ButtonSegment<bool>(value: true, icon: Icon(Icons.north_east_rounded), label: Text('Retirar al Banco')),
            ],
            selected: {_withdraw},
            onSelectionChanged: (selection) => setState(() {
              _withdraw = selection.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _BalanceBox(
                  icon: Icons.account_balance_rounded,
                  label: 'Banco',
                  cents: bank,
                  highlight: !_withdraw,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  _withdraw ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                  color: WalletColors.blue,
                ),
              ),
              Expanded(
                child: _BalanceBox(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Wallet',
                  cents: wallet,
                  highlight: _withdraw,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              children: [
                Text(_withdraw ? '¿Cuánto quieres retirar?' : '¿Cuánto quieres recargar?', style: WalletText.h3),
                TextField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?'))],
                  onChanged: (_) => setState(() => _error = null),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: WalletColors.navy),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: '0.00', prefixText: '\$ '),
                ),
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
          if (_error != null) ...[
            const SizedBox(height: 14),
            InfoBanner(text: _error!, kind: BannerKind.danger),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            label: _withdraw ? 'Retirar a mi cuenta' : 'Recargar mi Wallet',
            icon: Icons.fingerprint_rounded,
            loading: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          InfoBanner(
            icon: Icons.verified_user_rounded,
            text: _withdraw
                ? 'La Wallet descuenta tu saldo y firma un comprobante; el Banco verifica la firma antes de abonar.'
                : 'El Banco descuenta de tu cuenta y firma un comprobante; la Wallet verifica la firma antes de abonar. '
                    'El mismo comprobante nunca se abona dos veces.',
          ),
        ],
      ),
    );
  }
}

class _BalanceBox extends StatelessWidget {
  const _BalanceBox({required this.icon, required this.label, required this.cents, required this.highlight});

  final IconData icon;
  final String label;
  final int? cents;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? WalletColors.yellowDark : WalletColors.line, width: highlight ? 2 : 1),
      ),
      child: Column(
        children: [
          IconBadge(icon, size: 40, color: WalletColors.navy, background: highlight ? WalletColors.yellowSoft : WalletColors.ice),
          const SizedBox(height: 8),
          Text(label, style: WalletText.muted),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              cents == null ? '—' : formatMoney(cents!),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  const _SuccessSheet({required this.withdraw, required this.amountCents, required this.outcome});

  final bool withdraw;
  final int amountCents;
  final TransferOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(gradient: WalletColors.goldGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 52, color: WalletColors.navy),
            ),
            const SizedBox(height: 14),
            Text(withdraw ? '¡Retiro listo!' : '¡Recarga lista!', style: WalletText.h1),
            const SizedBox(height: 4),
            Text(
              formatMoney(amountCents),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: WalletColors.blue),
            ),
            const SizedBox(height: 12),
            DetailRow('Saldo en la Wallet', formatMoney(outcome.walletBalanceCents), icon: Icons.account_balance_wallet_rounded),
            DetailRow('Saldo en el Banco', formatMoney(outcome.bankBalanceCents), icon: Icons.account_balance_rounded),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Listo', icon: Icons.check_rounded, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
