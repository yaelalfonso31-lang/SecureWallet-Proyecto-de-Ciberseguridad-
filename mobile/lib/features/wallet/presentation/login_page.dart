import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../data/auth_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _biometric = BiometricService();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).login(email, _password.text);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Entrada rápida con huella: solo funciona si ya hay una sesión vigente en el teléfono.
  Future<void> _biometricLogin() async {
    final repo = ref.read(authRepositoryProvider);
    if (!await repo.hasSession()) {
      if (mounted) {
        showWalletSnack(context, 'Inicia sesión una vez con tu contraseña para usar la huella.', error: true);
      }
      return;
    }
    if (!await _biometric.isAvailable()) {
      if (mounted) {
        showWalletSnack(context, 'Tu teléfono no tiene huella ni bloqueo de pantalla.', error: true);
      }
      return;
    }
    final ok = await _biometric.authenticate('Confirma tu identidad para entrar a SecureWallet');
    if (!ok || !mounted) return;
    try {
      await repo.fetchProfile();
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (mounted) {
        showWalletSnack(context, 'Tu sesión expiró. Ingresa con tu contraseña.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(
              padding: const EdgeInsets.fromLTRB(24, 72, 24, 64),
              child: Column(
                children: [
                  const WalletLogo(size: 76),
                  const SizedBox(height: 16),
                  const Text(
                    'SecureWallet',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tu dinero, protegido',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SoftCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Iniciar sesión', style: WalletText.h2),
                          const SizedBox(height: 4),
                          const Text('Ingresa a tu cuenta para continuar', style: WalletText.muted),
                          const SizedBox(height: 20),
                          WalletTextField(
                            controller: _email,
                            label: 'Correo electrónico',
                            icon: Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: 14),
                          WalletTextField(
                            controller: _password,
                            label: 'Contraseña',
                            icon: Icons.lock_rounded,
                            obscure: _obscure,
                            textInputAction: TextInputAction.done,
                            suffix: IconButton(
                              tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            InfoBanner(text: _error!, kind: BannerKind.danger),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push('/forgot'),
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          PrimaryButton(
                            label: 'Entrar',
                            icon: Icons.login_rounded,
                            loading: _loading,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 12),
                          SecondaryButton(
                            label: 'Entrar con huella',
                            icon: Icons.fingerprint_rounded,
                            onPressed: _biometricLogin,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.go('/register'),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Crear cuenta'),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: WalletColors.muted),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Tu contraseña nunca se guarda en este teléfono',
                            textAlign: TextAlign.center,
                            style: WalletText.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
