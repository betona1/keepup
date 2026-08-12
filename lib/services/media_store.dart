/// 인증 사진·백업 같은 바이너리 파일 저장소 (플랫폼 공통 창구).
library;
///
/// - 네이티브(안드로이드/iOS): 앱 문서 폴더의 실제 파일. `path`는 절대 경로.
/// - 웹(PWA): 브라우저 IndexedDB. `path`는 파일명 그대로가 키가 된다.
///
/// 화면 코드가 `dart:io`의 File을 직접 쓰지 않게 해서 웹에서도 같은 흐름이 돈다.
export 'media_store_io.dart'
    if (dart.library.js_interop) 'media_store_web.dart';
