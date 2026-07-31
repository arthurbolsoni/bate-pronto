import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Cliente da API do Pontomais. Guarda os tokens (devise-token-auth) em
/// SharedPreferences e injeta os headers em toda request.
class PontomaisApi {
  static const _base = 'https://api.pontomais.com.br';
  static final PontomaisApi instance = PontomaisApi._();
  PontomaisApi._();

  static const _secure = FlutterSecureStorage();

  String? accessToken, client, uid, uuid;
  int? employeeId;
  String? employeeName;

  bool get loggedIn => (accessToken?.isNotEmpty ?? false);

  // token capturado antigo — se ainda estiver salvo de versões anteriores,
  // limpa pra forçar login de verdade (com senha) desta vez.
  static const _oldSeedToken = '7SBWezyCk_MIgIqxTmNQTw';

  // uuid do dispositivo — OBRIGATÓRIO no header pra registrar ponto (sem ele
  // a API responde 403). O sign_in não devolve, então usamos um fixo/persistente.
  static const _defaultUuid = '39c8480b-e287-49b3-90c3-e918c25b63a6';

  Future<void> loadCreds() async {
    final p = await SharedPreferences.getInstance();
    accessToken = p.getString('accessToken');
    client = p.getString('client');
    uid = p.getString('uid');
    uuid = p.getString('uuid');
    employeeId = p.getInt('employeeId');
    employeeName = p.getString('employeeName');

    if (accessToken == _oldSeedToken) {
      await logout(); // migração: descarta o token semeado antigo
    }
    if ((uuid ?? '').isEmpty) uuid = _defaultUuid;
  }

