import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Pantalla de recuperación de contraseña (DEMOSTRACIÓN: aún no envía correos).
/// TODO equipo Wallet: conectar con un endpoint que envíe un enlace firmado de un solo uso.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          const Center(
            child: IconBadge(
              Icons.lock_reset_rounded,
              size: 96,
              color: WalletColors.navy,
              background: WalletColors.yellowSoft,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _sent ? '¡Revisa tu correo!' : '¿Olvidaste tu contraseña?',
            textAlign: TextAlign.center,
            style: WalletText.h1,
          ),
          const SizedBox(height: 10),
          Text(
            _sent
                ? 'Si el correo está registrado, recibirás un enlace seguro de un solo uso para crear una contraseña nueva.'
                : 'Escribe tu correo y te enviaremos un enlace seguro para crear una contraseña nueva.',
            textAlign: TextAlign.center,
            style: WalletText.muted.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 28),
          if (!_sent) ...[
            WalletTextField(
              controller: _email,
              label: 'Correo electrónico',
              icon: Icons.email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Enviar enlace',
              icon: Icons.send_rounded,
              onPressed: () {
                if (_email.text.contains('@')) {
                  setState(() => _sent = true);
                } else {
                  showWalletSnack(context, 'Escribe un correo válido', error: true);
                }
              },
            ),
          ] else
            PrimaryButton(
              label: 'Volver a iniciar sesión',
              icon: Icons.login_rounded,
              blue: true,
              onPressed: () => context.pop(),
            ),
          const SizedBox(height: 20),
          const InfoBanner(
            kind: BannerKind.warning,
            text: 'Función de demostración: el envío de correos todavía no está conectado al backend.',
          ),
        ],
      ),
    );
  }
}
