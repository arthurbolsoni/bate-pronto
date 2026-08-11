import 'package:flutter_test/flutter_test.dart';
import 'package:controle_horas/salary.dart';

void main() {
  group('inssBracketFor', () {
    test('faixas batem com a tabela 01/2026', () {
      expect(inssBracketFor(4706.67).inss, 324.20);
      expect(inssBracketFor(4706.68).inss, 338.40);
      expect(inssBracketFor(6500.00).inss, 338.40);
      expect(inssBracketFor(6500.01).inss, 357.40);
      expect(inssBracketFor(8000.00).inss, 357.40);
    });

    test('acima de 8.000 trava no teto (cobre gap e >10k)', () {
      expect(inssBracketFor(8000.99).inss, 389.00);
      expect(inssBracketFor(8001.00).inss, 389.00);
      expect(inssBracketFor(10000.00).inss, 389.00);
      expect(inssBracketFor(50000.00).inss, 389.00);
    });
  });

  group('birthdayDayOffInMonth', () {
    test('null quando não há data', () {
      expect(birthdayDayOffInMonth(null, 2026, 8), isNull);
    });

    test('null quando o mês não é o do aniversário', () {
      final bday = DateTime(1990, 8, 12);
      expect(birthdayDayOffInMonth(bday, 2026, 7), isNull);
    });

    test('dia útil fica no próprio dia', () {
      // 12/08/2026 é quarta-feira.
      final bday = DateTime(1990, 8, 12);
      expect(birthdayDayOffInMonth(bday, 2026, 8), DateTime(2026, 8, 12));
    });

    test('sábado vira sexta anterior', () {
      // 15/08/2026 é sábado -> 14 (sexta).
      final bday = DateTime(1990, 8, 15);
      expect(birthdayDayOffInMonth(bday, 2026, 8), DateTime(2026, 8, 14));
    });

    test('domingo vira sexta anterior', () {
      // 16/08/2026 é domingo -> 14 (sexta).
      final bday = DateTime(1990, 8, 16);
      expect(birthdayDayOffInMonth(bday, 2026, 8), DateTime(2026, 8, 14));
    });

    test('29/02 em ano não bissexto cai pro dia 28', () {
      // 28/02/2026 é sábado -> 27 (sexta).
      final bday = DateTime(2000, 2, 29);
      expect(birthdayDayOffInMonth(bday, 2026, 2), DateTime(2026, 2, 27));
    });
  });
}
