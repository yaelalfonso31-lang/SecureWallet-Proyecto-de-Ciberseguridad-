import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/wallet_models.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

class TransactionSuccessPage extends StatelessWidget {
  const TransactionSuccessPage({super.key, required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WalletColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) => Transform.scale(scale: value, child: child),
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: const BoxDecoration(gradient: WalletColors.goldGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 78, color: WalletColors.navy),
                ),
              ),
              const SizedBox(height: 28),
              const Text('¡Operación exitosa!', style: WalletText.h1),
              const SizedBox(height: 10),
              Text(
                formatMoney(tx.amountCents.abs()),
                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: WalletColors.blue),
              ),
              const SizedBox(height: 6),
              Text(tx.title, textAlign: TextAlign.center, style: WalletText.muted.copyWith(fontSize: 15)),
              const SizedBox(height: 20),
              const InfoBanner(
                kind: BannerKind.success,
                icon: Icons.verified_user_rounded,
                text: 'Tu comprobante tiene una huella digital única para verificar que no fue alterado.',
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Ver comprobante',
                icon: Icons.receipt_long_rounded,
                onPressed: () => context.push('/transaction', extra: tx),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Volver al inicio',
                icon: Icons.home_rounded,
                onPressed: () => context.go('/home'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
