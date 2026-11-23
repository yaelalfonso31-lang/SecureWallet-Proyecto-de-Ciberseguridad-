import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../data/demo_wallet_store.dart';
import '../data/security_repository.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Dispositivos y sesiones.
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
                IconBadge(
                  Icons.phone_android_rounded,
                  color: WalletColors.navy,
                  background: WalletColors.yellowSoft,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Este dispositivo', style: WalletText.h3),
                      Text('Android · sesión JWT activa',
                          style: WalletText.muted),
                    ],
                  ),
                ),
                StatusChip(label: 'Actual', icon: Icons.check_circle_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const InfoBanner(
            icon: Icons.lock_clock_rounded,
            text:
                'Tu sesión usa un token JWT de vida corta (15 min) resguardado en Android Keystore / iOS Keychain.',
          ),
        ],
      ),
    );
  }
}

/// Límites por operación y diarios (se aplican en Enviar / Recargar / Retirar).
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
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: WalletColors.blue,
                  ),
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
                    IconBadge(
                      Icons.today_rounded,
                      color: WalletColors.navy,
                      background: WalletColors.yellowSoft,
                    ),
                    SizedBox(width: 12),
                    Text('Límite diario', style: WalletText.h3),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney((_daily * 100).round()),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: WalletColors.blue,
                  ),
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
          const InfoBanner(
            text:
                'Un límite bajo reduce el daño si alguien accede a tu cuenta.',
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Guardar límites',
            icon: Icons.check_rounded,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Bitácora real de auditoría con verificación criptográfica de cadena de hashes SHA-256.
class ActivityLogPage extends ConsumerWidget {
  const ActivityLogPage({super.key});

  static String _eventTitle(String event) {
    switch (event) {
      case 'register':
        return 'Registro de cuenta';
      case 'login_ok':
        return 'Inicio de sesión exitoso';
      case 'login_failed':
        return 'Intento de acceso fallido';
      case 'login_2fa_required':
        return 'Login detenido: falta 2FA';
      case 'login_2fa_failed':
        return 'Código 2FA incorrecto';
      case 'login_blocked':
        return 'Acceso bloqueado';
      case 'account_locked':
        return 'Cuenta bloqueada (15 min)';
      case 'card_added':
        return 'Tarjeta cifrada agregada';
      case 'card_deleted':
        return 'Tarjeta eliminada';
      case 'payment_authorized':
        return 'Orden firmada (Ed25519)';
      case 'bank_link_assertion':
        return 'Aserción bancaria firmada';
      case 'wallet_topup':
        return 'Recarga acreditada';
      case 'wallet_withdraw':
        return 'Retiro firmado hacia Banco';
      case 'wallet_transfer':
        return 'Transferencia P2P enviada';
      case 'totp_setup_started':
        return 'Configuración 2FA iniciada';
      case 'totp_enabled':
        return '2FA TOTP activado';
      case 'totp_disabled':
        return '2FA TOTP desactivado';
      default:
        return event;
    }
  }

  static IconData _eventIcon(String event) {
    if (event.contains('failed') ||
        event.contains('locked') ||
        event.contains('blocked')) {
      return Icons.warning_amber_rounded;
    }
    if (event.contains('totp')) return Icons.phonelink_lock_rounded;
    if (event.contains('card')) return Icons.credit_card_rounded;
    if (event.contains('payment') || event.contains('assertion')) {
      return Icons.verified_user_rounded;
    }
    if (event.contains('login') || event == 'register')
      return Icons.login_rounded;
    return Icons.swap_horiz_rounded;
  }

  static bool _isWarning(String event) =>
      event.contains('failed') ||
      event.contains('locked') ||
      event.contains('blocked');

  static String _shortHash(String h, [int keep = 14]) =>
      h.length > keep ? '${h.substring(0, keep)}…' : h;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(auditChainProvider);

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Bitácora de actividad')),
      body: RefreshIndicator(
        color: WalletColors.blue,
        onRefresh: () async {
          ref.invalidate(auditChainProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: auditAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InfoBanner(kind: BannerKind.danger, text: errorMessage(e)),
            ],
          ),
          data: (report) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InfoBanner(
                kind:
                    report.chainValid ? BannerKind.success : BannerKind.danger,
                icon: report.chainValid
                    ? Icons.verified_rounded
                    : Icons.gpp_bad_rounded,
                text: report.chainValid
                    ? 'Integridad SHA-256 verificada: ${report.totalRecords} registros encadenados sin alteraciones.'
                    : '¡Alerta! Se detectó una ruptura en la cadena de hashes SHA-256 de audit_log.',
              ),
              const SizedBox(height: 16),
              if (report.entries.isEmpty)
                const EmptyState(
                  icon: Icons.manage_search_rounded,
                  title: 'Sin registros',
                  message: 'Tus eventos de seguridad aparecerán aquí.',
                )
              else
                for (final e in report.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconBadge(
                            _eventIcon(e.event),
                            color: _isWarning(e.event)
                                ? WalletColors.danger
                                : WalletColors.blue,
                            background: _isWarning(e.event)
                                ? const Color(0xFFFDECEC)
                                : WalletColors.ice,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _eventTitle(e.event),
                                        style: WalletText.h3,
                                      ),
                                    ),
                                    Text(
                                      formatTime(e.createdAt.toLocal()),
                                      style: WalletText.muted,
                                    ),
                                  ],
                                ),
                                if (e.detail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(e.detail, style: WalletText.muted),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'SHA-256: ${_shortHash(e.hash)} · Prev: ${_shortHash(e.prevHash, 10)}',
                                  style:
                                      WalletText.muted.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
