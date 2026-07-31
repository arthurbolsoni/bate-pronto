import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../msg_history.dart';
import '../theme.dart';

const _diasSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

class _EditPunch {
  int? id; // null = nova batida
  String time; // "HH:MM"
  _EditPunch(this.time, {this.id});
}

class ResolveSheet extends StatefulWidget {
  final List<WorkDay> pending;
  final List<Motive> motives;
  const ResolveSheet({super.key, required this.pending, required this.motives});
  @override
  State<ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<ResolveSheet> {
  final _api = PontomaisApi.instance;
  int _idx = 0;
  bool _anyChanged = false;

  // estado do formulário do dia atual
  late List<_EditPunch> _punches;
  late TextEditingController _justif;
  int? _motiveId;
  bool _sending = false;
  String? _error;
  List<String> _msgHistory = [];

  @override
  void initState() {
    super.initState();
    _justif = TextEditingController();
    _initDay();
    MsgHistory.load().then((h) {
      if (mounted) setState(() => _msgHistory = h);
    });
  }

  @override
  void dispose() {
    _justif.dispose();
    super.dispose();
  }

  WorkDay get _day => widget.pending[_idx];

  void _initDay() {
    _punches =
        _day.cards.map((c) => _EditPunch(c.time, id: c.id)).toList();
    _justif.clear();
    _error = null;
    // motivo padrão = "Ajuste" (status_type 5), senão o primeiro
    final def = widget.motives.where((m) => m.statusTypeId == 5).toList();
    _motiveId = def.isNotEmpty
        ? def.first.id
        : (widget.motives.isNotEmpty ? widget.motives.first.id : null);
  }

  void _go(int delta) {
    final ni = _idx + delta;
    if (ni < 0 || ni >= widget.pending.length) return;
    setState(() {
      _idx = ni;
      _initDay();
    });
  }

  void _sortPunches() =>
      _punches.sort((a, b) => a.time.compareTo(b.time));

  Future<void> _editTime(_EditPunch p) async {
    final parts = p.time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        p.time =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        _sortPunches();
      });
    }
  }

  void _fillShift() {
    setState(() {
      _punches = _day.periods
          .expand((p) => [_EditPunch(p.enter), _EditPunch(p.leave)])
          .toList();
    });
  }

  List<Map<String, dynamic>> _buildTimes() {
    final orig = _day.cards;
    final times = <Map<String, dynamic>>[];
    // removidas
    for (final o in orig) {
      if (!_punches.any((p) => p.id == o.id)) {
        times.add({
          'time_card_id': o.id,
          'date': _day.date,
          'time': o.time,
          'disabled': true,
        });
      }
    }
    // novas / editadas
    for (final p in _punches) {
      if (p.id != null) {
        final o = orig.firstWhere((x) => x.id == p.id);
        if (o.time != p.time) {
          times.add({
            'time_card_id': p.id,
            'date': _day.date,
            'time': p.time,
            'edited': true,
          });
        }
      } else {
        times.add({'date': _day.date, 'time': p.time, 'edited': true});
      }
    }
    return times;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final justif = _justif.text.trim();
    if (justif.isEmpty) {
      setState(() => _error = 'Informe a justificativa.');
      return;
    }
    if (_motiveId == null) {
      setState(() => _error = 'Selecione o motivo.');
      return;
    }
    final times = _buildTimes();
    if (times.isEmpty) {
      setState(() => _error = 'Nenhuma alteração nas batidas.');
      return;
    }

    final resumo = times
        .map((t) => (t['disabled'] == true
                ? 'remover '
                : t.containsKey('time_card_id')
                    ? 'editar '
                    : 'add ') +
            t['time'])
        .join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Enviar ajuste'),
        content: Text(
            'Enviar solicitação REAL ao Pontomais para ${_fmtDate(_day.date)}?\n\n$resumo\nMotivo: $justif\n\nVai para aprovação do gestor.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      await _api.submitAdjust(
        date: _day.date,
        motive: justif,
        statusId: _motiveId!,
        times: times,
      );
      _anyChanged = true;
      _msgHistory = await MsgHistory.add(justif);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: C.pos,
        content: Text('Ajuste enviado! Aguardando aprovação.',
            style: TextStyle(color: Colors.black)),
      ));
      // avança ou fecha
      if (_idx < widget.pending.length - 1) {
        _go(1);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtDate(String iso) {
    final p = iso.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    final dt = DateTime.parse(d.date);
    final dow = _diasSemana[dt.weekday % 7];

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: C.card,
          border: Border(top: BorderSide(color: C.warn, width: 2)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            // handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Pill('Pendência ${_idx + 1} de ${widget.pending.length}',
                      bg: const Color(0xFF3A2F1A), fg: C.warn),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: C.mut),
                    onPressed: () => Navigator.pop(context, _anyChanged),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text('${_fmtDate(d.date)} · $dow',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    if (d.statusName != null)
                      Pill(d.statusName!,
                          bg: const Color(0xFF3A2F1A), fg: C.warn),
                  ]),
                  const SizedBox(height: 20),
                  if (d.awaitingApproval)
                    _sentBox(d)
                  else
                    _form(d),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _sentBox(WorkDay d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12331F),
        border: Border.all(color: const Color(0xFF1C4D2E)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text('✔', style: TextStyle(fontSize: 20, color: C.pos)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Solicitação enviada · aguardando aprovação',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: C.pos)),
                const SizedBox(height: 2),
                Text(
                    '${d.proposalObs != null ? "Motivo: ${d.proposalObs} · " : ""}Batidas: ${d.cards.map((c) => c.time).join("  ")}',
                    style: const TextStyle(color: C.mut, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(WorkDay d) {
    _sortPunches();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Batidas (entrada/saída, alternadas):',
            style: TextStyle(color: C.mut, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _punches)
              Container(
                decoration: BoxDecoration(
                  color: C.bg,
                  border: Border.all(color: C.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _editTime(p),
                      child: Text(p.time,
                          style: const TextStyle(
                              color: C.fg, fontWeight: FontWeight.w600)),
                    ),
                    InkWell(
                      onTap: () => setState(() => _punches.remove(p)),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8, left: 2),
                        child: Icon(Icons.close, size: 16, color: C.mut),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _punches.add(_EditPunch('12:00'))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('batida'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: C.fg,
                  side: const BorderSide(color: C.line)),
            ),
            const SizedBox(width: 8),
            if (d.periods.isNotEmpty)
              OutlinedButton(
                onPressed: _fillShift,
                style: OutlinedButton.styleFrom(
                    foregroundColor: C.fg,
                    side: const BorderSide(color: C.line)),
                child: const Text('preencher jornada'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
          initialValue: _motiveId,
          dropdownColor: C.card,
          decoration: const InputDecoration(labelText: 'Motivo'),
          items: [
            for (final m in widget.motives)
              DropdownMenuItem(value: m.id, child: Text(m.observation)),
          ],
          onChanged: (v) => setState(() => _motiveId = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _justif,
          decoration: const InputDecoration(
              labelText: 'Justificativa',
              hintText: 'ex.: esqueci de bater a saída'),
        ),
        if (_msgHistory.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Mensagens recentes (toque p/ usar · segure p/ remover):',
              style: TextStyle(color: C.mut, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _msgHistory)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() {
                    _justif.text = m;
                    _justif.selection = TextSelection.collapsed(
                        offset: m.length);
                  }),
                  onLongPress: () async {
                    final h = await MsgHistory.remove(m);
                    if (mounted) setState(() => _msgHistory = h);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: C.bg,
                      border: Border.all(color: C.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(m,
                        style: const TextStyle(color: C.fg, fontSize: 13)),
                  ),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: C.neg)),
        ],
      ],
    );
  }

  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _idx > 0 ? () => _go(-1) : null,
          ),
          Expanded(
            child: _day.awaitingApproval
                ? const Center(
                    child: Text('Já enviado',
                        style: TextStyle(color: C.mut)))
                : ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Enviar ajuste'),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _idx < widget.pending.length - 1
                ? () => _go(1)
                : null,
          ),
        ],
      ),
    );
  }
}
