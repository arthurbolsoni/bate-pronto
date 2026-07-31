// Modelos da API do Pontomais (ver ../../API.md).

class Session {
  final int employeeId;
  final String name;
  final String uid;
  Session({required this.employeeId, required this.name, required this.uid});
}

class TimeCard {
  final int id;
  final String time; // "HH:MM"
  TimeCard(this.id, this.time);
}

class Motive {
  final int id; // status_id p/ a solicitação de ajuste
  final String observation; // ex.: "Ajuste", "Ausência Justificada"
  final int? statusTypeId; // 5 = Ajuste de horário, 3 = Abono
  Motive({required this.id, required this.observation, this.statusTypeId});

  factory Motive.fromJson(Map<String, dynamic> j) => Motive(
        id: j['id'],
        observation: j['observation'] ?? '',
        statusTypeId: j['status_type']?['id'],
      );
}

class Period {
  final String enter; // "08:00"
  final String leave; // "11:48"
  Period(this.enter, this.leave);
}

class WorkDay {
  final int id;
  final String date; // "YYYY-MM-DD"
  final int? statusId;
  final String? statusName;
  final double extraTime; // seg
  final double missingTime; // seg
  final double shiftTime; // seg (jornada prevista)
  final List<TimeCard> cards; // batidas ativas, ordenadas
  final List<Period> periods; // jornada prevista do dia
  final int? proposalStatusTypeId; // last_solicitation_proposal_status.status_type.id
  final String? proposalObs;

  WorkDay({
    required this.id,
    required this.date,
    required this.statusId,
    required this.statusName,
    required this.extraTime,
    required this.missingTime,
    required this.shiftTime,
    required this.cards,
    required this.periods,
    required this.proposalStatusTypeId,
    required this.proposalObs,
  });

  factory WorkDay.fromJson(Map<String, dynamic> j) {
    final cards = <TimeCard>[];
    for (final c in (j['time_cards'] as List? ?? [])) {
      if (c['disabled'] == true) continue;
      final t = (c['time'] as String).substring(0, 5);
      cards.add(TimeCard(c['id'], t));
    }
    cards.sort((a, b) => a.time.compareTo(b.time));

    final periods = <Period>[];
    for (final p in (j['shift_day']?['periods'] as List? ?? [])) {
      periods.add(Period(p['enter_time'], p['leave_time']));
    }

    final prop = j['last_solicitation_proposal_status'];
    return WorkDay(
      id: j['id'],
      date: j['date'],
      statusId: j['status']?['id'],
      statusName: j['status']?['name'],
      extraTime: (j['extra_time'] ?? 0).toDouble(),
      missingTime: (j['missing_time'] ?? 0).toDouble(),
      shiftTime: (j['shift_time'] ?? 0).toDouble(),
      cards: cards,
      periods: periods,
      proposalStatusTypeId: prop?['status_type']?['id'],
      proposalObs: prop?['observation'],
    );
  }

  bool get isOff => shiftTime == 0 && cards.isEmpty;
  bool get open => cards.length.isOdd;

  // Trabalhado = soma dos pares de batida (mais honesto que shift-missing+extra).
  int get workedSeconds {
    int sec = 0;
    for (var i = 0; i + 1 < cards.length; i += 2) {
      sec += _toMin(cards[i + 1].time) - _toMin(cards[i].time);
    }
    return sec > 0 ? sec * 60 : 0;
  }

  // Já enviado, aguardando aprovação (status_type Pendente = 1).
  bool get awaitingApproval => proposalStatusTypeId == 1;

  // Pendência a resolver: dia passado, com problema, e ainda não enviado.
  bool isPending(DateTime today) {
    if (isOff) return false;
    final d = DateTime.parse(date);
    if (!d.isBefore(DateTime(today.year, today.month, today.day))) return false;
    final badStatus = statusId != null && [2, 3, 8].contains(statusId);
    return badStatus || (open && cards.isNotEmpty);
  }

  static int _toMin(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}

String hhmm(int seconds) {
  final sign = seconds < 0 ? '−' : '';
  final a = seconds.abs();
  final h = a ~/ 3600;
  final m = (a % 3600) ~/ 60;
  return '$sign${h}h${m.toString().padLeft(2, '0')}';
}
