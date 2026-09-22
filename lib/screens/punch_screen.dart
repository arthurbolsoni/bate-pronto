import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'hours_screen.dart';
import 'login_screen.dart';

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen>
    with WidgetsBindingObserver {
  static const _cooldownSeconds = 60; // trava o botão após bater (anti duplo clique)
  static const _kCooldownUntil = 'punch_cooldown_until'; // millis epoch
  static const _kQueued = 'punch_queued'; // "YYYY-MM-DD HH:mm" ainda na fila
  final _api = PontomaisApi.instance;
  List<TimeCard> _today = [];
  List<String> _queued = []; // batidas aceitas que o espelho ainda não mostra
  String? _lastText;
  bool _loading = true;
  bool _punching = false;
  String? _error;
  String? _warn;
  int _cooldown = 0;
  DateTime? _cooldownUntil;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCooldown();
    _loadQueued();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Android pode congelar o processo em background e o Timer para de disparar.
  // Ao voltar, recalcula o cooldown pelo relógio e revalida as batidas.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tickCooldown();
      _refresh();
    }
  }

  Future<void> _restoreCooldown() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kCooldownUntil);
    if (ms == null) return;
    _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(ms);
    _tickCooldown();
  }

  Future<void> _startCooldown() async {
    _cooldownUntil =
        DateTime.now().add(const Duration(seconds: _cooldownSeconds));
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCooldownUntil, _cooldownUntil!.millisecondsSinceEpoch);
    _tickCooldown();
  }

  // Fonte da verdade do cooldown = timestamp alvo, não o contador.
  void _tickCooldown() {
    _timer?.cancel();
    final left = _remaining();
    if (mounted) setState(() => _cooldown = left);
    if (left <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final r = _remaining();
      setState(() => _cooldown = r);
      if (r <= 0) t.cancel();
    });
  }

  int _remaining() {
    final until = _cooldownUntil;
    if (until == null) return 0;
    final s = until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Em paralelo: uma request lenta não soma no tempo da outra.
      final r = await Future.wait([
        _api.workDays(todayStr, todayStr),
        // o último registro é enfeite — não pode derrubar a tela inteira
        _api.lastCached().catchError((_) => <TimeCard>[]),
      ]);
      final days = r[0] as List<WorkDay>;
      final last = r[1] as List<TimeCard>;
      final cards = days.isNotEmpty ? days.first.cards : <TimeCard>[];
      await _pruneQueued(cards);
      setState(() {
        _today = cards;
        if (last.isNotEmpty) _lastText = last.first.time;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _todayIso => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ---- batidas na fila ----------------------------------------------------
  // O register é assíncrono: o servidor aceita a batida e só depois a grava no
  // espelho. Até lá ela fica guardada aqui e aparece na lista, como o app2 faz.

  Future<void> _loadQueued() async {
    final p = await SharedPreferences.getInstance();
    final hoje = _todayIso;
    final keep = (p.getStringList(_kQueued) ?? [])
        .where((e) => e.startsWith('$hoje '))
        .toList();
    await p.setStringList(_kQueued, keep);
    if (mounted) {
      setState(() => _queued = keep.map((e) => e.substring(11)).toList());
    }
  }

  Future<void> _addQueued(String time) async {
    final p = await SharedPreferences.getInstance();
    final all = (p.getStringList(_kQueued) ?? [])..add('$_todayIso $time');
    await p.setStringList(_kQueued, all);
    await _loadQueued();
  }

  static int _min(String hhmm) =>
      int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

  // O espelho alcançou? Então a cópia local não é mais necessária. Tolera 1min
  // de diferença: o horário que o servidor grava nem sempre é o da fila.
  Future<void> _pruneQueued(List<TimeCard> server) async {
    if (_queued.isEmpty) return;
    final gravadas = server.map((c) => _min(c.time)).toList();
    bool naFila(String e) {
      if (!e.startsWith('$_todayIso ')) return true; // outro dia: _loadQueued limpa
      final m = _min(e.substring(11));
      return !gravadas.any((g) => (g - m).abs() <= 1);
    }

    final p = await SharedPreferences.getInstance();
    final keep = (p.getStringList(_kQueued) ?? []).where(naFila).toList();
    await p.setStringList(_kQueued, keep);
    if (mounted) {
      setState(() => _queued = keep
          .where((e) => e.startsWith('$_todayIso '))
          .map((e) => e.substring(11))
          .toList());
    }
  }

  // Batidas de hoje como o usuário deve vê-las: o que o servidor já gravou
  // mais o que ele aceitou e ainda não processou.
  List<({String time, bool queued})> get _cards {
    final out = [
      for (final c in _today) (time: c.time, queued: false),
      for (final t in _queued) (time: t, queued: true),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  // próxima batida é entrada ou saída? (par = entrada)
  String get _nextKind => _cards.length.isEven ? 'ENTRADA' : 'SAÍDA';

  // Um clique bate direto (sem confirmação). Trava o botão por 1 min depois.
  Future<void> _punch() async {
    if (_punching || _cooldown > 0) return;
    final before = _today.length;
    setState(() {
      _punching = true;
      _error = null;
      _warn = null;
    });
    try {
      final r = await _api.registerPunch();
      if (!mounted) return;
      await _startCooldown(); // servidor aceitou → trava o botão
      final time = r.time;
      if (time != null) {
        await _addQueued(time);
        if (!mounted) return;
        setState(() => _lastText = time);
        _toast('Ponto registrado às $time', C.pos);
      } else {
        // aceito sem devolver horário: aí sim vale perguntar ao servidor
        await _confirmOrWarn(before);
      }
      await _refresh();
    } on ApiTimeoutException {
      // A batida pode ter entrado mesmo assim — nunca mandar bater de novo
      // às cegas. Trava o botão e confere no servidor.
      if (!mounted) return;
      await _startCooldown();
      await _confirmOrWarn(before);
      if (mounted) await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  Future<void> _confirmOrWarn(int before) async {
    final confirmed = await _confirmPunch(before);
    if (!mounted) return;
    if (confirmed != null) {
      setState(() => _lastText = confirmed);
      _toast('Ponto registrado às $confirmed', C.pos);
    } else {
      setState(() => _warn =
          'A resposta do servidor não veio. A batida pode ter entrado — puxe '
          'para atualizar e confira antes de bater de novo.');
      _toast('Sem confirmação do servidor — verifique', C.warn);
    }
  }

  void _toast(String msg, Color bg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: bg,
        content: Text(msg, style: const TextStyle(color: Colors.black)),
      ));

  // Consulta o servidor procurando a batida nova (até ~6s).
  Future<String?> _confirmPunch(int before) async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return null;
      try {
        final cards = await _api.todayCards();
        if (cards.length > before) {
          final times = cards.map((c) => c.time).toList()..sort();
          setState(() => _today = cards);
          return times.last;
        }
      } catch (_) {
        // rede instável no meio da confirmação — tenta de novo
      }
    }
    return null;
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏱️  Bate Pronto'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout, color: C.mut),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  Text(DateFormat('HH:mm').format(now),
                      style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [])),
                  Text(
                      DateFormat("EEEE, d 'de' MMMM", 'pt_BR')
                          .format(now)
                          .replaceFirstMapped(RegExp(r'^\w'),
                              (m) => m.group(0)!.toUpperCase()),
                      style: const TextStyle(color: C.mut)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: C.neg)),
              ),
            if (_warn != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_warn!, style: const TextStyle(color: C.warn)),
              ),
            Center(
              child: GestureDetector(
                onTap: (_punching || _cooldown > 0) ? null : _punch,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _cooldown > 0
                          ? [C.line, C.card]
                          : [C.acc, C.acc.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: _cooldown > 0
                        ? null
                        : [
                            BoxShadow(
                                color: C.acc.withValues(alpha: 0.35),
                                blurRadius: 30,
                                spreadRadius: 4),
                          ],
                  ),
                  child: Center(
                    child: _punching
                        ? const CircularProgressIndicator(color: Colors.white)
                        : _cooldown > 0
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock_clock,
                                      size: 48, color: C.mut),
                                  const SizedBox(height: 6),
                                  Text('Aguarde\n${_cooldown}s',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: C.mut,
                                          fontWeight: FontWeight.bold)),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.fingerprint,
                                      size: 56, color: Colors.white),
                                  const SizedBox(height: 4),
                                  Text(
                                      _loading ? '...' : 'Registrar\n$_nextKind',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Último registro',
                            style: TextStyle(color: C.mut)),
                        Text(_lastText ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                      ],
                    ),
                    const Divider(color: C.line, height: 24),
                    const Text('Batidas de hoje',
                        style: TextStyle(color: C.mut)),
                    const SizedBox(height: 8),
                    if (_cards.isEmpty)
                      const Text('Nenhuma batida hoje ainda',
                          style: TextStyle(color: C.mut))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _cards.length; i++)
                            Pill(
                              '${i.isEven ? "▸" : "◂"} ${_cards[i].time}'
                              '${_cards[i].queued ? " ⏳" : ""}',
                              bg: C.bg,
                              fg: _cards[i].queued ? C.mut : C.fg,
                            ),
                        ],
                      ),
                    if (_queued.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('⏳ enviada, aguardando o espelho do Pontomais',
                            style: TextStyle(color: C.mut, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _NavButton(
              icon: Icons.calendar_month,
              label: 'Ver Horas',
              sub: 'Espelho do mês, saldo e pendências',
              color: C.pos,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HoursScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  const _NavButton({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
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
                    Text(label,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(color: C.mut, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: C.mut),
            ],
          ),
        ),
      ),
    );
  }
}