  Future<void> _saveCreds() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('accessToken', accessToken ?? '');
    await p.setString('client', client ?? '');
    await p.setString('uid', uid ?? '');
    await p.setString('uuid', uuid ?? '');
    if (employeeId != null) await p.setInt('employeeId', employeeId!);
    if (employeeName != null) await p.setString('employeeName', employeeName!);
  }

  Future<void> logout() async {
    accessToken = client = uid = uuid = employeeName = null;
    employeeId = null;
    final p = await SharedPreferences.getInstance();
    await p.clear();
    await _secure.deleteAll();
  }

  // origin/referer são exigidos pelos endpoints de escrita (ex.: register) —
  // sem eles a API responde 403 "não autorizado a acessar esta ação".
  static const _origin = 'https://app2.pontomais.com.br';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36';

  Map<String, String> get _headers => {
        'api-version': '2',
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'access-token': accessToken ?? '',
        'client': client ?? '',
        'uid': uid ?? '',
        'uuid': uuid ?? '',
        'token': accessToken ?? '',
        'Origin': _origin,
        'Referer': '$_origin/',
        'User-Agent': _ua,
      };

  // devise-token-auth pode rotacionar o token a cada request; captura o novo.
  void _absorbTokens(http.Response r) {
    final t = r.headers['access-token'];
    final c = r.headers['client'];
    if (t != null && t.isNotEmpty) accessToken = t;
    if (c != null && c.isNotEmpty) client = c;
  }

  // sessão expirou de vez? (token inválido / redirect_to_login)
  bool _sessionExpired(http.Response r) {
    if (r.statusCode != 401 && r.statusCode != 403) return false;
    return r.body.contains('redirect_to_login') ||
        r.body.contains('Faça login');
  }

  // re-login automático usando a senha guardada no secure storage.
  Future<bool> _reauth() async {
    final email = await _secure.read(key: 'email');
    final pass = await _secure.read(key: 'password');
    if (email == null || pass == null) return false;
    try {
      await signIn(email, pass);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _get(String path, {bool retry = true}) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers);
    _absorbTokens(r);
    if (_sessionExpired(r)) {
      if (retry && await _reauth()) return _get(path, retry: false);
      throw ApiException(r.statusCode, 'Sessão expirou. Faça login.');
    }
    if (r.statusCode >= 400) throw ApiException(r.statusCode, r.body);
    await _saveCreds();
    return _decode(r);
  }

  // 202/204 podem vir com corpo vazio — jsonDecode('') estoura FormatException.
  static dynamic _decode(http.Response r) {
    if (r.body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(r.body);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body,
      {bool retry = true}) async {
    final r = await http.post(Uri.parse('$_base$path'),
        headers: _headers, body: jsonEncode(body));
    _absorbTokens(r);
    if (_sessionExpired(r)) {
      if (retry && await _reauth()) return _post(path, body, retry: false);
      throw ApiException(r.statusCode, 'Sessão expirou. Faça login.');
    }
    if (r.statusCode >= 400) {
      String msg = r.body;
      try {
        final j = jsonDecode(r.body);
        msg = j['error']?['message'] ??
            (j['errors'] is List ? (j['errors'] as List).join(', ') : null) ??
            j['error'] ??
            r.body;
      } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
    await _saveCreds();
    final j = _decode(r);
    // alguns endpoints devolvem 200 com {"error": ...} no corpo
    if (j is Map && j['error'] != null) {
      final e = j['error'];
      throw ApiException(r.statusCode,
          (e is Map ? (e['message'] ?? e.toString()) : e.toString()));
    }
    return j;
  }

  // ---------- login ----------
  Future<void> signIn(String email, String password) async {
    final r = await http.post(
      Uri.parse('$_base/api/auth/sign_in'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'api-version': '2',
        'Origin': _origin,
        'Referer': '$_origin/',
        'User-Agent': _ua,
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (r.statusCode >= 400) {
      String msg = 'Falha no login';
      try {
        final j = jsonDecode(r.body);
        msg = (j['errors'] is List ? (j['errors'] as List).join(', ') : null) ??
            j['error'] ??
            msg;
      } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
    accessToken = r.headers['access-token'];
    client = r.headers['client'];
    uid = r.headers['uid'] ?? email;

    final body = jsonDecode(r.body);
    final emp = body['employee'] ?? body['user'] ?? {};
    employeeId = emp['id'] ?? emp['employee_id'];
    employeeName = emp['name'] ?? emp['first_name'];
    // uuid do device: mantém o existente; nunca deixa vazio (register exige)
    final respUuid = emp['uuid'];
    if (respUuid is String && respUuid.isNotEmpty) uuid = respUuid;
    if ((uuid ?? '').isEmpty) uuid = _defaultUuid;

    // completa dados do funcionário via /session se faltou
    if (employeeId == null || employeeName == null) {
      try {
        final s = await _get('/api/session');
        final e = s['session']?['employee'];
        employeeId ??= e?['id'];
        employeeName ??= e?['name'];
      } catch (_) {}
    }
    await _saveCreds();
    // guarda credenciais pra re-login automático quando o token expirar
    await _secure.write(key: 'email', value: email);
    await _secure.write(key: 'password', value: password);
  }

  // ---------- ver pontos ----------
  Future<List<WorkDay>> workDays(String startDate, String endDate) async {
    final j = await _get('/api/time_card_control/current/work_days'
        '?start_date=$startDate&end_date=$endDate'
        '&sort_direction=asc&sort_property=date');
    final list = (j['work_days'] as List? ?? [])
        .map((e) => WorkDay.fromJson(e))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  // últimas batidas (para a tela de bater ponto)
  Future<List<TimeCard>> lastCached() async {
    final j = await _get('/api/time_cards/current/last_cached');
    return (j['time_cards'] as List? ?? [])
        .map((c) => TimeCard(c['id'], (c['time'] as String).substring(0, 5)))
        .toList();
  }

  Future<List<Motive>> proposalMotives() async {
    try {
      final j = await _get(
          '/api/time_cards/proposals/status?sort_property=name&sort_direction=asc');
      return (j['status'] as List? ?? [])
          .where((m) => m['active'] == true)
          .map((m) => Motive.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------- bater ponto ----------
  /// Registra a batida. Devolve a batida quando o servidor já a confirma no
  /// corpo; devolve null quando aceitou pra processar depois (202/corpo vazio)
  /// — nesse caso a tela precisa confirmar consultando o servidor.
  Future<TimeCard?> registerPunch() async {
    final body = {
      'image': null,
      'employee': {'id': employeeId, 'pin': null},
      'time_card': {
        'latitude': 0,
        'longitude': 0,
        'address': '',
        'reference_id': null,
        'original_latitude': null,
        'original_longitude': null,
        'original_address': null,
        'location_edited': true,
        'accuracy': 1100,
        'accuracy_method': null,
        'image': null,
        'info': null,
      },
      '_path': '/registrar-ponto',
      '_appVersion': '0.10.32',
      '_device': {
        'manufacturer': 'null',
        'model': 'null',
        'uuid': accessToken,
        'version': 'null',
      },
    };
    final j = await _post('/api/time_cards/register', body);
    final tc = j['time_card'] ?? j['employee']?['time_cards']?.last ?? {};
    final time = (tc['time'] ?? '').toString();
    if (time.length < 5) return null; // aceito, mas ainda não confirmado
    return TimeCard(tc['id'] ?? 0, time.substring(0, 5));
  }

  /// Batidas de hoje direto do servidor (fonte da verdade pra confirmar).
  Future<List<TimeCard>> todayCards() async {
    final now = DateTime.now();
    final iso = '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
    final days = await workDays(iso, iso);
    return days.isNotEmpty ? days.first.cards : <TimeCard>[];
  }

  // ---------- resolver pendência (solicitação de ajuste) ----------
  // times: cada item = {date, time, edited:true} (nova) |
  //   {time_card_id, date, time, edited:true} (editar) |
  //   {time_card_id, date, time, disabled:true} (remover)
  Future<void> submitAdjust({
    required String date,
    required String motive,
    required int statusId,
    required List<Map<String, dynamic>> times,
  }) async {
    Map<String, dynamic> bodyFor(int proposalType) => {
          'proposal': {
            'date': date,
            'motive': motive,
            'times_attributes': times,
            'proposal_type': proposalType,
            'status_id': statusId,
            'employee_id': employeeId,
            'file': null,
          },
          '_path': '/meu-ponto',
          '_appVersion': '0.10.32',
          '_device': {
            'browser': {
              'name': 'Flutter',
              'version': '1',
              'versionSearchString': 'Flutter'
            }
          },
        };

    // O grupo "Colaboradores" tem permissão TimeCard::Proposal#index e #create,
    // mas NÃO #adjust — daí o 403 "não autorizado" em /proposals/adjust.
    // Tenta a rota de create (permitida) e só cai pro /adjust como último recurso.
    const attempts = [
      ('/api/time_cards/proposals', 1),
      ('/api/time_cards/proposals', 2),
      ('/api/time_cards/proposals/adjust', 2),
    ];
    ApiException? last;
    for (final (path, type) in attempts) {
      try {
        await _post(path, bodyFor(type));
        return;
      } on ApiException catch (e) {
        last = e;
        // 403/404/405 = rota errada ou sem permissão → tenta a próxima.
        // Qualquer outro erro (ex.: 422 de validação) é real: propaga.
        if (e.status != 403 && e.status != 404 && e.status != 405) rethrow;
      }
    }
    throw last!;
  }
}
