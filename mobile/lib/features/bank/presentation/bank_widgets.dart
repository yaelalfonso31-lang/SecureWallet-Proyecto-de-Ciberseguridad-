import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../wallet/presentation/theme/wallet_format.dart';
import '../../wallet/presentation/theme/wallet_palette.dart';
import '../../wallet/presentation/widgets/wallet_widgets.dart';
import '../data/bank_repository.dart';

/// Tarjeta visual de la cuenta del Banco (azul oscuro con detalles amarillos).
class BankAccountCard extends StatelessWidget {
  const BankAccountCard({super.key, required this.account, this.hidden = false});

  final BankAccount account;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: WalletColors.darkGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x330B2A6B), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                Icons.account_balance_rounded,
                size: 40,
                color: WalletColors.navy,
                background: WalletColors.yellow,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cuenta Azul',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              StatusChip(
                label: account.isFrozen ? 'Congelada' : 'Activa',
                color: account.isFrozen ? WalletColors.danger : WalletColors.yellow,
                icon: account.isFrozen ? Icons.lock_rounded : Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Saldo disponible',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hidden ? '\$ ••••••' : formatMoney(account.balanceCents),
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.credit_card_rounded, color: WalletColors.yellow, size: 18),
              const SizedBox(width: 8),
              Text(
                account.numberMasked,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text('MXN', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Movimiento de la cuenta del Banco.
class BankMovementTile extends StatelessWidget {
  const BankMovementTile({super.key, required this.movement});

  final BankMovement movement;

  @override
  Widget build(BuildContext context) {
    final credit = movement.isCredit;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: IconBadge(
        credit ? Icons.south_west_rounded : Icons.north_east_rounded,
        color: credit ? WalletColors.success : WalletColors.navy,
        background: credit ? const Color(0xFFE6F6EF) : WalletColors.yellowSoft,
      ),
      title: Text(
        movement.concept,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WalletColors.ink),
      ),
      subtitle: Text(
        '${formatTime(movement.createdAt.toLocal())} · Saldo ${formatMoney(movement.balanceAfterCents)}',
        style: WalletText.muted,
      ),
      trailing: Text(
        '${credit ? '+' : '-'}${formatMoney(movement.amountCents)}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: credit ? WalletColors.success : WalletColors.ink,
        ),
      ),
    );
  }
}

/// Mensaje legible para un error del servidor. Los 422 (validación) no traen un texto útil.
String friendlyError(
  Object error, {
  String validation = 'Revisa los datos e inténtalo de nuevo',
}) {
  if (error is DioException && error.response?.statusCode == 422) return validation;
  return errorMessage(error);
}
