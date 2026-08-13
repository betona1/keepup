import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── 기기 간 '가져오기 요청' ──────────────────────────────────────
  // 이 기기에서 요청을 남기면, 기록이 있는 다른 기기의 앱이 열릴 때
  // 승인 안내가 뜨고 [보내기]로 올려 준다. 그러면 이쪽이 자동으로 내려받는다.

  static const _clientIdKey = 'sync_client_id_v1';

  /// 이 설치(기기/브라우저)의 무작위 식별자 — 내가 보낸 요청에 내가 승인 창을
  /// 띄우지 않기 위한 구분용. 개인정보가 아니다.
  static Future<String> clientId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_clientIdKey);
    if (id == null) {
      final rnd = Random();
      id = List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_clientIdKey, id);
    }
    return id;
  }

  /// 다른 기기에 '기록 보내달라'는 요청을 남긴다 (15분 뒤 자동 소멸)
  static Future<void> requestPull() async {
    final res = await http
        .post(
          _uri('/api/sync/request'),
          headers: {
            ...await _headers(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'clientId': await clientId()}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) _fail(res.statusCode, null);
  }

  /// 대기 중인 가져오기 요청. 없거나 미로그인이면 null.
  /// [ignoreMine]이 true면 이 기기가 보낸 요청은 없는 것으로 친다 (승인 창용).
  static Future<PullRequestInfo?> pendingPull({bool ignoreMine = true}) async {
    try {
      final res = await http
          .get(_uri('/api/sync/request'), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final d = json['data'] as Map<String, dynamic>?;
      if (d == null || d['pending'] != true) return null;
      final info = PullRequestInfo(
        clientId: d['clientId'] as String? ?? '',
        requestedAt:
            DateTime.tryParse(d['requestedAt'] as String? ?? '')?.toLocal(),
      );
      if (ignoreMine && info.clientId == await clientId()) return null;
      return info;
    } catch (_) {
      return null; // 오프라인 등 — 요청 확인은 조용히 건너뛴다
    }
  }

  /// 요청 지우기 (취소·거절·완료 후 정리). 실패해도 무시 — TTL로 소멸한다.
  static Future<void> clearPull() async {
    try {
      await http
          .delete(_uri('/api/sync/request'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
    } catch (_) {/* 무시 */}
  }
}

/// 대기 중인 '가져오기 요청' 정보
class PullRequestInfo {
  final String clientId;
  final DateTime? requestedAt;
  const PullRequestInfo({required this.clientId, this.requestedAt});
}
