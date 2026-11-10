import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _accepted = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasLength => _password.text.length >= 10;
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_password.text);
  bool get _hasDigit => RegExp(r'\d').hasMatch(_password.text);
  bool get _hasSymbol => RegExp(r'[^A-Za-z0-9]').hasMatch(_password.text);

  /// 0 a 4 según los requisitos cumplidos.
  int get _strength => [_hasLength, _hasLetter, _hasDigit, _hasSymbol].where((e) => e).length;

  bool get _passwordOk => _hasLength && _hasLetter && _hasDigit;

  bool get _canSubmit =>
      _name.text.trim().length >= 2 &&
      _email.text.contains('@') &&
      _passwordOk &&
      _password.text == _confirm.text &&
      _accepted;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.register(
        email: _email.text.trim(),
        fullName: _name.text.trim(),
        password: _password.text,
      );
      await repo.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      context.go('/onboarding');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _rule(bool ok, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: ok ? WalletColors.success : WalletColors.muted,
            ),
            const SizedBox(width: 8),
            Text(text, style: WalletText.muted.copyWith(color: ok ? WalletColors.ink : WalletColors.muted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final labels = ['Muy débil', 'Débil', 'Media', 'Buena', 'Fuerte'];
    final colors = [
      WalletColors.danger,
      WalletColors.danger,
      WalletColors.yellowDark,
      WalletColors.blue,
      WalletColors.success,
    ];
    final strength = _password.text.isEmpty ? 0 : _strength;
    return Scaffold(
      backgroundColor: WalletColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(
              padding: const EdgeInsets.fromLTRB(8, 40, 24, 48),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Crear cuenta', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Solo toma un minuto', style: TextStyle(color: WalletColors.yellow, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const WalletLogo(size: 48),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SoftCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WalletTextField(
                        controller: _name,
                        label: 'Nombre completo',
                        icon: Icons.badge_rounded,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      WalletTextField(
                        controller: _email,
                        label: 'Correo electrónico',
                        icon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      WalletTextField(
                        controller: _password,
                        label: 'Contraseña',
                        icon: Icons.lock_rounded,
                        obscure: _obscure,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: strength / 4,
                                minHeight: 8,
                                backgroundColor: WalletColors.line,
                                color: colors[strength],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            labels[strength],
                            style: TextStyle(fontWeight: FontWeight.w800, color: colors[strength], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _rule(_hasLength, 'Mínimo 10 caracteres'),
                      _rule(_hasLetter, 'Incluye letras'),
                      _rule(_hasDigit, 'Incluye números'),
                      _rule(_hasSymbol, 'Un símbolo la hace más fuerte (opcional)'),
                      const SizedBox(height: 14),
                      WalletTextField(
                        controller: _confirm,
                        label: 'Confirmar contraseña',
                        icon: Icons.lock_reset_rounded,
                        obscure: _obscure,
                        onChanged: (_) => setState(() {}),
                        errorText: _confirm.text.isNotEmpty && _confirm.text != _password.text
                            ? 'Las contraseñas no coinciden'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _accepted,
                        onChanged: (v) => setState(() => _accepted = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Acepto los términos y el aviso de privacidad',
                          style: WalletText.body,
                        ),
                      ),
                      if (_error != null) ...[
                        InfoBanner(text: _error!, kind: BannerKind.danger),
                        const SizedBox(height: 12),
                      ],
                      PrimaryButton(
                        label: 'Registrarme',
                        icon: Icons.check_rounded,
                        loading: _loading,
                        onPressed: _canSubmit ? _submit : null,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Ya tengo cuenta'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
