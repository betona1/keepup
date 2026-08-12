/// 만들어진 파일(백업 ZIP, 회고 카드 PNG)을 사용자에게 건네는 방법.
library;
/// 네이티브는 공유 시트를 쓰므로 이 창구는 웹에서만 실제 동작한다.
export 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';
