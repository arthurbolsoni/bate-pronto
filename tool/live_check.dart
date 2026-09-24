// Verificação standalone contra a API real (sem Flutter binding).
// Rodar: PONTOMAIS_ACCESS_TOKEN=... PONTOMAIS_CLIENT=... PONTOMAIS_UID=... PONTOMAIS_UUID=... dart run tool/live_check.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:controle_horas/models.dart';

void main() async {
  String env(String k) => Platform.environment[k] ?? (throw StateError('defina $k'));
  final headers = {
    'api-version': '2',
    'Content-Type': 'application/json',
    'access-token': env('PONTOMAIS_ACCESS_TOKEN'),
    'client': env('PONTOMAIS_CLIENT'),
    'uid': env('PONTOMAIS_UID'),
    'uuid': env('PONTOMAIS_UUID'),
    'token': env('PONTOMAIS_ACCESS_TOKEN'),
    'User-Agent': 'ControleHoras/1.0 (Dart)',
  };
  final url = Uri.parse('https://api.pontomais.com.br/api/time_card_control/'
      'current/work_days?start_date=2026-07-01&end_date=2026-07-23'
      '&sort_direction=asc&sort_property=date');
  final r = await http.get(url, headers: headers);
  print('HTTP ${r.statusCode}');
  if (r.statusCode >= 400) {
    print(r.body);
    return;
  }
  final j = jsonDecode(r.body);
  final days =
      (j['work_days'] as List).map((e) => WorkDay.fromJson(e)).toList();
  int worked = 0, pending = 0, awaiting = 0;
  final today = DateTime(2026, 7, 23);
  for (final d in days) {
    worked += d.workedSeconds;
    if (d.isPending(today)) {
      pending++;
      if (d.awaitingApproval) awaiting++;
    }
  }
  print('Dias: ${days.length} | Trabalhado: ${hhmm(worked)} | '
      'Pendências: $pending (aguardando aprovação: $awaiting)');
  for (final d in days.where((d) => d.isPending(today))) {
    print('  ${d.date} ${d.statusName} '
        '${d.awaitingApproval ? "[✔ aguardando]" : "[a resolver]"} '
        'batidas=${d.cards.map((c) => c.time).join(",")}');
  }
}
