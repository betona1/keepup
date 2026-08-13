/// 네이티브에서는 쓰이지 않는다 — 앱은 Custom Tab/구글 원탭으로 로그인한다.
library;

/// 현재 페이지 주소 (네이티브에는 없음)
String currentUrl() => '';

/// 같은 탭에서 주소 이동 (네이티브에서는 아무 것도 하지 않음)
void navigateTo(String url) {}
