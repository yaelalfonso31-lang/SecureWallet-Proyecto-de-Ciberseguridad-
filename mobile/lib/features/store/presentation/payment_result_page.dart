import 'package:flutter/material.dart';

import '../data/store_repository.dart';
import 'store_page.dart' show formatPrice;

class PaymentResultPage extends StatelessWidget {
  const PaymentResultPage({super.key, required this.paid});

  final PaidOrder paid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String text, Color color) = switch (paid.receiptStatus) {
      ReceiptStatus.verified => (Icons.verified, 'Recibo del Banco verificado', Colors.green),
      ReceiptStatus.invalid => (Icons.warning_amber, 'No se pudo verificar el recibo', scheme.error),
      ReceiptStatus.unchecked => (Icons.help_outline, 'Recibo sin verificar (falta BANK_PUBLIC_KEY)', Colors.orange),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Pago realizado'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              formatPrice(paid.amountCents),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('Orden ${paid.orderId}', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Flexible(child: Text(text, style: TextStyle(color: color))),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver a la tienda'),
            ),
          ],
        ),
      ),
    );
  }
}