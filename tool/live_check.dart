// Verificação standalone contra a API real (sem Flutter binding).
// Rodar: dart run tool/live_check.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:controle_horas/models.dart';

void main() async {
  final headers = {
    'api-version': '2',
    'Content-Type': 'application/json',
    'access-token': '7SBWezyCk_MIgIqxTmNQTw',
    'client': 'rADbIvjgCtnWk8dBEjvWnA',
    'uid': 'arthur.bolsoni@wmcsistemas.com',
    'uuid': '39c8480b-e287-49b3-90c3-e918c25b63a6',
    'token': '7SBWezyCk_MIgIqxTmNQTw',
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
