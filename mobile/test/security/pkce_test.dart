import 'package:flutter_test/flutter_test.dart';
import 'package:secure_wallet/features/bank/data/bank_auth_repository.dart';

void main() {
  test('codeChallengeS256 coincide con el vector del RFC 7636', () async {
    expect(
      await codeChallengeS256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('generateCodeVerifier produce 43 caracteres base64url distintos cada vez', () {
    final a = generateCodeVerifier();
    final b = generateCodeVerifier();
    expect(a, hasLength(43));
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });
}
