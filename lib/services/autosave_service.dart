import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/routine.dart';

/// 자동 스냅샷 — 데이터가 바뀔 때마다 앱 문서 폴더에 조용히 저장한다.
/// SharedPreferences가 비었는데(=데이터 유실) 스냅샷이 있으면 자동 복구한다.
///
/// 안드로이드 '자동 백업'(구글 드라이브)이 앱 삭제·폰 교체를 커버하고,
/// 이 스냅샷은 데이터 손상·초기화 같은 로컬 사고를 커버한다(2중 안전망).
class AutosaveService {
  static final AutosaveService instance = AutosaveService._();
  AutosaveService._();

  File? _file;

  Future<File> _snapshotFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/autosave.json');
    return _file!;
  }

  /// 현재 데이터를 스냅샷으로 저장 (변경 시마다 호출)
  Future<void> save(List<Routine> routines, List<Certification> certs) async {
    try {
      final f = await _snapshotFile();
      final data = {
        'savedAt': DateTime.now().toIso8601String(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'certs': certs.map((c) => c.toJson()).toList(),
      };
      // 원자적 저장: 임시 파일에 쓰고 교체 (쓰기 중 크래시로 파일 손상 방지)
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('자동 스냅샷 저장 실패(무시): $e');
    }
  }

  /// 스냅샷에서 복구. 파일이 없거나 손상됐으면 null.
  Future<(List<Routine>, List<Certification>)?> restore() async {
    try {
      final f = await _snapshotFile();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final routines = (data['routines'] as List)
          .map((e) => Routine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final certs = (data['certs'] as List)
          .map((e) =>
              Certification.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (routines.isEmpty && certs.isEmpty) return null;
      return (routines, certs);
    } catch (e) {
      debugPrint('자동 스냅샷 복구 실패: $e');
      return null;
    }
  }

  Future<DateTime?> lastSavedAt() async {
    try {
      final f = await _snapshotFile();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return DateTime.tryParse(data['savedAt'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }
}
