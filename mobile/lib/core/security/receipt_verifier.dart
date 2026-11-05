import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// JSON canónico: llaves ordenadas y sin espacios. Debe producir exactamente los mismos
/// bytes que `canonical_json` del backend (backend/shared/security/signing.py).
String canonicalJson(Object? value) => jsonEncode(_sortKeys(value));

Object? _sortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sortKeys(value[k])};
  }
  if (value is List) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

/// Verifica firmas Ed25519 (p. ej. el recibo firmado por el Banco).
class ReceiptVerifier {
  final Ed25519 _algorithm = Ed25519();

  Future<bool> verify({
    required Map<String, dynamic> payload,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    final signature = Signature(
      base64Url.decode(signatureB64),
      publicKey: SimplePublicKey(base64Url.decode(publicKeyB64), type: KeyPairType.ed25519),
    );
    return _algorithm.verify(utf8.encode(canonicalJson(payload)), signature: signature);
  }
}
