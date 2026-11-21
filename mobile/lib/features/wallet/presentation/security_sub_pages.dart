import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/demo_wallet_store.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Dispositivos y sesiones (demostración).
class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Dispositivos y sesiones')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SoftCard(
            child: Row(
              children: [
                IconBadge(Icons.phone_android_rounded, color: WalletColors.navy, background: WalletColors.yellowSoft),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Este dispositivo', style: WalletText.h3),
                      Text('Android · activo ahora', style: WalletText.muted),
                    ],
                  ),
                ),
                StatusChip(label: 'Actual', icon: Icons.check_circle_rounded),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Row(
              children: [
                const IconBadge(Icons.laptop_mac_rounded),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Navegador web', style: WalletText.h3),
                      Text('Hace 2 días', style: WalletText.muted),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => showWalletSnack(context, 'Sesión cerrada (demostración)'),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const InfoBanner(
            kind: BannerKind.warning,
            text: 'Lista de demostración. TODO: mostrar las sesiones reales del backend y permitir cerrarlas a distancia.',
          ),
        ],
      ),
    );
  }
}

/// Límites por operación y diarios (demostración, se aplican en Enviar / Recargar / Retirar).
class LimitsPage extends ConsumerStatefulWidget {
  const LimitsPage({super.key});

  @override
  ConsumerState<LimitsPage> createState() => _LimitsPageState();
}

class _LimitsPageState extends ConsumerState<LimitsPage> {
  late double _perTx;
  late double _daily;

  @override
  void initState() {
    super.initState();
    final s = ref.read(securitySettingsProvider);
    _perTx = (s.perTxLimitCents / 100).clamp(500.0, 20000.0).toDouble();
    _daily = (s.dailyLimitCents / 100).clamp(1000.0, 50000.0).toDouble();
  }

  void _save() {
    final notifier = ref.read(securitySettingsProvider.notifier);
    notifier.replace(
      ref.read(securitySettingsProvider).copyWith(
            perTxLimitCents: (_perTx * 100).round(),
            dailyLimitCents: (_daily * 100).round(),
          ),
    );
    showWalletSnack(context, 'Límites actualizados');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Límites de transacción')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    IconBadge(Icons.swap_horiz_rounded),
                    SizedBox(width: 12),
                    Text('Límite por operación', style: WalletText.h3),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney((_perTx * 100).round()),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: WalletColors.blue),
                ),
                Slider(
                  value: _perTx,
                  min: 500,
                  max: 20000,
                  divisions: 39,
                  label: '\$${_perTx.round()}',
                  onChanged: (v) => setState(() => _perTx = v),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    IconBadge(Icons.today_rounded, color: WalletColors.navy, background: WalletColors.yellowSoft),
                    SizedBox(width: 12),
                    Text('Límite diario', style: WalletText.h3),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney((_daily * 100).round()),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: WalletColors.blue),
                ),
                Slider(
                  value: _daily,
                  min: 1000,
                  max: 50000,
                  divisions: 49,
                  label: '\$${_daily.round()}',
                  onChanged: (v) => setState(() => _daily = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const InfoBanner(text: 'Un límite bajo reduce el daño si alguien accede a tu cuenta.'),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Guardar límites', icon: Icons.check_rounded, onPressed: _save),
        ],
      ),
    );
  }
}

class _LogEvent {
  const _LogEvent(this.icon, this.title, this.detail, this.when, {this.warn = false});

  final IconData icon;
  final String title;
  final String detail;
  final String when;
  final bool warn;
}

/// Bitácora de actividad (demostración). En el backend existe `audit_log` con hashes encadenados.
class ActivityLogPage extends StatelessWidget {
  const ActivityLogPage({super.key});

  static const _events = [
    _LogEvent(Icons.login_rounded, 'Inicio de sesión', 'Este dispositivo', 'Hoy · 09:12'),
    _LogEvent(Icons.add_card_rounded, 'Tarjeta agregada', 'Visa •••• 1111', 'Hoy · 09:14'),
    _LogEvent(Icons.verified_user_rounded, 'Pago autorizado', 'Orden firmada con Ed25519', 'Ayer · 18:40'),
    _LogEvent(Icons.warning_amber_rounded, 'Intento de acceso fallido', 'Contraseña incorrecta', 'Hace 3 días', warn: true),
    _LogEvent(Icons.lock_rounded, 'Cuenta bloqueada 15 min', '5 intentos fallidos', 'Hace 3 días', warn: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Bitácora de actividad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoBanner(
            icon: Icons.link_rounded,
            text: 'En el backend cada evento se encadena con un hash al anterior: si alguien altera un registro, la cadena se rompe.',
          ),
          const SizedBox(height: 16),
          for (final e in _events)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: IconBadge(
                    e.icon,
                    color: e.warn ? WalletColors.danger : WalletColors.blue,
                    background: e.warn ? const Color(0xFFFDECEC) : WalletColors.ice,
                  ),
                  title: Text(e.title, style: WalletText.h3),
                  subtitle: Text(e.detail, style: WalletText.muted),
                  trailing: Text(e.when, style: WalletText.muted),
                ),
              ),
            ),
          const InfoBanner(kind: BannerKind.warning, text: 'Eventos de demostración.'),
        ],
      ),
    );
  }
}
