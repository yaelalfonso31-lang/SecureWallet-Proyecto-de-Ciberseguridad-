import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;
}

/// Recorrido de bienvenida de 3 pantallas (se muestra después de registrarse).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _slides = [
    _Slide(
      Icons.account_balance_wallet_rounded,
      'Todo tu dinero en un solo lugar',
      'Guarda tus tarjetas, revisa tu saldo y mueve tu dinero desde una sola app.',
    ),
    _Slide(
      Icons.shield_rounded,
      'Seguridad en cada operación',
      'Tus tarjetas se guardan cifradas y cada pago se firma digitalmente. Confirmas con tu huella.',
    ),
    _Slide(
      Icons.storefront_rounded,
      'Compra y gana promociones',
      'Paga en la tienda con tu wallet y aprovecha los bonos y descuentos de tu banco.',
    ),
  ];

  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => context.go('/home');

  void _next() {
    if (_index == _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: WalletColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Omitir')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final slide = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 190,
                          height: 190,
                          decoration: const BoxDecoration(
                            gradient: WalletColors.mainGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: const BoxDecoration(
                                gradient: WalletColors.goldGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(slide.icon, size: 64, color: WalletColors.navy),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(slide.title, textAlign: TextAlign.center, style: WalletText.h1),
                        const SizedBox(height: 14),
                        Text(slide.text, textAlign: TextAlign.center, style: WalletText.muted.copyWith(fontSize: 15)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? WalletColors.yellow : WalletColors.line,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: PrimaryButton(
                label: last ? 'Comenzar' : 'Siguiente',
                icon: last ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
