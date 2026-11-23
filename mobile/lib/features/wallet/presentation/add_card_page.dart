import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../data/cards_repository.dart';
import 'theme/wallet_palette.dart';
import 'widgets/credit_card_view.dart';
import 'widgets/input_formatters.dart';
import 'widgets/wallet_widgets.dart';

/// Formulario para agregar una tarjeta (POST /cards) con vista previa en vivo.
class AddCardPage extends ConsumerStatefulWidget {
  const AddCardPage({super.key});

  @override
  ConsumerState<AddCardPage> createState() => _AddCardPageState();
}

class _AddCardPageState extends ConsumerState<AddCardPage> {
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  bool _loading = false;
  bool _submitted = false;
  String? _serverError;

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    _expiry.dispose();
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(' ', '');

  String? get _numberError {
    if (!_submitted) return null;
    if (_digits.length < 13 || !luhnValid(_digits)) return 'Número de tarjeta inválido';
    return null;
  }

  String? get _holderError {
    if (!_submitted) return null;
    return _holder.text.trim().length < 2 ? 'Escribe el nombre del titular' : null;
  }

  String? get _expiryError {
    if (!_submitted) return null;
    final parsed = parseExpiry(_expiry.text);
    if (parsed == null) return 'Usa el formato MM/AA';
    if (isExpired(parsed[0], parsed[1])) return 'La tarjeta está vencida';
    return null;
  }

  void _fillTestCard() {
    setState(() {
      _number.text = '4111 1111 1111 1111';
      _holder.text = 'TITULAR DE PRUEBA';
      _expiry.text = '12/30';
      _submitted = false;
      _serverError = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (_numberError != null || _holderError != null || _expiryError != null) return;
    final parsed = parseExpiry(_expiry.text)!;
    setState(() => _loading = true);
    try {
      await ref.read(cardsRepositoryProvider).add(
            number: _number.text,
            holderName: _holder.text.trim(),
            expMonth: parsed[0],
            expYear: parsed[1],
          );
      ref.invalidate(cardsProvider);
      if (!mounted) return;
      showWalletSnack(context, 'Tarjeta guardada de forma segura');
      context.pop(true);
    } catch (e) {
      if (mounted) setState(() => _serverError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = detectBrand(_digits);
    return Scaffold(
      backgroundColor: WalletColors.background,
      appBar: AppBar(title: const Text('Agregar tarjeta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CreditCardView(
            brand: brand,
            holder: _holder.text.trim(),
            expiry: _expiry.text.isEmpty ? 'MM/AA' : _expiry.text,
            numberText: _number.text.isEmpty ? '•••• •••• •••• ••••' : _number.text,
          ),
          const SizedBox(height: 20),
          WalletTextField(
            controller: _number,
            label: 'Número de tarjeta',
            icon: Icons.credit_card_rounded,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [CardNumberFormatter()],
            errorText: _numberError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          WalletTextField(
            controller: _holder,
            label: 'Nombre del titular',
            icon: Icons.person_rounded,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            errorText: _holderError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          WalletTextField(
            controller: _expiry,
            label: 'Vencimiento (MM/AA)',
            icon: Icons.event_rounded,
            keyboardType: TextInputType.number,
            inputFormatters: [ExpiryFormatter(), LengthLimitingTextInputFormatter(5)],
            errorText: _expiryError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const InfoBanner(
            icon: Icons.shield_rounded,
            text: 'Por seguridad no pedimos ni guardamos el CVV. El número se cifra con AES-256 y solo se muestran los últimos 4 dígitos.',
          ),
          if (_serverError != null) ...[
            const SizedBox(height: 12),
            InfoBanner(text: _serverError!, kind: BannerKind.danger),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Guardar tarjeta',
            icon: Icons.lock_rounded,
            loading: _loading,
            onPressed: _save,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _fillTestCard,
            icon: const Icon(Icons.science_rounded),
            label: const Text('Usar tarjeta de prueba'),
          ),
        ],
      ),
    );
  }
}
