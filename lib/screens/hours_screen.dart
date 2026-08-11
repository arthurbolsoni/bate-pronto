import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../salary.dart';
import '../theme.dart';
import 'resolve_sheet.dart';
import 'salary_sheet.dart';

const meses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
];
const diasSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key});
  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> {
  final _api = PontomaisApi.instance;
  int _offset = 0; // 0 = mês atual, 1 = anterior, ...
  List<WorkDay> _days = [];
  List<Motive> _motives = [];
  bool _loading = true;
  String? _error;
  SalaryConfig _salary = SalaryConfig();

  @override
  void initState() {
    super.initState();
    _load();
    _api.proposalMotives().then((m) => setState(() => _motives = m));
    MoneyPrivacy.load();
    SalaryConfig.load().then((s) {
      if (mounted) setState(() => _salary = s);
    });
  }

  DateTime get _targetMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _offset, 1);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = _targetMonth;
      final now = DateTime.now();
      final isCurrent = t.year == now.year && t.month == now.month;
      final start = '${t.year}-${_two(t.month)}-01';
      final lastDay = DateTime(t.year, t.month + 1, 0).day;
      final end = isCurrent
          ? '${now.year}-${_two(now.month)}-${_two(now.day)}'
          : '${t.year}-${_two(t.month)}-${_two(lastDay)}';
      final days = await _api.workDays(start, end);
      setState(() => _days = days);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Data (ISO) do day-off de aniversário no mês exibido, ou null.
  DateTime? get _dayOff {
    final t = _targetMonth;
    return birthdayDayOffInMonth(_salary.birthday, t.year, t.month);
  }

  String? get _dayOffIso {
    final d = _dayOff;
    return d == null ? null : '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  // Um day-off pago vale um turno normal; 0 se não cai neste mês.
  int get _dayOffSeconds => _dayOff == null ? 0 : _normalDailyShift;

  List<WorkDay> get _pending {
    final today = DateTime.now();
    final offIso = _dayOffIso;
    // O day-off de aniversário é folga legítima — nunca vira pendência.
    return _days
        .where((d) => d.date != offIso && d.isPending(today))
        .toList();
  }

  int get _workedSeconds => _days.fold(0, (a, d) => a + d.workedSeconds);

  // turno normal diário (11h48 = 31680s), inferido dos dias com jornada
  int get _normalDailyShift {
    final shifts = _days.map((d) => d.shiftTime).where((s) => s > 0);
    if (shifts.isEmpty) return 31680;
    return shifts.reduce((a, b) => a > b ? a : b).round();
  }

  // Projeção do mês: dias passados sem pendência = trabalhado real;
  // dias futuros/hoje/pendentes = carga normal. + carga normal total do mês.
  ({int projection, int carga}) _monthTotals() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final t = _targetMonth;
    final lastDay = DateTime(t.year, t.month + 1, 0).day;
    final byIso = {for (final d in _days) d.date: d};
    final normal = _normalDailyShift;
    final offIso = _dayOffIso;

    int projection = 0, carga = 0;
    for (int day = 1; day <= lastDay; day++) {
      final date = DateTime(t.year, t.month, day);
      final iso = '${t.year}-${_two(t.month)}-${_two(day)}';
      final wd = byIso[iso];
      final isWeekday = date.weekday <= 5; // seg-sex

      // Day-off de aniversário: dia normal pago sem trabalhar. Substitui a
      // contribuição do dia por um turno normal (não soma por cima).
      if (iso == offIso) {
        carga += normal;
        projection += normal;
        continue;
      }

      // carga esperada do dia (real se existe, senão dia útil = turno normal)
      final expected =
          wd != null ? wd.shiftTime.round() : (isWeekday ? normal : 0);
      carga += expected;

      final pastResolved =
          wd != null && date.isBefore(today) && !wd.isPending(today);
      projection += pastResolved ? wd.workedSeconds : expected;
    }
    return (projection: projection, carga: carga);
  }

  String _monthLabel(int off) {
    final now = DateTime.now();
    final t = DateTime(now.year, now.month - off, 1);
    final base = '${meses[t.month - 1]} ${t.year}';
    if (off == 0) return 'Mês atual — $base';
    if (off == 1) return 'Mês anterior — $base';
    return base;
  }

  Future<void> _openResolver() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResolveSheet(pending: _pending, motives: _motives),
    );
    if (changed == true) _load();
  }

  Future<void> _openSalary() async {
    final m = _monthTotals();
    final saved = await showModalBottomSheet<SalaryConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SalarySheet(
        config: _salary,
        projecaoSeconds: m.projection,
        trabalhadoSeconds: _workedSeconds + _dayOffSeconds,
        cargaSeconds: m.carga,
      ),
    );
    if (saved != null) setState(() => _salary = saved);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ver Horas'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: MoneyPrivacy.hidden,
            builder: (_, hidden, _) => IconButton(
              icon: Icon(hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              tooltip: hidden ? 'Mostrar valores' : 'Esconder valores',
              onPressed: MoneyPrivacy.toggle,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          // inset da barra de navegação já vem do SafeArea global (main.dart)
          padding: const EdgeInsets.all(16),
          children: [
            _monthNav(),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: C.neg)),
                ),
              )
            else ...[
              if (pending.isNotEmpty) _pendCard(pending),
              _totals(),
              const SizedBox(height: 16),
              _projectionCards(),
              const SizedBox(height: 12),
              _salaryCard(),
              const SizedBox(height: 16),
              _table(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthNav() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              // mês anterior = offset+1
              onPressed: _offset < 23
                  ? () => setState(() {
                        _offset++;
                        _load();
                      })
                  : null,
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _offset,
                  dropdownColor: C.card,
                  alignment: Alignment.center,
                  items: [
                    for (int i = 0; i < 24; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Center(
                          child: Text(_monthLabel(i),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _offset = v!;
                    _load();
                  }),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              // próximo mês = offset-1; não passa do atual
              onPressed: _offset > 0
                  ? () => setState(() {
                        _offset--;
                        _load();
                      })
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendCard(List<WorkDay> pending) {
    final sent = pending.where((d) => d.awaitingApproval).length;
    final todo = pending.length - sent;
    final parts = <String>[];
    if (todo > 0) parts.add('$todo a resolver');
    if (sent > 0) parts.add('$sent ✔ aguardando aprovação');
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: C.warn),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${pending.length} pendência${pending.length > 1 ? "s" : ""} neste mês',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(parts.join('  ·  '),
                      style: const TextStyle(color: C.mut, fontSize: 13)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _openResolver,
              child: const Text('Resolver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totals() {
    int worked = 0;
    double extra = 0, missing = 0;
    int diasComBatida = 0;
    for (final d in _days) {
      worked += d.workedSeconds;
      extra += d.extraTime;
      missing += d.missingTime;
      if (d.cards.isNotEmpty) diasComBatida++;
    }
    final saldo = (extra - missing).round();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _stat('Trabalhado', hhmm(worked), C.fg),
          _stat('Extra', hhmm(extra.round()), C.pos),
          _stat('Faltas', hhmm(missing.round()), C.neg),
          _stat('Saldo', hhmm(saldo), saldo >= 0 ? C.pos : C.neg),
          _stat('Dias', '$diasComBatida', C.fg),
        ],
      ),
    );
  }

  Widget _stat(String k, String v, Color c) => Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.toUpperCase(),
                style: const TextStyle(
                    color: C.mut, fontSize: 11, letterSpacing: .5)),
            const SizedBox(height: 2),
            Text(v,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: c)),
          ],
        ),
      );

  Widget _projectionCards() {
    final m = _monthTotals();
    return Column(
      children: [
        _bigCard(
          icon: Icons.trending_up,
          color: C.acc,
          title: 'Projeção do mês',
          value: hhmm(m.projection),
          sub: 'Dias sem pendência (real) + restante com carga normal',
        ),
        const SizedBox(height: 12),
        _bigCard(
          icon: Icons.event_available,
          color: C.mut,
          title: 'Carga normal do mês',
          value: hhmm(m.carga),
          sub: 'Jornada prevista somando todos os dias úteis',
        ),
      ],
    );
  }

  // Card do salário: zerado até configurar valor/hora. Toque abre o SalarySheet.
  // Com o olhinho ligado os valores em R$ viram máscara.
  Widget _salaryCard() => ValueListenableBuilder<bool>(
        valueListenable: MoneyPrivacy.hidden,
        builder: (_, hide, _) => _salaryCardBody(hide),
      );

  Widget _salaryCardBody(bool hide) {
    final m = _monthTotals();
    final seconds = switch (_salary.base) {
      SalaryBase.projecao => m.projection,
      SalaryBase.trabalhado => _workedSeconds + _dayOffSeconds,
      SalaryBase.carga => m.carga,
    };
    final r = _salary.compute(seconds);
    final set = _salary.isSet;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openSalary,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (set ? C.pos : C.mut).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: set ? 1 : 0.55,
                        child: const Text('🤑',
                            style: TextStyle(fontSize: 26)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Salário do mês',
                            style: TextStyle(fontSize: 13, color: C.mut)),
                        const SizedBox(height: 2),
                        Text(brl(set ? r.liquido : 0, hide: set && hide),
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: set ? C.pos : C.fg)),
                        const SizedBox(height: 2),
                        Text(
                          set
                              ? '${brl(_salary.hourRate, hide: hide)}/h · ${hhmm(seconds)} · ${_salary.base.label.toLowerCase()}'
                              : 'Toque para informar valor/hora e descontos',
                          style: const TextStyle(fontSize: 12, color: C.mut),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 18, color: C.mut),
                ],
              ),
              if (set) ...[
                const Divider(color: C.line, height: 22),
                if (_dayOff != null)
                  _salaryLine(
                      'Day-off aniversário (${_dayOff!.day}/${_two(_dayOff!.month)} · +${hhmm(_dayOffSeconds)})',
                      'incluso',
                      C.pos),
                _salaryLine('Bruto', brl(r.bruto, hide: hide), C.fg),
                if (r.inss > 0)
                  _salaryLine('INSS (tabela)',
                      '−${brl(r.inss, hide: hide)}', C.neg),
                if (_salary.otherPct > 0)
                  _salaryLine('Outros (${_fmtPct(_salary.otherPct)}%)',
                      '−${brl(r.outros, hide: hide)}', C.neg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmtPct(double v) =>
      (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2))
          .replaceAll('.', ',');

  Widget _salaryLine(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(color: C.mut, fontSize: 13))),
            Text(v,
                style: TextStyle(
                    color: c, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _bigCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String sub,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, color: C.mut)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color == C.mut ? C.fg : color)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(fontSize: 12, color: C.mut)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table() {
    return ValueListenableBuilder<bool>(
      valueListenable: MoneyPrivacy.hidden,
      builder: (_, hide, _) => Card(
        child: Column(
          children: [
            for (final d in _days) _row(d, hide),
          ],
        ),
      ),
    );
  }

  Widget _row(WorkDay d, bool hide) {
    final dt = DateTime.parse(d.date);
    final dow = diasSemana[dt.weekday % 7];
    final cardsText = d.cards.map((c) => c.time).join('  ');
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_two(dt.day)}/${_two(dt.month)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: d.isOff ? C.mut : C.fg)),
                Text(dow, style: const TextStyle(color: C.mut, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.isOff
                      ? '—'
                      : (cardsText.isEmpty ? 'sem batida' : cardsText),
                  style: TextStyle(
                      color: d.cards.isEmpty ? C.mut : C.fg, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (!d.isOff && d.statusName != null)
                      Pill(d.statusName!),
                    if (d.open && d.cards.isNotEmpty)
                      const Pill('nº ímpar',
                          bg: Color(0xFF3A2F1A), fg: C.warn),
                    if (d.awaitingApproval)
                      const Pill('✔ aguardando aprovação',
                          bg: Color(0xFF12331F), fg: C.pos),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(d.isOff ? '—' : hhmm(d.workedSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (d.extraTime > 0)
                Text('+${hhmm(d.extraTime.round())}',
                    style: const TextStyle(color: C.pos, fontSize: 12)),
              if (d.missingTime > 0)
                Text('−${hhmm(d.missingTime.round())}',
                    style: const TextStyle(color: C.neg, fontSize: 12)),
              if (_salary.isSet && !d.isOff && d.workedSeconds > 0)
                Text(brl(_salary.hourRate * d.workedSeconds / 3600, hide: hide),
                    style: const TextStyle(color: C.acc, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
