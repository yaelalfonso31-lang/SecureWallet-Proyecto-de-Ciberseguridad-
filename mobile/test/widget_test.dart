import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_wallet/app.dart';

void main() {
  testWidgets('el splash lleva a la pantalla de inicio de sesión', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SecureWalletApp()));
    // El splash espera ~1.8 s antes de navegar.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsWidgets);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
