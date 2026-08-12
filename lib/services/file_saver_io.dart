import 'dart:typed_data';

/// 네이티브에서는 공유 시트로 파일을 내보내므로 브라우저 다운로드가 필요 없다.
Future<void> downloadBytes(
    String filename, Uint8List bytes, String mimeType) async {
  throw UnsupportedError('브라우저 다운로드는 웹에서만 사용합니다');
}
