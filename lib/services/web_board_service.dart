import 'dart:convert';
import 'dart:typed_data';

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

  /// 회고(성과)를 게시판에 올린다. 성공하면 글 id, 실패하면 예외.
  static Future<int> share({
    required RetroStats stats,
    required String title,
    required String body,
    Uint8List? cardPng,
  }) async {
    final token = await AccountService.instance.sessionToken();
    if (token == null) {
      throw StateError('로그인이 필요해요');
    }

    final r = stats.routine;
    final d = DateFormat('yyyy-MM-dd');
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/posts'))
      ..headers['Cookie'] = 'session=$token'
      ..fields['title'] = _clamp(title, 80)
      ..fields['routineType'] =
          r.type == RoutineType.accumulate ? 'stack' : 'goal'
      ..fields['routineName'] = _clamp(r.title, 60)
      ..fields['periodStart'] = d.format(r.startDate)
      ..fields['periodEnd'] = d.format(r.endDate)
      ..fields['certCount'] = '${stats.certifiedDays}'
      ..fields['achievedPercent'] = '${stats.percent}'
      ..fields['body'] = _clamp(body, 5000);

    if (cardPng != null) {
      req.files.add(http.MultipartFile.fromBytes(
        'images',
        cardPng,
        filename: 'retro_card.png',
        contentType: MediaType('image', 'png'),
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
