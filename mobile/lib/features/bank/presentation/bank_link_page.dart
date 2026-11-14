import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/bank_auth_repository.dart';

/// Vincula la cuenta del Banco con el usuario de la Wallet (OAuth2 + PKCE).
/// Regresa `true` con `Navigator.pop` si la vinculación funcionó.
class BankLinkPage extends ConsumerStatefulWidget {
  const BankLinkPage({super.key});

  @override
  ConsumerState<BankLinkPage> createState() => _BankLinkPageState();
}

class _BankLinkPageState extends ConsumerState<BankLinkPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Escribe el correo y la contraseña de tu banco');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(bankAuthRepositoryProvider).link(email: email, password: _password.text);
      ref.invalidate(bankLinkedProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on BankLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular banco')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.account_balance, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Ingresa con tu cuenta del banco para ligarla a tu Wallet. '
            'Tu contraseña se envía solo al banco.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Correo del banco'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Contraseña del banco',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Vincular'),
          ),
        ],
      ),
    );
  }
}
