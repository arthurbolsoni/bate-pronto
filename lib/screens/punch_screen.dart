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
  final _api = PontomaisApi.instance;
  List<TimeCard> _today = [];
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
      final days = await _api.workDays(todayStr, todayStr);
      final last = await _api.lastCached();
      setState(() {
        _today = days.isNotEmpty ? days.first.cards : [];
        _lastText = last.isNotEmpty ? last.first.time : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // próxima batida é entrada ou saída? (par = entrada)
  String get _nextKind => _today.length.isEven ? 'ENTRADA' : 'SAÍDA';

  // Um clique bate direto (sem confirmação). Trava o botão por 1 min depois.
  // Só declara sucesso depois que o servidor confirma a batida — o register é
  // assíncrono, então antes o app mostrava "registrado" mesmo quando não entrou.
  Future<void> _punch() async {
    if (_punching || _cooldown > 0) return;
    final before = _today.length;
    setState(() {
      _punching = true;
      _error = null;
      _warn = null;
    });
    try {
      final tc = await _api.registerPunch();
      if (!mounted) return;
      await _startCooldown(); // servidor aceitou → trava o botão
      final confirmed = tc?.time ?? await _confirmPunch(before);
      if (!mounted) return;
      if (confirmed != null) {
        setState(() => _lastText = confirmed);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: C.pos,
          content: Text('Ponto registrado às $confirmed',
              style: const TextStyle(color: Colors.black)),
        ));
      } else {
        setState(() => _warn =
            'Batida enviada, mas o servidor não confirmou. Puxe para atualizar e confira antes de bater de novo.');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: C.warn,
          content: Text('Não confirmado pelo servidor — verifique',
              style: TextStyle(color: Colors.black)),
        ));
      }
      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  // Confirma a batida consultando o servidor (até ~10s).
  Future<String?> _confirmPunch(int before) async {
    for (var i = 0; i < 5; i++) {
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
        title: const Text('⏱️  Controle de Horas'),
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
                    if (_today.isEmpty)
                      const Text('Nenhuma batida hoje ainda',
                          style: TextStyle(color: C.mut))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _today.length; i++)
                            Pill(
                              '${i.isEven ? "▸" : "◂"} ${_today[i].time}',
                              bg: C.bg,
                              fg: C.fg,
                            ),
                        ],
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
