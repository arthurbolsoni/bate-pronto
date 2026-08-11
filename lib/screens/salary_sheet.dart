import 'package:flutter/material.dart';
import '../models.dart';
import '../salary.dart';
import '../theme.dart';

/// Sheet de configuração do salário: valor/hora, % INSS, % outros descontos
/// e qual base de horas usar. Devolve o config salvo (ou zerado, se limpou).
class SalarySheet extends StatefulWidget {
  final SalaryConfig config;
  final int projecaoSeconds, trabalhadoSeconds, cargaSeconds;
  const SalarySheet({
    super.key,
    required this.config,
    required this.projecaoSeconds,
    required this.trabalhadoSeconds,
    required this.cargaSeconds,
  });

  @override
  State<SalarySheet> createState() => _SalarySheetState();
}

class _SalarySheetState extends State<SalarySheet> {
  late SalaryConfig _cfg;
  late TextEditingController _rate, _other;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cfg = widget.config.copy();
    String fmt(double v) =>
        v == 0 ? '' : v.toStringAsFixed(2).replaceAll('.', ',');
    _rate = TextEditingController(text: fmt(_cfg.hourRate));
    _other = TextEditingController(text: fmt(_cfg.otherPct));
  }

  @override
  void dispose() {
    _rate.dispose();
    _other.dispose();
    super.dispose();
  }

  int _secondsFor(SalaryBase b) => switch (b) {
        SalaryBase.projecao => widget.projecaoSeconds,
        SalaryBase.trabalhado => widget.trabalhadoSeconds,
        SalaryBase.carga => widget.cargaSeconds,
      };

  /// Preview ao vivo com o que está digitado agora.
  SalaryConfig get _draft => SalaryConfig(
        hourRate: parseNum(_rate.text) ?? 0,
        otherPct: parseNum(_other.text) ?? 0,
        base: _cfg.base,
      );

  Future<void> _save() async {
    final rate = parseNum(_rate.text) ?? 0;
    final other = parseNum(_other.text) ?? 0;
    if (rate <= 0) {
      setState(() => _error = 'Informe o valor da hora.');
      return;
    }
    if (other < 0 || other > 100) {
      setState(() => _error = 'Percentual deve ficar entre 0 e 100.');
      return;
    }
    _cfg
      ..hourRate = rate
      ..otherPct = other;
    await _cfg.save();
    if (mounted) Navigator.pop(context, _cfg);
  }

  Future<void> _clear() async {
    await _cfg.clear();
    if (mounted) Navigator.pop(context, _cfg);
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cfg.birthday ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: 'Data de nascimento',
    );
    if (picked != null) setState(() => _cfg.birthday = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final r = draft.compute(_secondsFor(draft.base));
    return Padding(
      // só o teclado — o inset da barra de navegação vem do SafeArea global
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: C.card,
          border: Border(top: BorderSide(color: C.acc, width: 2)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🤑  Salário do mês',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: C.mut),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                autofocus: !widget.config.isSet,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Valor da hora',
                  prefixText: r'R$ ',
                  hintText: '0,00',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _other,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Outros descontos',
                  suffixText: '%',
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SalaryBase>(
                initialValue: _cfg.base,
                dropdownColor: C.card,
                decoration: const InputDecoration(labelText: 'Base de horas'),
                items: [
                  for (final b in SalaryBase.values)
                    DropdownMenuItem(
                      value: b,
                      child: Text('${b.label} · ${hhmm(_secondsFor(b))}'),
                    ),
                ],
                onChanged: (v) => setState(() => _cfg.base = v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _pickBirthday,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de nascimento',
                    helperText:
                        'Rende day-off pago no mês (sáb/dom → sexta anterior)',
                    helperStyle: const TextStyle(color: C.mut, fontSize: 11),
                    suffixIcon: _cfg.birthday == null
                        ? const Icon(Icons.cake_outlined, color: C.mut)
                        : IconButton(
                            icon: const Icon(Icons.clear, color: C.mut),
                            onPressed: () =>
                                setState(() => _cfg.birthday = null),
                          ),
                  ),
                  child: Text(
                    _cfg.birthday == null
                        ? 'Toque para informar'
                        : _fmtDate(_cfg.birthday!),
                    style: TextStyle(
                        color: _cfg.birthday == null ? C.mut : C.fg,
                        fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // preview
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: C.bg,
                  border: Border.all(color: C.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _line('Horas (${draft.base.label.toLowerCase()})',
                        hhmm(_secondsFor(draft.base)), C.fg),
                    _line('Bruto', brl(r.bruto), C.fg),
                    _line('INSS (tabela)', '−${brl(r.inss)}', C.neg),
                    _line('Outros (${_pct(draft.otherPct)}%)',
                        '−${brl(r.outros)}', C.neg),
                    const Divider(color: C.line, height: 18),
                    _line('Líquido', brl(r.liquido), C.pos, bold: true),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: C.neg)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.config.isSet)
                    OutlinedButton(
                      onPressed: _clear,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: C.neg,
                          side: const BorderSide(color: C.line),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      child: const Text('Zerar'),
                    ),
                  if (widget.config.isSet) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Salvar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pct(double v) =>
      (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2))
          .replaceAll('.', ',');

  Widget _line(String k, String v, Color c, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(k,
                  style: TextStyle(
                      color: bold ? C.fg : C.mut,
                      fontSize: bold ? 14 : 13,
                      fontWeight: bold ? FontWeight.w600 : null)),
            ),
            Text(v,
                style: TextStyle(
                    color: c,
                    fontSize: bold ? 18 : 14,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ],
        ),
      );
}
