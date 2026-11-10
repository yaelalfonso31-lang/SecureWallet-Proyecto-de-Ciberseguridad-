import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Recibir dinero: muestra un código QR de DEMOSTRACIÓN y tu alias.
/// TODO equipo Wallet: generar un QR firmado con los datos reales de cobro.
class ReceivePage extends ConsumerWidget {
  const ReceivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final email = profile.maybeWhen(data: (p) => p.email, orElse: () => 'usuario@securewallet');
    final name = profile.maybeWhen(data: (p) => p.fullName, orElse: () => 'Tu nombre');
    final alias = '@${email.split('@').first}';

    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Recibir dinero')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                InitialsAvatar(name, radius: 30),
                const SizedBox(height: 10),
                Text(name, style: WalletText.h2),
                const SizedBox(height: 2),
                Text(alias, style: WalletText.muted),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: WalletColors.yellow, width: 3),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: CustomPaint(painter: _QrPainter(alias.hashCode)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Muestra este código para que te envíen dinero', textAlign: TextAlign.center, style: WalletText.muted),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Copiar mi alias',
            icon: Icons.content_copy_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: alias));
              if (context.mounted) showWalletSnack(context, 'Alias copiado: $alias');
            },
          ),
          const SizedBox(height: 16),
          const InfoBanner(
            kind: BannerKind.warning,
            text: 'Código QR de demostración: todavía no contiene datos de cobro reales.',
          ),
        ],
      ),
    );
  }
}

/// Dibuja un patrón tipo QR (esquinas de posición + puntos pseudoaleatorios).
class _QrPainter extends CustomPainter {
  _QrPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 25;
    final cell = size.width / n;
    final ink = Paint()..color = WalletColors.ink;
    final navy = Paint()..color = WalletColors.navy;
    final white = Paint()..color = Colors.white;
    final random = math.Random(seed);

    bool inFinder(int x, int y) =>
        (x < 8 && y < 8) || (x >= n - 8 && y < 8) || (x < 8 && y >= n - 8);

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (inFinder(x, y)) continue;
        if (random.nextBool()) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x * cell, y * cell, cell * 0.92, cell * 0.92),
              Radius.circular(cell * 0.25),
            ),
            ink,
          );
        }
      }
    }

    void finder(int gx, int gy) {
      final ox = gx * cell;
      final oy = gy * cell;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(ox, oy, cell * 7, cell * 7), Radius.circular(cell * 1.4)),
        navy,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(ox + cell, oy + cell, cell * 5, cell * 5), Radius.circular(cell)),
        white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(ox + cell * 2, oy + cell * 2, cell * 3, cell * 3),
          Radius.circular(cell * 0.7),
        ),
        Paint()..color = WalletColors.yellow,
      );
    }

    finder(0, 0);
    finder(n - 7, 0);
    finder(0, n - 7);
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.seed != seed;
}
