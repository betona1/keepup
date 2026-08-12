import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 웹(PWA)용 구현 — 사진/백업 바이트를 브라우저 IndexedDB에 보관한다.
///
/// · 값은 base64 문자열로 저장한다. 브라우저·idb 구현마다 타입배열 변환이
///   미묘하게 달라서, 어디서든 안전한 문자열로 통일했다(용량 +33%는 감수).
/// · 파일 목록(키)은 SharedPreferences(localStorage)에 따로 둔다.
///   썸네일 목록에서 "사진이 남아 있나?"를 동기로 즉시 판단해야 하기 때문.
class MediaStore {
  MediaStore._();

  static const bool isWeb = true;

  static const _dbName = 'logchallenge_media';
  static const _storeName = 'media';
  static const _keysPrefKey = 'media_keys_v1';

  static Database? _db;
  static SharedPreferences? _prefs;
  static final Set<String> _keys = <String>{};
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _keys.addAll(_prefs?.getStringList(_keysPrefKey) ?? const []);
      _db = await idbFactoryBrowser.open(
        _dbName,
        version: 1,
        onUpgradeNeeded: (VersionChangeEvent e) {
          final db = e.database;
          if (!db.objectStoreNames.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        },
      );
    } catch (e) {
      debugPrint('브라우저 저장소 초기화 실패: $e');
    }
  }

  static Future<void> _rememberKey(String name) async {
    if (!_keys.add(name)) return;
    await _prefs?.setStringList(_keysPrefKey, _keys.toList());
  }

  static Future<void> _forgetKey(String name) async {
    if (!_keys.remove(name)) return;
    await _prefs?.setStringList(_keysPrefKey, _keys.toList());
  }

  static Future<String> saveBytes(String name, Uint8List bytes) async {
    final db = _db;
    if (db == null) throw StateError('브라우저 저장소를 열 수 없어요');
    final txn = db.transaction(_storeName, idbModeReadWrite);
    await txn.objectStore(_storeName).put(base64Encode(bytes), name);
    await txn.completed;
    _cache[name] = bytes;
    await _rememberKey(name);
    return name;
  }

  static Future<Uint8List?> readBytes(String path) async {
    if (path.isEmpty) return null;
    final cached = _cache[path];
    if (cached != null) return cached;
    final db = _db;
    if (db == null) return null;
    try {
      final txn = db.transaction(_storeName, idbModeReadOnly);
      final value = await txn.objectStore(_storeName).getObject(path);
      await txn.completed;
      if (value is! String) {
        // 저장소가 비워졌는데 목록만 남은 경우 — 목록을 정리해 둔다
        await _forgetKey(path);
        return null;
      }
      final bytes = base64Decode(value);
      _cache[path] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('사진 읽기 실패($path): $e');
      return null;
    }
  }

  static bool existsSync(String path) =>
      path.isNotEmpty && (_cache.containsKey(path) || _keys.contains(path));

  static Future<void> preload(Iterable<String> paths) async {
    for (final p in paths) {
      await readBytes(p);
    }
  }

  static ImageProvider? providerFor(String path) {
    final bytes = _cache[path];
    return bytes == null ? null : MemoryImage(bytes);
  }
}
