import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Everything kept on the device: who the user is, recent rooms, raw values
/// for other services.
class Prefs {
  Prefs._(this._sp);

  final SharedPreferences _sp;

  static Future<Prefs> load() async {
    final sp = await SharedPreferences.getInstance();
    final p = Prefs._(sp);
    if (sp.getString(_kUserId) == null) {
      await sp.setString(_kUserId, newId());
    }
    return p;
  }

  static const _kUserId = 'user_id';
  static const _kUserName = 'user_name';
  static const _kRecent = 'recent_rooms';

  String get userId => _sp.getString(_kUserId)!;
  String? get userName => _sp.getString(_kUserName);

  UserProfile get profile => UserProfile(id: userId, name: userName ?? 'Гость');

  Future<void> setUserName(String name) => _sp.setString(_kUserName, name);

  List<Room> get recentRooms {
    final raw = _sp.getStringList(_kRecent) ?? const [];
    final out = <Room>[];
    for (final s in raw) {
      try {
        out.add(Room.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> rememberRoom(Room room) async {
    final list = recentRooms.where((r) => r.code != room.code).toList()
      ..insert(0, room);
    await _sp.setStringList(
      _kRecent,
      list.take(12).map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  Future<void> forgetRoom(String code) async {
    final list = recentRooms.where((r) => r.code != code);
    await _sp.setStringList(
      _kRecent,
      list.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  String? getString(String key) => _sp.getString(key);
  Future<void> setString(String key, String value) => _sp.setString(key, value);
  Future<void> remove(String key) => _sp.remove(key);

  /// Picks up writes made by another tab (web keeps prefs in localStorage).
  Future<void> reload() => _sp.reload();
}
