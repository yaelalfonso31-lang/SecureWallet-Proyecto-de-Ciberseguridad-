import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/wallet_models.dart';
import 'theme/wallet_format.dart';
import 'theme/wallet_palette.dart';
import 'widgets/wallet_widgets.dart';

/// Comprobante de un movimiento con su huella digital SHA-256 (demostración de integridad).
class TransactionDetailPage extends StatefulWidget {
  const TransactionDetailPage({super.key, required this.tx});

  final WalletTransaction tx;

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  late final Future<String> _fingerprint = _computeFingerprint(widget.tx);

  /// Cambiar cualquier dato del movimiento cambia por completo esta huella.
  static Future<String> _computeFingerprint(WalletTransaction tx) async {
    final data = utf8.encode('${tx.id}|${tx.amountCents}|${tx.title}|${tx.date.toIso8601String()}');
    final hash = await Sha256().hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final income = tx.isIncome;
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Comprobante')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                IconBadge(
                  txIcon(tx.kind),
                  size: 64,
                  color: income ? WalletColors.success : WalletColors.navy,
                  background: income ? const Color(0xFFE6F6EF) : WalletColors.yellowSoft,
                ),
                const SizedBox(height: 14),
                Text(
                  '${income ? '+' : ''}${formatMoney(tx.amountCents)}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: income ? WalletColors.success : WalletColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(tx.title, textAlign: TextAlign.center, style: WalletText.h3),
                const SizedBox(height: 10),
                const StatusChip(label: 'Completado', icon: Icons.check_circle_rounded),
                const SizedBox(height: 16),
                const Divider(height: 1),
                DetailRow('Concepto', tx.subtitle, icon: Icons.notes_rounded),
                const Divider(height: 1),
                DetailRow('Fecha', formatDate(tx.date), icon: Icons.event_rounded),
                const Divider(height: 1),
                DetailRow('Hora', formatTime(tx.date), icon: Icons.schedule_rounded),
                const Divider(height: 1),
                DetailRow('Referencia', tx.id, icon: Icons.tag_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.fingerprint_rounded, color: WalletColors.blue),
                    SizedBox(width: 8),
                    Expanded(child: Text('Huella digital (SHA-256)', style: WalletText.h3)),
                  ],
                ),
                const SizedBox(height: 10),
                FutureBuilder<String>(
                  future: _fingerprint,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator(color: WalletColors.yellow);
                    }
                    final hash = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: WalletColors.ice, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            hash,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: WalletColors.navy),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: hash));
                              if (context.mounted) showWalletSnack(context, 'Huella copiada');
                            },
                            icon: const Icon(Icons.content_copy_rounded, size: 18),
                            label: const Text('Copiar'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const InfoBanner(
                  text: 'Si alguien cambiara el monto, la fecha o cualquier dato, la huella sería completamente distinta. Así se detecta una alteración.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
