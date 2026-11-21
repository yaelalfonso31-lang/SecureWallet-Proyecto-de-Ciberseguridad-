import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'home_page.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Pestaña "Perfil".
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Cerrar sesión',
      message: '¿Quieres salir de SecureWallet? Tendrás que iniciar sesión de nuevo.',
      confirmLabel: 'Salir',
    );
    if (!ok) return;
    await ref.read(authRepositoryProvider).logout();
    ref.read(homeTabProvider.notifier).select(0);
    if (context.mounted) context.go('/login');
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool yellow = false}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: IconBadge(
        icon,
        color: yellow ? WalletColors.navy : WalletColors.blue,
        background: yellow ? WalletColors.yellowSoft : WalletColors.ice,
      ),
      title: Text(title, style: WalletText.h3),
      subtitle: Text(subtitle, style: WalletText.muted),
      trailing: const Icon(Icons.chevron_right_rounded, color: WalletColors.muted),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        GradientHeader(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: profile.when(
            loading: () => const SizedBox(height: 110, child: Center(child: CircularProgressIndicator(color: Colors.white))),
            error: (e, _) => const SizedBox(
              height: 110,
              child: Center(child: Text('No se pudo cargar tu perfil', style: TextStyle(color: Colors.white))),
            ),
            data: (p) => Column(
              children: [
                InitialsAvatar(p.fullName, radius: 38),
                const SizedBox(height: 12),
                Text(p.fullName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(p.email, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(height: 10),
                const StatusChip(label: 'Cuenta verificada', color: WalletColors.yellow, icon: Icons.verified_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _tile(Icons.badge_rounded, 'Datos personales', 'Nombre, correo e ID de cuenta', () {
                  final p = profile.maybeWhen(data: (value) => value, orElse: () => null);
                  if (p == null) return;
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                    builder: (ctx) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Datos personales', style: WalletText.h2),
                            const SizedBox(height: 12),
                            DetailRow('Nombre', p.fullName, icon: Icons.person_rounded),
                            DetailRow('Correo', p.email, icon: Icons.email_rounded),
                            DetailRow('ID de cuenta', p.id, icon: Icons.tag_rounded),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const Divider(height: 1),
                _tile(Icons.shield_rounded, 'Centro de seguridad', 'Huella, 2FA, límites y sesiones', () => context.push('/security'), yellow: true),
                const Divider(height: 1),
                _tile(Icons.contacts_rounded, 'Contactos', 'Personas a las que envías dinero', () => context.push('/contacts')),
                const Divider(height: 1),
                _tile(Icons.notifications_rounded, 'Notificaciones', 'Alertas y avisos', () => context.push('/notifications'), yellow: true),
                const Divider(height: 1),
                _tile(Icons.support_agent_rounded, 'Ayuda y soporte', 'Preguntas frecuentes y consejos', () => context.push('/help')),
                const Divider(height: 1),
                _tile(Icons.info_rounded, 'Acerca de SecureWallet', 'Versión 0.1.0', () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'SecureWallet',
                    applicationVersion: '0.1.0',
                    applicationIcon: const WalletLogo(size: 48),
                    children: const [Text('Proyecto académico de ciberseguridad. Usa solo datos de prueba.')],
                  );
                }, yellow: true),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context, ref),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WalletColors.danger,
                side: const BorderSide(color: WalletColors.danger, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
