import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Pantalla de arranque con el logo animado. Después manda al inicio de sesión.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: WalletColors.mainGradient),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.7 + 0.3 * value, child: child),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WalletLogo(size: 104),
                SizedBox(height: 24),
                Text(
                  'SecureWallet',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Tu dinero, protegido',
                  style: TextStyle(color: WalletColors.yellow, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 40),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
