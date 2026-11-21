import 'package:flutter/material.dart';

import '../theme/wallet_palette.dart';

/// Tarjeta visual con degradado azul, chip amarillo y marca (Visa / Mastercard / Amex).
class CreditCardView extends StatelessWidget {
  const CreditCardView({
    super.key,
    required this.brand,
    required this.holder,
    required this.expiry,
    this.last4,
    this.numberText,
    this.compact = false,
    this.blocked = false,
    this.isDefault = false,
  });

  final String brand;
  final String holder;
  final String expiry;
  final String? last4;

  /// Texto completo del número (solo para la vista previa al agregar una tarjeta).
  final String? numberText;
  final bool compact;
  final bool blocked;
  final bool isDefault;

  LinearGradient get _gradient {
    if (blocked) {
      return const LinearGradient(colors: [Color(0xFF7A8699), Color(0xFF3F4A5E)]);
    }
    switch (brand) {
      case 'mastercard':
        return WalletColors.skyGradient;
      case 'amex':
        return WalletColors.darkGradient;
      default:
        return WalletColors.mainGradient;
    }
  }

  Widget _circle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  Widget _dot(Color color) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.9), shape: BoxShape.circle),
      );

  Widget _brandMark() {
    switch (brand) {
      case 'visa':
        return const Text(
          'VISA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 1,
          ),
        );
      case 'mastercard':
        return SizedBox(
          width: 38,
          height: 24,
          child: Stack(
            children: [
              Positioned(left: 0, child: _dot(const Color(0xFFEB5757))),
              Positioned(right: 0, child: _dot(WalletColors.yellow)),
            ],
          ),
        );
      case 'amex':
        return const Text(
          'AMEX',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
        );
      default:
        return const Icon(Icons.credit_card_rounded, color: Colors.white);
    }
  }

  Widget _chip() => Container(
        width: 38,
        height: 28,
        decoration: BoxDecoration(
          gradient: WalletColors.goldGradient,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Container(
            width: 20,
            height: 14,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x66000000)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );

  Widget _label(String title, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontSize: compact ? 12 : 14, fontWeight: FontWeight.w700),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final number = numberText ?? '•••• •••• •••• ${last4 ?? '••••'}';
    final pad = compact ? 14.0 : 18.0;
    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x330B2A6B), blurRadius: 20, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned(right: -40, top: -40, child: _circle(160, 0.08)),
              Positioned(left: -30, bottom: -60, child: _circle(180, 0.06)),
              Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: WalletColors.yellow, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'SecureWallet',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, color: WalletColors.yellow, size: 16),
                        ],
                        if (blocked) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                        ],
                        const Spacer(),
                        _brandMark(),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _chip(),
                        const SizedBox(width: 10),
                        Icon(Icons.contactless_rounded, color: Colors.white.withValues(alpha: 0.75)),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        number,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 17 : 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _label('TITULAR', holder.isEmpty ? 'NOMBRE APELLIDO' : holder.toUpperCase())),
                        const SizedBox(width: 12),
                        _label('VENCE', expiry),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
