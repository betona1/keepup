import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

/// 웹(PWA) 전용 — 앱을 열 때 클라우드에 더 새로운 백업(폰이 자동으로 올린 것)이
/// 있는지 알아채는 도우미. 폰의 자동 올리기(AutoUploadService)와 짝을 이룬다.
///
/// '이 브라우저가 마지막으로 클라우드와 같아진 시점'(백업의 updatedAt)을 기억해
/// 두고, 클라우드의 updatedAt이 그보다 새로우면 가져오기를 제안한다.
/// 한 번 미룬 백업 버전은 다시 묻지 않는다 — 새 백업이 올라오면 다시 물어본다.
class WebAutoSync {
  static const _syncedKey = 'web_synced_cloud_at_v1';
  static const _declinedKey = 'web_declined_cloud_at_v1';

  /// 클라우드와 같아진 순간(내려받기/올리기 성공) 기록.
  /// [cloudUpdatedAt]은 그 시점 백업의 updatedAt.
  static Future<void> recordSynced(DateTime? cloudUpdatedAt) async {
    if (!kIsWeb || cloudUpdatedAt == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncedKey, cloudUpdatedAt.toIso8601String());
      await prefs.remove(_declinedKey);
    } catch (_) {}
  }

  /// '나중에'를 눌렀다 — 이 백업 버전은 다시 묻지 않는다.
  static Future<void> decline(DateTime cloudUpdatedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_declinedKey, cloudUpdatedAt.toIso8601String());
    } catch (_) {}
  }

  /// 이 브라우저가 아직 반영하지 않은 새 클라우드 백업.
  /// 없거나(미로그인·백업 없음·이미 최신·이미 미룸) 웹이 아니면 null.
  static Future<CloudBackupInfo?> newerBackup() async {
    if (!kIsWeb) return null;
    final info = await CloudSyncService.info(); // 미로그인이면 null
    final at = info?.updatedAt;
    if (info == null || !info.exists || at == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final synced =
          DateTime.tryParse(prefs.getString(_syncedKey) ?? '');
      final declined =
          DateTime.tryParse(prefs.getString(_declinedKey) ?? '');
      if (synced != null && !at.isAfter(synced)) return null;
      if (declined != null && at.isAtSameMomentAs(declined)) return null;
    } catch (_) {
      return null;
    }
    return info;
  }
}
