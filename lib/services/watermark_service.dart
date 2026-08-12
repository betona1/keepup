import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'media_store.dart';

/// 인증 사진에 날짜·시각을 자동으로 새겨 저장한다.
/// (규칙: "사진엔 필히 날짜가 표기되어야 함"을 앱이 자동 처리)
class WatermarkService {
  /// 원본 사진 [bytes]에 워터마크를 찍어 저장하고, 이후 읽을 때 쓸 경로를 반환한다.
  /// (네이티브는 앱 문서 폴더 파일 경로, 웹은 브라우저 저장소 키)
  static Future<String> stamp(Uint8List bytes, DateTime when) async {
    var image = img.decodeImage(bytes);
    if (image == null) {
      // 디코드 실패 — 원본 그대로라도 남긴다
      return MediaStore.saveBytes(_fileName(when), bytes);
    }

    // 너무 큰 사진은 가로 1440px로 축소 (메모리/용량 절약)
    if (image.width > 1440) {
      image = img.copyResize(image, width: 1440);
    }

    final stamp = DateFormat('yyyy-MM-dd  HH:mm').format(when);
    final font = img.arial48;

    // 텍스트 위치: 좌하단 여백
    final textW = stamp.length * 26; // 대략적 폭
    const x = 24;
    final y = image.height - font.lineHeight - 28;

    // 가독성용 반투명 어두운 배경 박스
    img.fillRect(
      image,
      x1: x - 12,
      y1: y - 10,
      x2: x + textW,
      y2: y + font.lineHeight + 6,
      color: img.ColorRgba8(0, 0, 0, 140),
    );

    // 흰색 텍스트
    img.drawString(
      image,
      stamp,
      font: font,
      x: x,
      y: y,
      color: img.ColorRgb8(255, 255, 255),
    );

    final jpg = img.encodeJpg(image, quality: 88);
    final path = await MediaStore.saveBytes(_fileName(when), jpg);

    // 갤러리 'KeepUp' 앨범에도 저장 — 앱을 지워도 워터마크 원본이 폰에 영구 보존됨
    // (웹은 갤러리가 없으므로 건너뛴다)
    if (!MediaStore.isWeb) {
      try {
        await Gal.putImage(path, album: 'KeepUp');
      } catch (e) {
        debugPrint('갤러리 저장 실패(무시): $e'); // 권한 거부 등은 무시, 앱 내 저장은 유지
      }
    }
    return path;
  }

  static String _fileName(DateTime when) =>
      'cert_${when.millisecondsSinceEpoch}.jpg';
}
