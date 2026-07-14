import 'dart:convert';
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
    if (remote && token != null) {
      try {
        await http.post(
          Uri.parse('$_base/api/auth/logout'),
          headers: {'Cookie': 'session=$token'},
        ).timeout(const Duration(seconds: 5));
      } catch (_) {/* 오프라인이어도 로컬은 정리 */}
    }
    _token = null;
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
