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
  static const _kInss = 'salary_inss_pct';
  static const _kOther = 'salary_other_pct';
  static const _kBase = 'salary_base';

  double hourRate;
  double inssPct;
  double otherPct;
  SalaryBase base;

  SalaryConfig({
    this.hourRate = 0,
    this.inssPct = 0,
    this.otherPct = 0,
    this.base = SalaryBase.projecao,
  });

  bool get isSet => hourRate > 0;

  SalaryConfig copy() => SalaryConfig(
        hourRate: hourRate,
        inssPct: inssPct,
        otherPct: otherPct,
        base: base,
      );

  static Future<SalaryConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final baseName = p.getString(_kBase);
    return SalaryConfig(
      hourRate: p.getDouble(_kRate) ?? 0,
      inssPct: p.getDouble(_kInss) ?? 0,
      otherPct: p.getDouble(_kOther) ?? 0,
      base: SalaryBase.values.firstWhere(
        (b) => b.name == baseName,
        orElse: () => SalaryBase.projecao,
      ),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRate, hourRate);
    await p.setDouble(_kInss, inssPct);
    await p.setDouble(_kOther, otherPct);
    await p.setString(_kBase, base.name);
  }

  Future<void> clear() async {
    hourRate = inssPct = otherPct = 0;
    base = SalaryBase.projecao;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRate);
    await p.remove(_kInss);
    await p.remove(_kOther);
    await p.remove(_kBase);
  }

  /// Cálculo do mês a partir dos segundos da base escolhida.
  SalaryResult compute(int seconds) {
    final hours = seconds / 3600.0;
    final bruto = hourRate * hours;
    final inss = bruto * inssPct / 100;
    final outros = bruto * otherPct / 100;
    return SalaryResult(
      hours: hours,
      bruto: bruto,
      inss: inss,
      outros: outros,
      liquido: bruto - inss - outros,
    );
  }
}

class SalaryResult {
  final double hours, bruto, inss, outros, liquido;
  const SalaryResult({
    required this.hours,
    required this.bruto,
    required this.inss,
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
