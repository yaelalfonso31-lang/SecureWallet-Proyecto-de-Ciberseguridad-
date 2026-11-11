import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';

/// Pantalla de saldo y movimientos de la cuenta bancaria (B3).
///
/// Recibe el [dio] **ya autenticado** con el token del Banco; la Persona 2 la
/// enlaza desde el tablero (`bank_page.dart`) una vez exista la vinculación (B2).
/// El número de cuenta llega enmascarado desde el Banco: aquí nunca se muestra completo.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.dio});

  final Dio dio;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountData {
  _AccountData(this.account, this.movements);

  final Map<String, dynamic> account;
  final List<dynamic> movements;
}

class _AccountPageState extends State<AccountPage> {
  late Future<_AccountData> _future = _load();

  Future<_AccountData> _load() async {
    final accountRes = await widget.dio.get('/accounts/me');
    final movementsRes = await widget.dio.get(
      '/accounts/me/movements',
      queryParameters: {'limit': 20},
    );
    return _AccountData(
      Map<String, dynamic>.from(accountRes.data as Map),
      List<dynamic>.from(movementsRes.data as List),
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // El error ya lo muestra el FutureBuilder.
    }
  }

  String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: FutureBuilder<_AccountData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(errorMessage(snapshot.error!)));
          }
          final data = snapshot.data!;
          final account = data.account;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Saldo disponible', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Text(
                          _money(account['balance_cents'] as int),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('${account['account_number_masked']} · ${account['currency']}'),
                        Text('Estado: ${account['status']}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (data.movements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Aún no hay movimientos')),
                  )
                else
                  for (final m in data.movements) _MovementTile(m: m, money: _money),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.m, required this.money});

  final dynamic m;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final isDebit = m['kind'] == 'debit';
    final color = isDebit ? Colors.red : Colors.green;
    return ListTile(
      leading: Icon(isDebit ? Icons.arrow_upward : Icons.arrow_downward, color: color),
      title: Text('${m['concept']}'),
      subtitle: Text('Saldo: ${money(m['balance_after_cents'] as int)}'),
      trailing: Text(
        '${isDebit ? '-' : '+'}${money(m['amount_cents'] as int)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
