import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base de horas usada pra calcular o salário do mês.
enum SalaryBase {
  projecao('Projeção do mês'),
  trabalhado('Trabalhado (real)'),
  carga('Carga normal do mês');

  final String label;
  const SalaryBase(this.label);
}

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Formata em reais. Com [hide], devolve a máscara do olhinho no lugar do valor.
String brl(double v, {bool hide = false}) => hide ? r'R$ ••••' : _brl.format(v);

/// Faixa da tabela de INSS (SM) vigente 01/2026. O desconto é fixo por faixa
/// de remuneração total — INSS (SM) = 20% da remuneração produção da faixa.
class InssBracket {
  /// Teto da remuneração total da faixa (inclusive). Infinito na última.
  final double limit;

  /// Remuneração produção base usada pra apurar o INSS da faixa.
  final double producao;

  /// Desconto de INSS fixo da faixa (R$).
  final double inss;

  const InssBracket(this.limit, this.producao, this.inss);
}

/// Tabela vigente. A última faixa é o teto: qualquer bruto acima de 8.000
/// desconta R$ 389,00 (comporta o gap 8.000→8.001 e brutos acima de 10k).
const inssTable = <InssBracket>[
  InssBracket(4706.67, 1621.00, 324.20),
  InssBracket(6500.00, 1692.00, 338.40),
  InssBracket(8000.00, 1787.00, 357.40),
  InssBracket(double.infinity, 1945.00, 389.00),
];

/// Faixa da tabela pra um dado bruto (remuneração total do mês).
InssBracket inssBracketFor(double bruto) =>
    inssTable.firstWhere((b) => bruto <= b.limit, orElse: () => inssTable.last);

/// Dia do day-off pago de aniversário dentro do mês [year]/[month], ou null se
/// o aniversário não cai nesse mês. Se cair no sábado ou domingo, joga pra
/// sexta-feira anterior (a sexta pode até cair no mês anterior — aí só conta
/// no mês em que a sexta realmente está).
DateTime? birthdayDayOffInMonth(DateTime? birthday, int year, int month) {
  if (birthday == null) return null;
  // Dia do aniversário no ano corrente, preso ao último dia do mês (29/02).
  final lastDay = DateTime(year, birthday.month + 1, 0).day;
  final day = birthday.day < lastDay ? birthday.day : lastDay;
  var d = DateTime(year, birthday.month, day);
  if (d.weekday == DateTime.saturday) {
    d = d.subtract(const Duration(days: 1));
  } else if (d.weekday == DateTime.sunday) {
    d = d.subtract(const Duration(days: 2));
  }
  return (d.year == year && d.month == month) ? d : null;
}

/// Olhinho estilo app de banco: esconde os valores em R$ da tela de horas.
/// O estado é global (um notifier) e fica persistido em SharedPreferences.
class MoneyPrivacy {
  static const _kHidden = 'money_hidden';

  static final ValueNotifier<bool> hidden = ValueNotifier(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    hidden.value = p.getBool(_kHidden) ?? false;
  }

  static Future<void> toggle() async {
    hidden.value = !hidden.value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHidden, hidden.value);
  }
}

/// Parâmetros do salário, persistidos em SharedPreferences. Começa zerado —
/// enquanto [isSet] for false o card mostra R$ 0,00.
class SalaryConfig {
  static const _kRate = 'salary_hour_rate';
  static const _kOther = 'salary_other_pct';
  static const _kBase = 'salary_base';
  static const _kBday = 'salary_birthday';

  double hourRate;
  double otherPct;
  SalaryBase base;

  /// Data de nascimento. Rende um day-off pago no mês do aniversário
  /// (ver [birthdayDayOffInMonth]). Só o dia/mês importam pro cálculo.
  DateTime? birthday;

  SalaryConfig({
    this.hourRate = 0,
    this.otherPct = 0,
    this.base = SalaryBase.projecao,
    this.birthday,
  });

  bool get isSet => hourRate > 0;

  SalaryConfig copy() => SalaryConfig(
        hourRate: hourRate,
        otherPct: otherPct,
        base: base,
        birthday: birthday,
      );

  static Future<SalaryConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final baseName = p.getString(_kBase);
    final bday = p.getString(_kBday);
    return SalaryConfig(
      hourRate: p.getDouble(_kRate) ?? 0,
      otherPct: p.getDouble(_kOther) ?? 0,
      base: SalaryBase.values.firstWhere(
        (b) => b.name == baseName,
        orElse: () => SalaryBase.projecao,
      ),
      birthday: bday == null ? null : DateTime.tryParse(bday),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, hourRate);
    await p.setDouble(_kOther, otherPct);
    await p.setString(_kBase, base.name);
    final b = birthday;
    if (b == null) {
      await p.remove(_kBday);
    } else {
      final mm = b.month.toString().padLeft(2, '0');
      final dd = b.day.toString().padLeft(2, '0');
      await p.setString(_kBday, '${b.year}-$mm-$dd');
    }
  }

  Future<void> clear() async {
    hourRate = otherPct = 0;
    base = SalaryBase.projecao;
    birthday = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRate);
    await p.remove(_kOther);
    await p.remove(_kBase);
    await p.remove(_kBday);
  }

  /// Cálculo do mês a partir dos segundos da base escolhida.
  /// O INSS sai da tabela de faixas ([inssTable]) pelo bruto do mês.
  SalaryResult compute(int seconds) {
    final hours = seconds / 3600.0;
    final bruto = hourRate * hours;
    final bracket = inssBracketFor(bruto);
    final outros = bruto * otherPct / 100;
    return SalaryResult(
      hours: hours,
      bruto: bruto,
      inss: bracket.inss,
      bracket: bracket,
      outros: outros,
      liquido: bruto - bracket.inss - outros,
    );
  }
}

class SalaryResult {
  final double hours, bruto, inss, outros, liquido;

  /// Faixa da tabela de INSS aplicada ao bruto.
  final InssBracket bracket;

  const SalaryResult({
    required this.hours,
    required this.bruto,
    required this.inss,
    required this.bracket,
    required this.outros,
    required this.liquido,
  });
}

/// Aceita "45,50" e "45.50".
double? parseNum(String s) {
  final t = s.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
