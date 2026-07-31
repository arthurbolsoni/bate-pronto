// Teste básico de smoke: o app inicializa sem erros.
import 'package:flutter_test/flutter_test.dart';
import 'package:controle_horas/main.dart';

void main() {
  testWidgets('App builds', (tester) async {
    await tester.pumpWidget(const ControleHorasApp());
    expect(find.byType(ControleHorasApp), findsOneWidget);
  });
}
