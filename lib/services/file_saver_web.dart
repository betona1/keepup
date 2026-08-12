import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 브라우저에서 파일 다운로드를 띄운다 (백업 ZIP·회고 카드 PNG 저장용).
Future<void> downloadBytes(
    String filename, Uint8List bytes, String mimeType) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
