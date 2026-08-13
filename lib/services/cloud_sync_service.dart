import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/routine.dart';
import 'account_service.dart';
import 'backup_service.dart';

/// 클라우드에 올려 둔 백업 정보
class CloudBackupInfo {
  final bool exists;
  final int size;
  final DateTime? updatedAt;
  const CloudBackupInfo({
    required this.exists,
    required this.size,
    this.updatedAt,
  });

  String get sizeLabel {
    if (size <= 0) return '-';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}

/// 기록을 웹 계정에 보관한다 — 기기를 바꾸거나 브라우저 데이터를 지워도 되살릴 수 있게.
///
/// 앱이 이미 만들고 있는 백업 ZIP(data.json + media/*)을 그대로 올리고 내린다.
/// 서버는 내용을 해석하지 않고 사용자당 최신 1개만 보관하므로, **마지막에 올린 것이 이긴다**.
/// 자동 동기화가 아니라 사용자가 '올리기/내리기'를 직접 누르는 방식이라 두 기기에서
/// 번갈아 쓰다 덮어쓰는 사고가 잘 나지 않는다.
class CloudSyncService {
  /// 서버가 받는 최대 크기 (routes/sync.ts의 MAX_BYTES와 같아야 한다)
  static const maxBytes = 60 * 1024 * 1024;

  /// 웹앱은 같은 오리진이라 상대경로면 세션 쿠키가 자동으로 붙는다.
  /// 네이티브는 저장한 세션 토큰을 Cookie 헤더로 넘긴다.
  static const _base = 'https://log.keywordream.com';

  static Future<Map<String, String>> _headers() async {
    if (kIsWeb) return const {};
    final token = await AccountService.instance.sessionToken();
    if (token == null) throw StateError('로그인이 필요해요');
    return {'Cookie': 'session=$token'};
  }

  static Uri _uri(String path) => Uri.parse(kIsWeb ? path : '$_base$path');

  static Never _fail(int status, Map<String, dynamic>? json) {
    final code = json?['error'];
    throw StateError(switch (code) {
      'too_large' => '기록이 너무 커서 올릴 수 없어요 (60MB 제한). '
          '사진이 많은 시즌은 파일 백업(ZIP 내보내기)을 써 주세요.',
      'unauthorized' => '세션이 만료됐어요. 다시 로그인해 주세요',
      'not_found' => '클라우드에 저장된 기록이 없어요',
      _ => '실패 (${code ?? status})',
    });
  }

  /// 클라우드 백업 정보 조회. 로그인 안 됐으면 null.
  static Future<CloudBackupInfo?> info() async {
    try {
      final res = await http
          .get(_uri('/api/sync/meta'), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 401) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (json['ok'] != true) return null;
      final d = json['data'] as Map<String, dynamic>;
      return CloudBackupInfo(
        exists: d['exists'] == true,
        size: (d['size'] as num?)?.toInt() ?? 0,
        updatedAt: d['updatedAt'] == null
            ? null
            : DateTime.tryParse(d['updatedAt'] as String)?.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 지금 기기의 기록을 클라우드에 올린다 (기존 백업을 덮어쓴다).
  /// 반환: 올린 크기(바이트)
  static Future<int> upload(
      List<Routine> routines, List<Certification> certs) async {
    final (zip, _) = await BackupService.buildZip(routines, certs);
    if (zip.lengthInBytes > maxBytes) {
      throw StateError('기록이 너무 커서 올릴 수 없어요 '
          '(${(zip.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB / 60MB 제한). '
          '사진이 많은 시즌은 파일 백업(ZIP 내보내기)을 써 주세요.');
    }

    final res = await http
        .put(
          _uri('/api/sync'),
          headers: {
            ...await _headers(),
            'Content-Type': 'application/zip',
          },
          body: zip,
        )
        .timeout(const Duration(minutes: 3));

    if (res.statusCode != 200) {
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      _fail(res.statusCode, json);
    }
    return zip.lengthInBytes;
  }

  /// 클라우드에 둔 기록을 내려받아 되살린다.
  /// ⚠️ 호출한 쪽에서 '지금 기기 기록을 덮어쓴다'는 확인을 먼저 받아야 한다.
  static Future<(List<Routine>, List<Certification>)> download() async {
    final res = await http
        .get(_uri('/api/sync'), headers: await _headers())
        .timeout(const Duration(minutes: 3));

    if (res.statusCode != 200) {
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      _fail(res.statusCode, json);
    }
    return BackupService.readZip(Uint8List.fromList(res.bodyBytes));
  }

  /// 클라우드에 둔 기록만 삭제 (기기 안 기록은 그대로)
  static Future<void> deleteRemote() async {
    final res = await http
        .delete(_uri('/api/sync'), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res.statusCode, null);
  }
}
