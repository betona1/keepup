import 'package:web/web.dart' as web;

/// 현재 페이지 주소 — 로그인 후 돌아올 위치로 쓴다.
String currentUrl() => web.window.location.href;

/// 같은 탭에서 주소 이동 (로그인 페이지로 보낼 때)
void navigateTo(String url) {
  web.window.location.assign(url);
}
