/// 브라우저 주소 이동 창구 (웹 전용 동작).
library;

/// 웹앱은 log.keywordream.com/app/ 에서 서비스되므로 같은 오리진의 API를 상대경로로
/// 호출하면 세션 쿠키가 자동으로 붙는다. 로그인은 main 사이트로 페이지를 옮겨서 한다
/// (브라우저에서는 Custom Tab·구글 원탭을 쓸 수 없다).
export 'web_nav_io.dart' if (dart.library.js_interop) 'web_nav_web.dart';
