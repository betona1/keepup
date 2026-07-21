import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// keywordream.com 웹 계정 (선택 로그인 — 프로필 표시 + 향후 게시판 연동)
class WebAccount {
  final int id;
  final String name;
  final String? avatarUrl;
  final String role;
  const WebAccount({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.role,
  });
}

/// 웹 세션 토큰 관리 — 앱은 로그인 없이도 완전 동작하며, 이 연동은 순수 선택사항.
class AccountService {
  static final AccountService instance = AccountService._();
  AccountService._();

  static const _base = 'https://keywordream.com';
  static const _prefsKey = 'web_session_token_v1';

  String? _token;
  WebAccount? _cached;

  Future<String?> _loadToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefsKey);
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, token);
  }

  /// 웹 계정 로그인 — 크롬 Custom Tab에서 keywordream 간편로그인을 진행한다.
  /// (WebView가 아니라 크롬이라 구글 OAuth가 정상 작동하고, 계정 전환/로그아웃도 깔끔)
  /// 로그인 완료 시 서버가 `logchallenge://auth?token=...` 로 리다이렉트 → 토큰을 저장.
  /// 성공 true / 취소·실패 false.
  Future<bool> login() async {
    final start = '$_base/api/auth/appredirect';
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: start,
        callbackUrlScheme: 'logchallenge',
        options: const FlutterWebAuth2Options(
          // 매번 서버 세션을 새로 확인하도록 (계정 전환 가능)
          preferEphemeral: false,
        ),
      );
      final token = Uri.parse(result).queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        await saveToken(token);
        return true;
      }
    } catch (_) {
      // 사용자가 취소했거나 실패 — 조용히 무시
    }
    return false;
  }

  /// 현재 로그인된 웹 계정. 미로그인/만료면 null.
  Future<WebAccount?> me({bool refresh = false}) async {
    if (!refresh && _cached != null) return _cached;
    final token = await _loadToken();
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$_base/api/auth/me'),
        headers: {'Cookie': 'session=$token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return _cached;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final user = body?['data']?['user'];
      if (user == null) {
        await logout(remote: false); // 세션 만료 → 토큰 정리
        return null;
      }
      _cached = WebAccount(
        id: (user['id'] as num).toInt(),
        name: user['name'] as String? ?? '회원',
        avatarUrl: user['avatarUrl'] as String?,
        role: user['role'] as String? ?? 'member',
      );
      return _cached;
    } catch (_) {
      return _cached; // 오프라인이면 캐시 유지
    }
  }

  Future<void> logout({bool remote = true}) async {
    final token = await _loadToken();
    // 1) 로컬을 먼저 즉시 정리 — 네트워크가 느리거나 실패해도 앱은 곧바로 로그아웃 상태가 된다
    _token = null;
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    // 2) 서버 세션 무효화는 백그라운드로 (결과를 기다리지 않음)
    if (remote && token != null) {
      http
          .post(
            Uri.parse('$_base/api/auth/logout'),
            headers: {'Cookie': 'session=$token'},
          )
          .timeout(const Duration(seconds: 5))
          .catchError((_) => http.Response('', 499)); // 실패 무시
    }
  }
}
