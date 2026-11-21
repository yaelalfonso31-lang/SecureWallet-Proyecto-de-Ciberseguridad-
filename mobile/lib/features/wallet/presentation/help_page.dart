import 'package:flutter/material.dart';

import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Ayuda: preguntas frecuentes y consejos de seguridad.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _faqs = [
    ('¿Cómo agrego una tarjeta?', 'Ve a la pestaña Tarjetas y pulsa "Agregar tarjeta". Para pruebas usa la 4111 1111 1111 1111.'),
    ('¿Guardan mi CVV?', 'No. Nunca pedimos ni guardamos el CVV. El número de tarjeta se cifra y solo vemos los últimos 4 dígitos.'),
    ('¿Qué pasa si olvido mi contraseña?', 'En la pantalla de inicio de sesión pulsa "¿Olvidaste tu contraseña?" y sigue el enlace seguro que recibirás.'),
    ('¿Por qué se bloqueó mi cuenta?', 'Tras 5 intentos fallidos la cuenta se bloquea 15 minutos para protegerte de ataques de fuerza bruta.'),
    ('¿Cómo sé que un pago no fue alterado?', 'Cada pago se firma digitalmente y su comprobante tiene una huella SHA-256 que cambia si alguien modifica un dato.'),
  ];

  static const _tips = [
    (Icons.link_off_rounded, 'No abras enlaces sospechosos', 'SecureWallet nunca te pedirá tu contraseña por mensaje.'),
    (Icons.fingerprint_rounded, 'Activa la huella', 'Confirma pagos sin escribir tu contraseña.'),
    (Icons.wifi_off_rounded, 'Cuidado con el Wi-Fi público', 'Evita hacer pagos en redes abiertas.'),
    (Icons.lock_rounded, 'Usa contraseñas únicas', 'Combina letras, números y símbolos.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Ayuda y soporte')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Preguntas frecuentes', style: WalletText.h2),
          const SizedBox(height: 12),
          for (final f in _faqs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const IconBadge(Icons.help_outline_rounded, size: 38),
                    title: Text(f.$1, style: WalletText.h3),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(f.$2, style: WalletText.muted)],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Text('Consejos de seguridad', style: WalletText.h2),
          const SizedBox(height: 12),
          for (final t in _tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                child: Row(
                  children: [
                    IconBadge(t.$1, color: WalletColors.navy, background: WalletColors.yellowSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.$2, style: WalletText.h3),
                          const SizedBox(height: 2),
                          Text(t.$3, style: WalletText.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Contactar a soporte',
            icon: Icons.support_agent_rounded,
            onPressed: () => showWalletSnack(context, 'Soporte por chat: próximamente (demostración)'),
          ),
        ],
      ),
    );
  }
}
