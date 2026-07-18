import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/routine.dart';
import '../models/notif_settings.dart';

/// 로컬 저장소 (SharedPreferences + JSON).
/// 서버 없이 폰 안에서만 데이터를 보관한다.
class StorageService {
  static const _kRoutines = 'routines_v1';
  static const _kCerts = 'certs_v1';
  static const _kNotif = 'notif_settings_v1';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  List<Routine> loadRoutines() {
    final raw = _prefs.getString(_kRoutines);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Routine.fromJson).toList();
  }

  Future<void> saveRoutines(List<Routine> routines) async {
    final raw = jsonEncode(routines.map((r) => r.toJson()).toList());
    await _prefs.setString(_kRoutines, raw);
  }

  List<Certification> loadCerts() {
    final raw = _prefs.getString(_kCerts);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Certification.fromJson).toList();
  }

  Future<void> saveCerts(List<Certification> certs) async {
    final raw = jsonEncode(certs.map((c) => c.toJson()).toList());
    await _prefs.setString(_kCerts, raw);
  }

  NotifSettings loadNotifSettings() {
    final raw = _prefs.getString(_kNotif);
    if (raw == null || raw.isEmpty) return NotifSettings.defaults;
    return NotifSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveNotifSettings(NotifSettings s) async {
    await _prefs.setString(_kNotif, jsonEncode(s.toJson()));
  }
}
