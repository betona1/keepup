import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 습관 명언 한 줄
class Quote {
  final String text;
  final String author;
  const Quote({required this.text, required this.author});

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        text: (j['text'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
      );
}

/// 오늘의 명언 — 내장 JSON(오프라인 기본) + 웹 관리자 등록분(원격) 병합.
/// 원격은 keepup.keywordream.com/api/quotes 에서 하루 한 번 갱신, 실패해도 조용히 무시.
class QuoteService {
  static final QuoteService instance = QuoteService._();
  QuoteService._();

  static const _remoteUrl = 'https://keepup.keywordream.com/api/quotes';
  static const _prefsKey = 'remote_quotes_v1';
  static const _prefsFetchedAt = 'remote_quotes_fetched_at';

  List<Quote>? _merged;

  Future<List<Quote>> _load() async {
    if (_merged != null) return _merged!;

    final bundled = await rootBundle.loadString('assets/quotes.json');
    final quotes = (jsonDecode(bundled) as List)
        .map((e) => Quote.fromJson(e as Map<String, dynamic>))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final cachedRemote = prefs.getString(_prefsKey);
    if (cachedRemote != null) {
      try {
        final remote = (jsonDecode(cachedRemote) as List)
            .map((e) => Quote.fromJson(e as Map<String, dynamic>))
            .toList();
        final seen = quotes.map((q) => q.text).toSet();
        quotes.addAll(remote.where((q) => !seen.contains(q.text)));
      } catch (_) {/* 캐시 손상 시 내장분만 사용 */}
    }

    _merged = quotes;
    _refreshRemoteIfStale(prefs); // 백그라운드 갱신 (다음 실행부터 반영)
    return quotes;
  }

  Future<void> _refreshRemoteIfStale(SharedPreferences prefs) async {
    final last = prefs.getInt(_prefsFetchedAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 12).inMilliseconds) return;
    try {
      final res = await http
          .get(Uri.parse(_remoteUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['ok'] == true && body['data']?['quotes'] is List) {
          await prefs.setString(_prefsKey, jsonEncode(body['data']['quotes']));
          await prefs.setInt(_prefsFetchedAt, now);
        }
      }
    } catch (_) {/* 오프라인이면 조용히 넘어감 */}
  }

  /// 날짜 기준으로 매일 하나씩 순환
  Future<Quote> today() async {
    final list = await _load();
    final days = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
    return list[days % list.length];
  }
}
