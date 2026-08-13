import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

import '../models/retro_stats.dart';
import '../models/routine.dart';
import 'account_service.dart';

/// 성과 게시판(log.keywordream.com/stories) 업로드.
///
/// 앱의 웹 계정 세션 토큰을 그대로 써서 — 게시판과 앱이 같은 KV 세션을
/// 공유하므로 — 브라우저 없이 앱 안에서 바로 글을 올린다.
class WebBoardService {
  static const base = 'https://log.keywordream.com';

  /// 게시된 글 주소
  static String postUrl(int id) => '$base/stories/$id';

  /// 성과를 게시판에 올린다 (회고 카드 이미지 또는 인증 사진 첨부).
  /// 성공하면 글 id, 실패하면 예외.
  static Future<int> share({
    required RetroStats stats,
    required String title,
    required String body,
    Uint8List? imageBytes,
    String imageMime = 'image/png',
    String imageName = 'image.png',
  }) async {
    // 브라우저에서는 저장된 토큰이 없고 Cookie 헤더도 넣을 수 없다.
    // 웹앱이 log.keywordream.com/app/ 에서 돌기 때문에 같은 오리진(/api/posts)으로 부르면
    // 세션 쿠키가 자동으로 붙는다. 네이티브는 기존처럼 토큰을 헤더로 넘긴다.
    String? token;
    if (!kIsWeb) {
      token = await AccountService.instance.sessionToken();
      if (token == null) {
        throw StateError('로그인이 필요해요');
      }
    }

    final r = stats.routine;
    final d = DateFormat('yyyy-MM-dd');
    final req = http.MultipartRequest(
        'POST', Uri.parse(kIsWeb ? '/api/posts' : '$base/api/posts'))
      ..fields['title'] = _clamp(title, 80)
      ..fields['routineType'] =
          r.type == RoutineType.accumulate ? 'stack' : 'goal'
      ..fields['routineName'] = _clamp(r.title, 60)
      ..fields['periodStart'] = d.format(r.startDate)
      ..fields['periodEnd'] = d.format(r.endDate)
      ..fields['certCount'] = '${stats.certifiedDays}'
      ..fields['achievedPercent'] = '${stats.percent}'
      ..fields['body'] = _clamp(body, 5000);
    if (!kIsWeb) req.headers['Cookie'] = 'session=$token';

    if (imageBytes != null) {
      final parts = imageMime.split('/');
      req.files.add(http.MultipartFile.fromBytes(
        'images',
        imageBytes,
        filename: imageName,
        contentType: MediaType(parts.first, parts.last),
      ));
    }

    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 30)));
    if (res.statusCode == 401) {
      throw StateError('세션이 만료됐어요. 다시 로그인해 주세요');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200 || json?['ok'] != true) {
      throw StateError('업로드 실패 (${json?['error'] ?? res.statusCode})');
    }
    return (json['data']['id'] as num).toInt();
  }

  static String _clamp(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }
}
