import 'package:flutter/material.dart';

import '../theme/wallet_format.dart';
import '../theme/wallet_palette.dart';
import 'wallet_widgets.dart';

/// Saldo con efecto "cristal" sobre el encabezado azul.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balanceCents,
    required this.hidden,
    required this.onToggle,
    required this.onSend,
    required this.onTopUp,
  });

  final int balanceCents;
  final bool hidden;
  final VoidCallback onToggle;
  final VoidCallback onSend;
  final VoidCallback onTopUp;

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color background,
    required Color foreground,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Saldo disponible',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: hidden ? 'Mostrar saldo' : 'Ocultar saldo',
                onPressed: onToggle,
                icon: Icon(
                  hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hidden ? '\$ ••••••' : formatMoney(balanceCents),
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const StatusChip(label: 'MXN', color: WalletColors.yellow),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: WalletColors.yellow, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Protegido con cifrado y firma digital',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _pill(
                  icon: Icons.add_card_rounded,
                  label: 'Recargar',
                  onTap: onTopUp,
                  background: WalletColors.yellow,
                  foreground: WalletColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pill(
                  icon: Icons.send_rounded,
                  label: 'Enviar',
                  onTap: onSend,
                  background: Colors.white.withValues(alpha: 0.18),
                  foreground: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
