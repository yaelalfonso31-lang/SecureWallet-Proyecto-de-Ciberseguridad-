import 'package:flutter/material.dart';

import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

class _Notice {
  const _Notice(this.icon, this.title, this.text, this.when, {this.unread = false, this.yellow = false});

  final IconData icon;
  final String title;
  final String text;
  final String when;
  final bool unread;
  final bool yellow;
}

/// Notificaciones (demostración).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _allRead = false;

  static const _items = [
    _Notice(Icons.shield_rounded, 'Nuevo inicio de sesión', 'Detectamos un acceso desde este dispositivo.', 'Hace 5 min', unread: true),
    _Notice(Icons.local_offer_rounded, '¡Bono disponible!', 'Tienes 10% de descuento en tu próxima compra.', 'Hace 2 h', unread: true, yellow: true),
    _Notice(Icons.check_circle_rounded, 'Pago exitoso', 'Tu pago en Café Central fue procesado.', 'Ayer'),
    _Notice(Icons.tips_and_updates_rounded, 'Consejo de seguridad', 'Activa la verificación en dos pasos para proteger tu cuenta.', 'Hace 2 días', yellow: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          IconButton(
            tooltip: 'Marcar todo como leído',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () => setState(() => _allRead = true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final n in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: IconBadge(
                    n.icon,
                    color: n.yellow ? WalletColors.navy : WalletColors.blue,
                    background: n.yellow ? WalletColors.yellowSoft : WalletColors.ice,
                  ),
                  title: Text(n.title, style: WalletText.h3),
                  subtitle: Text('${n.text}\n${n.when}', style: WalletText.muted),
                  isThreeLine: true,
                  trailing: n.unread && !_allRead
                      ? const Icon(Icons.circle, size: 10, color: WalletColors.yellowDark)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
