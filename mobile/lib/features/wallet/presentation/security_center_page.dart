import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';
import '../data/auth_repository.dart';
import '../data/demo_wallet_store.dart';
import '../data/security_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Centro de seguridad: biometría real, 2FA TOTP (RFC 6238) y bitácora SHA-256.
class SecurityCenterPage extends ConsumerStatefulWidget {
  const SecurityCenterPage({super.key});

  @override
  ConsumerState<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends ConsumerState<SecurityCenterPage> {
  bool _busy2fa = false;

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
        showWalletSnack(
          context,
          'Tu teléfono no tiene huella, rostro ni bloqueo de pantalla configurado.',
          error: true,
        );
      }
      return;
    }
    final ok = await bio.authenticate(
      'Confirma para activar la verificación biométrica',
    );
    if (!mounted) return;
    if (ok) {
      _update((s) => s.copyWith(biometric: true));
      showWalletSnack(context, 'Verificación biométrica activada');
    } else {
      showWalletSnack(context, 'No se pudo verificar tu identidad',
          error: true);
    }
  }

  Future<void> _toggleTwoFactor(bool value) async {
    if (_busy2fa) return;
    setState(() => _busy2fa = true);
    try {
      if (value) {
        final setup = await ref.read(securityRepositoryProvider).setup2fa();
        if (!mounted) return;
        final activated = await _showEnable2faSheet(setup);
        if (activated == true && mounted) {
          _update((s) => s.copyWith(twoFactor: true));
          ref.invalidate(profileProvider);
          ref.invalidate(auditChainProvider);
          showWalletSnack(context, 'Verificación en dos pasos (2FA) activada');
        }
      } else {
        final disabled = await _showDisable2faDialog();
        if (disabled == true && mounted) {
          _update((s) => s.copyWith(twoFactor: false));
          ref.invalidate(profileProvider);
          ref.invalidate(auditChainProvider);
          showWalletSnack(context, 'Verificación en dos pasos desactivada');
        }
      }
    } catch (e) {
      if (mounted) showWalletSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy2fa = false);
    }
  }

  Future<bool?> _showEnable2faSheet(TotpSetupData setup) {
    final codeCtrl = TextEditingController();
    String? sheetError;
    bool submitting = false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Activar 2FA (TOTP)',
                    textAlign: TextAlign.center,
                    style: WalletText.h2,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Agrega esta clave secreta en Google Authenticator o Authy e ingresa el código de 6 dígitos:',
                    style: WalletText.muted,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: WalletColors.ice,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            setup.secret,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.5,
                              color: WalletColors.navy,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar clave',
                          icon: const Icon(Icons.copy_rounded,
                              color: WalletColors.blue),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: setup.secret));
                            showWalletSnack(context, 'Clave TOTP copiada');
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Código de 6 dígitos',
                      counterText: '',
                      errorText: sheetError,
                      prefixIcon: const Icon(Icons.pin_rounded,
                          color: WalletColors.blue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Confirmar y activar 2FA',
                    icon: Icons.verified_user_rounded,
                    loading: submitting,
                    onPressed: () async {
                      if (codeCtrl.text.trim().length < 6) {
                        setSheetState(
                            () => sheetError = 'Ingresa los 6 dígitos');
                        return;
                      }
                      setSheetState(() {
                        submitting = true;
                        sheetError = null;
                      });
                      try {
                        await ref
                            .read(securityRepositoryProvider)
                            .enable2fa(codeCtrl.text);
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setSheetState(() {
                          submitting = false;
                          sheetError = errorMessage(e);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDisable2faDialog() {
    final codeCtrl = TextEditingController();
    String? dialogError;
    bool submitting = false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Desactivar 2FA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa el código actual de 6 dígitos de tu app autenticadora para desactivar el segundo factor:',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Código de 6 dígitos',
                  counterText: '',
                  errorText: dialogError,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (codeCtrl.text.trim().length < 6) {
                        setDialogState(() =>
                            dialogError = 'Código de 6 dígitos requerido');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        dialogError = null;
                      });
                      try {
                        await ref
                            .read(securityRepositoryProvider)
                            .disable2fa(codeCtrl.text);
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          dialogError = errorMessage(e);
                        });
                      }
                    },
              child: const Text('Desactivar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleEmergency(bool value) async {
    if (!value) {
      _update((s) => s.copyWith(emergencyLock: false));
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Bloqueo de emergencia',
      message:
          'Se bloquearán envíos, recargas y retiros hasta que lo desactives. ¿Continuar?',
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

  Widget _linkTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: IconBadge(
        icon,
        color: WalletColors.navy,
        background: WalletColors.yellowSoft,
      ),
      title: Text(title, style: WalletText.h3),
      subtitle: Text(subtitle, style: WalletText.muted),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: WalletColors.muted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(securitySettingsProvider);
    final profile = ref.watch(profileProvider);
    final totpEnabled = profile.maybeWhen(
      data: (p) => p.totpEnabled,
      orElse: () => s.twoFactor,
    );
    final effective = s.copyWith(twoFactor: totpEnabled);
    final level = effective.score >= 85
        ? 'Excelente'
        : (effective.score >= 60 ? 'Buena' : 'Mejorable');

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
                          value: effective.score / 100,
                          strokeWidth: 9,
                          backgroundColor: Colors.white24,
                          color: WalletColors.yellow,
                        ),
                      ),
                      Text(
                        '${effective.score}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nivel de seguridad',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        level,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Activa más protecciones para llegar al 100%',
                        style: TextStyle(
                          color: WalletColors.yellow,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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
                    title: 'Verificación en dos pasos (TOTP)',
                    subtitle: totpEnabled
                        ? 'Activo · código temporal al iniciar sesión'
                        : 'Código temporal (RFC 6238) con app autenticadora',
                    value: totpEnabled,
                    onChanged: _toggleTwoFactor,
                  ),
                  const Divider(height: 1),
                  _switchTile(
                    icon: Icons.notifications_active_rounded,
                    title: 'Alertas de inicio de sesión',
                    subtitle: 'Te avisamos de accesos nuevos',
                    value: s.loginAlerts,
                    onChanged: (v) =>
                        _update((x) => x.copyWith(loginAlerts: v)),
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
                  _linkTile(
                    Icons.devices_rounded,
                    'Dispositivos y sesiones',
                    'Dónde está abierta tu cuenta',
                    () => context.push('/security/sessions'),
                  ),
                  const Divider(height: 1),
                  _linkTile(
                    Icons.speed_rounded,
                    'Límites de transacción',
                    'Controla cuánto puedes mover',
                    () => context.push('/security/limits'),
                  ),
                  const Divider(height: 1),
                  _linkTile(
                    Icons.manage_search_rounded,
                    'Bitácora de actividad (SHA-256)',
                    'Cadena inmutable verificada en el servidor',
                    () => context.push('/security/log'),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: InfoBanner(
              icon: Icons.verified_user_rounded,
              text:
                  'Protección activa con biometría local, 2FA TOTP en el servidor, límite de peticiones por IP y bitácora encadenada con SHA-256.',
            ),
          ),
        ],
      ),
    );
  }
}
