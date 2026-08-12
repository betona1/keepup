import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 네이티브용 구현 — 앱 문서 폴더의 `certs/` 아래에 실제 파일로 보관한다.
/// (기존에 저장된 절대 경로들도 그대로 읽히도록 path는 항상 절대 경로)
class MediaStore {
  MediaStore._();

  /// 웹(브라우저 저장소)에서 동작 중인지 — 화면에서 안내 문구 분기에 쓴다.
  static const bool isWeb = false;

  static Directory? _dir;

  static Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/certs');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
    } catch (e) {
      debugPrint('미디어 폴더 준비 실패: $e');
    }
    return _dir;
  }

  /// 앱 시작 시 1회 호출 (웹 구현과 시그니처를 맞추기 위한 준비 단계)
  static Future<void> init() async {
    await _ensureDir();
  }

  /// [name] 이름으로 저장하고 이후 읽을 때 쓸 경로를 돌려준다.
  static Future<String> saveBytes(String name, Uint8List bytes) async {
    final dir = await _ensureDir();
    if (dir == null) throw StateError('저장 폴더를 열 수 없어요');
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  static Future<Uint8List?> readBytes(String path) async {
    if (path.isEmpty) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 파일이 실제로 남아 있는지 (목록/썸네일에서 즉시 판단해야 해서 동기)
  static bool existsSync(String path) {
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 회고 카드 캡처처럼 '그리기 전에 미리 디코드'가 필요한 곳에서 호출
  static Future<void> preload(Iterable<String> paths) async {}

  /// 지금 즉시 그릴 수 있는 이미지 소스 (없으면 null → 비동기 로딩으로 넘어감)
  static ImageProvider? providerFor(String path) =>
      existsSync(path) ? FileImage(File(path)) : null;
}
