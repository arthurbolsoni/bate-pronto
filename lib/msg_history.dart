import 'package:shared_preferences/shared_preferences.dart';

/// Histórico das últimas justificativas de ajuste de ponto, persistido em
/// SharedPreferences. Serve pra reusar mensagens repetidas com 1 toque em vez
/// de digitar tudo de novo.
class MsgHistory {
  static const _key = 'adjust_msg_history';
  static const _max = 8;

  /// Últimas mensagens, mais recente primeiro.
  static Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_key) ?? const [];
  }

  /// Guarda [msg] no topo. Dedupe (case-insensitive), mantém no máx [_max].
  static Future<List<String>> add(String msg) async {
    final m = msg.trim();
    if (m.isEmpty) return load();
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == m.toLowerCase());
    list.insert(0, m);
    if (list.length > _max) list.removeRange(_max, list.length);
    await p.setStringList(_key, list);
    return list;
  }

  static Future<List<String>> remove(String msg) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == msg.trim().toLowerCase());
    await p.setStringList(_key, list);
    return list;
  }
}
