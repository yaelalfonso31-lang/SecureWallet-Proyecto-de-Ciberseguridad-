/// Tarjeta guardada en el backend (GET /cards). Nunca contiene el número completo.
class WalletCard {
  const WalletCard({
    required this.id,
    required this.token,
    required this.brand,
    required this.last4,
    required this.holderName,
    required this.expMonth,
    required this.expYear,
  });

  factory WalletCard.fromJson(Map<String, dynamic> json) => WalletCard(
        id: json['id'] as String,
        token: json['token'] as String,
        brand: json['brand'] as String,
        last4: json['last4'] as String,
        holderName: json['holder_name'] as String,
        expMonth: json['exp_month'] as int,
        expYear: json['exp_year'] as int,
      );

  final String id;
  final String token;
  final String brand;
  final String last4;
  final String holderName;
  final int expMonth;
  final int expYear;

  String get brandLabel {
    switch (brand) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
        return 'Mastercard';
      case 'amex':
        return 'American Express';
      default:
        return 'Tarjeta';
    }
  }

  String get expiry {
    final month = expMonth.toString().padLeft(2, '0');
    final year = (expYear % 100).toString().padLeft(2, '0');
    return '$month/$year';
  }
}

enum TxKind { sent, received, topUp, withdraw, payment, promo }

/// Movimiento de la wallet. Importe con signo, en centavos.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.amountCents,
    required this.date,
  });

  final String id;
  final TxKind kind;
  final String title;
  final String subtitle;
  final int amountCents;
  final DateTime date;

  bool get isIncome => amountCents > 0;
}

class WalletContact {
  const WalletContact({required this.name, required this.alias});

  final String name;
  final String alias;
}

class BankAccountInfo {
  const BankAccountInfo({required this.bank, required this.last4});

  final String bank;
  final String last4;
}

/// Cuentas bancarias de demostración (el módulo Banco las reemplazará).
const List<BankAccountInfo> demoBankAccounts = [
  BankAccountInfo(bank: 'Banco Azul', last4: '4821'),
  BankAccountInfo(bank: 'Banco Dorado', last4: '9033'),
];

class UserProfile {
  const UserProfile({required this.id, required this.email, required this.fullName});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
      );

  final String id;
  final String email;
  final String fullName;
}
