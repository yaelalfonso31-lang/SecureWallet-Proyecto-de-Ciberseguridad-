import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_service.dart';

/// Pantalla de transferencias banco <-> wallet (B5).
///
/// Recibe el [dio] autenticado con el token del Banco (la enlaza Persona 2).
/// La recarga (banco -> wallet) funciona de principio a fin: el Banco firma el
/// comprobante. El retiro (wallet -> banco) requiere que la Wallet exponga
/// `/wallet/withdraw` para generar su comprobante, por eso se marca como pendiente.
class TransferPage extends StatefulWidget {
  const TransferPage({super.key, required this.dio});

  final Dio dio;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _amountCtrl = TextEditingController();
  final _biometric = BiometricService();
  String _idempotencyKey = _newKey();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _voucher;

  static String _newKey() => 'topup-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int? _amountCents() {
    final value = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  Future<void> _confirm() async {
    final amountCents = _amountCents();
    if (amountCents == null) {
      setState(() => _error = 'Ingresa un monto válido');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Confirmación biométrica antes de mover dinero.
    final ok = await _biometric.authenticate('Confirma la recarga a tu Wallet');
    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Autenticación cancelada';
      });
      return;
    }
    try {
      final res = await widget.dio.post(
        '/transfers/to-wallet',
        data: {'amount_cents': amountCents, 'idempotency_key': _idempotencyKey},
      );
      if (!mounted) return;
      setState(() {
        _voucher = Map<String, dynamic>.from(res.data['voucher'] as Map);
        _loading = false;
        _idempotencyKey = _newKey(); // una operación nueva = una llave nueva
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferencias')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Recargar tu Wallet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Se descuenta de tu cuenta del banco y el Banco firma el comprobante.'),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Monto (MXN)', prefixText: r'$'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _confirm,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fingerprint),
            label: const Text('Confirmar con biometría'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_voucher != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Comprobante firmado', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Transferencia: ${_voucher!['transfer_id']}'),
                    Text('Monto: \$${((_voucher!['amount_cents'] as int) / 100).toStringAsFixed(2)}'),
                    Text('Dirección: ${_voucher!['direction']}'),
                    const SizedBox(height: 8),
                    const Text('Envíalo a la Wallet para abonar el saldo.'),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 40),
          Text('Retirar al banco', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Disponible cuando la Wallet exponga /wallet/withdraw para generar su comprobante firmado.',
          ),
        ],
      ),
    );
  }
}
