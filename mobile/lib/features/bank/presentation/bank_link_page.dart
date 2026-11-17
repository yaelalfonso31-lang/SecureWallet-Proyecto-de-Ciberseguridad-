import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_auth_repository.dart';
import 'bank_widgets.dart';

/// Vincular una cuenta existente del Banco o abrir una nueva (simulación).
class BankLinkPage extends ConsumerStatefulWidget {
  const BankLinkPage({super.key});

  @override
  ConsumerState<BankLinkPage> createState() => _BankLinkPageState();
}

class _BankLinkPageState extends ConsumerState<BankLinkPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _openNew = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _passwordOk =>
      _password.text.length >= 10 &&
      RegExp(r'[A-Za-z]').hasMatch(_password.text) &&
      RegExp(r'\d').hasMatch(_password.text);

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña del Banco');
      return;
    }
    if (_openNew) {
      if (!_passwordOk) {
        setState(() => _error = 'La contraseña debe tener 10 o más caracteres, con letras y números');
        return;
      }
      if (_password.text != _confirm.text) {
        setState(() => _error = 'Las contraseñas no coinciden');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(bankAuthRepositoryProvider);
      if (_openNew) {
        await repo.openAccount(email: email, password: _password.text);
      } else {
        await repo.link(email: email, password: _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e, validation: 'Revisa tus datos: el correo debe ser válido y la contraseña de 10+ caracteres con letras y números'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Tu cuenta del Banco')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: IconBadge(Icons.account_balance_rounded, size: 84, color: WalletColors.navy, background: WalletColors.yellowSoft),
          ),
          const SizedBox(height: 16),
          Text(
            _openNew ? 'Abre tu cuenta en minutos' : 'Vincula tu cuenta',
            textAlign: TextAlign.center,
            style: WalletText.h1,
          ),
          const SizedBox(height: 6),
          Text(
            _openNew
                ? 'Es una cuenta de práctica: la abrimos con saldo de demostración.'
                : 'Entra con el correo y la contraseña de tu cuenta del Banco.',
            textAlign: TextAlign.center,
            style: WalletText.muted.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: false, icon: Icon(Icons.link_rounded), label: Text('Ya tengo cuenta')),
              ButtonSegment<bool>(value: true, icon: Icon(Icons.add_circle_outline_rounded), label: Text('Abrir cuenta')),
            ],
            selected: {_openNew},
            onSelectionChanged: (selection) => setState(() {
              _openNew = selection.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          WalletTextField(
            controller: _email,
            label: 'Correo del Banco',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          WalletTextField(
            controller: _password,
            label: _openNew ? 'Crea una contraseña' : 'Contraseña del Banco',
            icon: Icons.lock_rounded,
            obscure: _obscure,
            onChanged: (_) => setState(() {}),
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (_openNew) ...[
            const SizedBox(height: 14),
            WalletTextField(
              controller: _confirm,
              label: 'Confirmar contraseña',
              icon: Icons.lock_reset_rounded,
              obscure: _obscure,
              errorText: _confirm.text.isNotEmpty && _confirm.text != _password.text ? 'Las contraseñas no coinciden' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _passwordOk ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: _passwordOk ? WalletColors.success : WalletColors.muted,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('10 o más caracteres, con letras y números', style: WalletText.muted)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            InfoBanner(text: _error!, kind: BannerKind.danger),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: _openNew ? 'Abrir y vincular cuenta' : 'Vincular cuenta',
            icon: _openNew ? Icons.add_card_rounded : Icons.link_rounded,
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          const InfoBanner(
            icon: Icons.shield_rounded,
            text: 'Tu Wallet certifica quién eres con una firma digital y el Banco te entrega un acceso temporal. '
                'La app nunca guarda tu contraseña del Banco.',
          ),
        ],
      ),
    );
  }
}
