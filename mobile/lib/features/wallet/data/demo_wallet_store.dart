import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wallet_models.dart';

/// Saldo, movimientos y contactos de DEMOSTRACIÓN.
/// TODO equipo Wallet: reemplazar por endpoints reales del backend (saldo, historial, transferencias).
class DemoWalletState {
  const DemoWalletState({
    required this.balanceCents,
    required this.transactions,
    required this.contacts,
  });

  final int balanceCents;
  final List<WalletTransaction> transactions;
  final List<WalletContact> contacts;

  DemoWalletState copyWith({
    int? balanceCents,
    List<WalletTransaction>? transactions,
    List<WalletContact>? contacts,
  }) =>
      DemoWalletState(
        balanceCents: balanceCents ?? this.balanceCents,
        transactions: transactions ?? this.transactions,
        contacts: contacts ?? this.contacts,
      );
}

class DemoWalletNotifier extends Notifier<DemoWalletState> {
  @override
  DemoWalletState build() {
    final now = DateTime.now();
    return DemoWalletState(
      balanceCents: 1254000,
      contacts: const [
        WalletContact(name: 'Ana López', alias: '@ana.lopez'),
        WalletContact(name: 'Carlos Ruiz', alias: '@carlos.ruiz'),
        WalletContact(name: 'María Torres', alias: '@maria.torres'),
        WalletContact(name: 'Luis Pérez', alias: '@luis.perez'),
        WalletContact(name: 'Sofía Díaz', alias: '@sofia.diaz'),
      ],
      transactions: [
        WalletTransaction(
          id: 'tx_seed_1',
          kind: TxKind.payment,
          title: 'Café Central',
          subtitle: 'Pago con Wallet',
          amountCents: -8500,
          date: now.subtract(const Duration(hours: 2)),
        ),
        WalletTransaction(
          id: 'tx_seed_2',
          kind: TxKind.received,
          title: 'Recibido de María Torres',
          subtitle: 'Comida del viernes',
          amountCents: 30000,
          date: now.subtract(const Duration(hours: 20)),
        ),
        WalletTransaction(
          id: 'tx_seed_3',
          kind: TxKind.topUp,
          title: 'Recarga de saldo',
          subtitle: 'Desde Visa •••• 1111',
          amountCents: 50000,
          date: now.subtract(const Duration(days: 1, hours: 3)),
        ),
        WalletTransaction(
          id: 'tx_seed_4',
          kind: TxKind.payment,
          title: 'Tienda: Teclado mecánico',
          subtitle: 'Pago con Wallet',
          amountCents: -129900,
          date: now.subtract(const Duration(days: 3)),
        ),
        WalletTransaction(
          id: 'tx_seed_5',
          kind: TxKind.promo,
          title: 'Bono de bienvenida',
          subtitle: 'Promoción del Banco',
          amountCents: 10000,
          date: now.subtract(const Duration(days: 5)),
        ),
      ],
    );
  }

  WalletTransaction _record({
    required TxKind kind,
    required String title,
    required String subtitle,
    required int signedCents,
  }) {
    final tx = WalletTransaction(
      id: 'tx_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      title: title,
      subtitle: subtitle,
      amountCents: signedCents,
      date: DateTime.now(),
    );
    state = state.copyWith(
      balanceCents: state.balanceCents + signedCents,
      transactions: [tx, ...state.transactions],
    );
    return tx;
  }

  WalletTransaction send(WalletContact to, int cents, {String note = ''}) => _record(
        kind: TxKind.sent,
        title: 'Enviado a ${to.name}',
        subtitle: note.isEmpty ? 'Transferencia' : note,
        signedCents: -cents,
      );

  WalletTransaction topUp(String source, int cents) => _record(
        kind: TxKind.topUp,
        title: 'Recarga de saldo',
        subtitle: 'Desde $source',
        signedCents: cents,
      );

  WalletTransaction withdraw(String destination, int cents) => _record(
        kind: TxKind.withdraw,
        title: 'Retiro a banco',
        subtitle: 'A $destination',
        signedCents: -cents,
      );

  void addContact(WalletContact contact) {
    state = state.copyWith(contacts: [...state.contacts, contact]);
  }
}

final demoWalletProvider =
    NotifierProvider<DemoWalletNotifier, DemoWalletState>(DemoWalletNotifier.new);

/// Preferencias de seguridad (locales de demostración).
class SecuritySettings {
  const SecuritySettings({
    this.biometric = false,
    this.twoFactor = false,
    this.loginAlerts = true,
    this.emergencyLock = false,
    this.perTxLimitCents = 500000,
    this.dailyLimitCents = 2000000,
  });

  final bool biometric;
  final bool twoFactor;
  final bool loginAlerts;
  final bool emergencyLock;
  final int perTxLimitCents;
  final int dailyLimitCents;

  SecuritySettings copyWith({
    bool? biometric,
    bool? twoFactor,
    bool? loginAlerts,
    bool? emergencyLock,
    int? perTxLimitCents,
    int? dailyLimitCents,
  }) =>
      SecuritySettings(
        biometric: biometric ?? this.biometric,
        twoFactor: twoFactor ?? this.twoFactor,
        loginAlerts: loginAlerts ?? this.loginAlerts,
        emergencyLock: emergencyLock ?? this.emergencyLock,
        perTxLimitCents: perTxLimitCents ?? this.perTxLimitCents,
        dailyLimitCents: dailyLimitCents ?? this.dailyLimitCents,
      );

  /// 25 puntos por la contraseña fuerte que exige el backend + protecciones activas.
  int get score =>
      25 + (biometric ? 30 : 0) + (twoFactor ? 30 : 0) + (loginAlerts ? 15 : 0);
}

class SecuritySettingsNotifier extends Notifier<SecuritySettings> {
  @override
  SecuritySettings build() => const SecuritySettings();

  void replace(SecuritySettings value) {
    state = value;
  }
}

final securitySettingsProvider =
    NotifierProvider<SecuritySettingsNotifier, SecuritySettings>(
  SecuritySettingsNotifier.new,
);
