import 'package:flutter_test/flutter_test.dart';
import 'package:secure_wallet/core/security/receipt_verifier.dart';

void main() {
  test('canonicalJson ordena llaves y no agrega espacios (igual que el backend)', () {
    expect(
      canonicalJson({'b': 1, 'a': {'d': 2, 'c': 3}, 'l': [2, 1]}),
      '{"a":{"c":3,"d":2},"b":1,"l":[2,1]}',
    );
  });
}
