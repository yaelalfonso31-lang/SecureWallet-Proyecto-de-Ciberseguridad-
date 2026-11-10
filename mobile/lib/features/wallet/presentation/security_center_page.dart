import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/biometric_service.dart';
import '../data/demo_wallet_store.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Centro de seguridad: nivel de protección, activar/desactivar protecciones y administrar.
/// La biometría es real (local_auth); el resto de interruptores son de demostración.
class SecurityCenterPage extends ConsumerStatefulWidget {
  const SecurityCenterPage({super.key});

  @override
  ConsumerState<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends ConsumerState<SecurityCenterPage> {
  void _update(SecuritySettings Function(SecuritySettings) change) {
    final notifier = ref.read(securitySettingsProvider.notifier);
    notifier.replace(change(ref.read(securitySettingsProvider)));
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!value) {
      _update((s) => s.copyWith(biometric: false));
      return;
    }
    final bio = BiometricService();
    if (!await bio.isAvailable()) {
      if (mounted) {
        showWalletSnack(context, 'Tu teléfono no tiene huella, rostro ni bloqueo de pantalla configurado.', error: true);
      }
      return;
    }
    final ok = await bio.authenticate('Confirma para activar la verificación biométrica');
    if (!mounted) return;
    if (ok) {
      _update((s) => s.copyWith(biometric: true));
      showWalletSnack(context, 'Verificación biométrica activada');
    } else {
      showWalletSnack(context, 'No se pudo verificar tu identidad', error: true);
    }
  }

  Future<void> _toggleTwoFactor(bool value) async {
    if (!value) {
      _update((s) => s.copyWith(twoFactor: false));
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Verificación en dos pasos',
      message: 'Usarás una app autenticadora para generar un código temporal (TOTP) al iniciar sesión. '
          'Esta pantalla es una demostración: falta conectarla al backend.',
      confirmLabel: 'Activar',
    );
    if (ok) _update((s) => s.copyWith(twoFactor: true));
  }

  Future<void> _toggleEmergency(bool value) async {
    if (!value) {
      _update((s) => s.copyWith(emergencyLock: false));
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Bloqueo de emergencia',
      message: 'Se bloquearán envíos, recargas y retiros hasta que lo desactives. ¿Continuar?',
      confirmLabel: 'Bloquear',
      danger: true,
    );
    if (ok) _update((s) => s.copyWith(emergencyLock: true));
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool danger = false,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: IconBadge(
        icon,
        color: danger ? WalletColors.danger : WalletColors.blue,
        background: danger ? const Color(0xFFFDECEC) : WalletColors.ice,
      ),
      title: Text(title, style: WalletText.h3),
      subtitle: Text(subtitle, style: WalletText.muted),
    );
  }

  Widget _linkTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: IconBadge(icon, color: WalletColors.navy, background: WalletColors.yellowSoft),
      title: Text(title, style: WalletText.h3),
      subtitle: Text(subtitle, style: WalletText.muted),
      trailing: const Icon(Icons.chevron_right_rounded, color: WalletColors.muted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(securitySettingsProvider);
    final level = s.score >= 85 ? 'Excelente' : (s.score >= 60 ? 'Buena' : 'Mejorable');
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Centro de seguridad')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CircularProgressIndicator(
                          value: s.score / 100,
                          strokeWidth: 9,
                          backgroundColor: Colors.white24,
                          color: WalletColors.yellow,
                        ),
                      ),
                      Text('${s.score}%', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nivel de seguridad', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(level, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text(
                        'Activa más protecciones para llegar al 100%',
                        style: TextStyle(color: WalletColors.yellow, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Protecciones'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _switchTile(
                    icon: Icons.fingerprint_rounded,
                    title: 'Huella o rostro',
                    subtitle: 'Confirma pagos y cambios sensibles',
                    value: s.biometric,
                    onChanged: _toggleBiometric,
                  ),
                  const Divider(height: 1),
                  _switchTile(
                    icon: Icons.phonelink_lock_rounded,
                    title: 'Verificación en dos pasos',
                    subtitle: 'Código temporal (TOTP) al iniciar sesión',
                    value: s.twoFactor,
                    onChanged: _toggleTwoFactor,
                  ),
                  const Divider(height: 1),
                  _switchTile(
                    icon: Icons.notifications_active_rounded,
                    title: 'Alertas de inicio de sesión',
                    subtitle: 'Te avisamos de accesos nuevos',
                    value: s.loginAlerts,
                    onChanged: (v) => _update((x) => x.copyWith(loginAlerts: v)),
                  ),
                  const Divider(height: 1),
                  _switchTile(
                    icon: Icons.block_rounded,
                    title: 'Bloqueo de emergencia',
                    subtitle: 'Detiene todas las operaciones al instante',
                    value: s.emergencyLock,
                    onChanged: _toggleEmergency,
                    danger: true,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Administrar'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _linkTile(Icons.devices_rounded, 'Dispositivos y sesiones', 'Dónde está abierta tu cuenta', () => context.push('/security/sessions')),
                  const Divider(height: 1),
                  _linkTile(Icons.speed_rounded, 'Límites de transacción', 'Controla cuánto puedes mover', () => context.push('/security/limits')),
                  const Divider(height: 1),
                  _linkTile(Icons.manage_search_rounded, 'Bitácora de actividad', 'Historial de eventos de seguridad', () => context.push('/security/log')),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: InfoBanner(
              kind: BannerKind.warning,
              text: 'Solo la huella funciona con el teléfono. El resto de los interruptores son de demostración y se conectarán al backend.',
            ),
          ),
        ],
      ),
    );
  }
}
