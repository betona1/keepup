import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'media_store.dart';

/// 인증 사진에 날짜·시각과 앱 로고를 자동으로 새겨 저장한다.
/// (규칙: "사진엔 필히 날짜가 표기되어야 함"을 앱이 자동 처리.
///  로고는 공유됐을 때 어느 앱에서 찍었는지 보여주는 브랜드 워터마크)
class WatermarkService {
  /// 로고(바브바브 얼굴) 디코드 캐시 — 인증마다 다시 읽지 않는다
  static img.Image? _logoCache;

  static Future<img.Image?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/character/vave_face.png');
      _logoCache = img.decodeImage(data.buffer.asUint8List());
    } catch (e) {
      debugPrint('로고 로드 실패(무시): $e'); // 로고 없이 날짜만 찍는다
    }
    return _logoCache;
  }

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

    draw(image, when, logo: await _loadLogo());

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

  /// 이미지에 워터마크를 그린다 — 좌하단 날짜·시각, 우하단 로고(얼굴+워드마크).
  /// 순수 그리기 로직이라 테스트에서 그대로 검증할 수 있다.
  @visibleForTesting
  static void draw(img.Image image, DateTime when, {img.Image? logo}) {
    final stamp = DateFormat('yyyy-MM-dd  HH:mm').format(when);
    final font = img.arial48;

    // 텍스트 위치: 좌하단 여백
    final textW = stamp.length * 26; // 대략적 폭
    const x = 24;
    final y = image.height - font.lineHeight - 28;
    final boxY1 = y - 10;
    final boxY2 = y + font.lineHeight + 6;

    // 가독성용 반투명 어두운 배경 박스
    img.fillRect(
      image,
      x1: x - 12,
      y1: boxY1,
      x2: x + textW,
      y2: boxY2,
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

    // ── 우하단 앱 로고: 바브바브 얼굴 + 'Log Challenge' ──
    // (image 패키지 내장 폰트는 한글이 없어 워드마크는 영문 표기)
    const brand = 'Log Challenge';
    final brandFont = img.arial24;
    final brandW = brand.length * 14; // 대략적 폭
    final boxH = boxY2 - boxY1;
    final faceH = boxH - 8; // 날짜 박스와 같은 높이의 필 안에 꽉 차게
    final hasLogo = logo != null;
    final contentW = (hasLogo ? faceH + 10 : 0) + brandW;

    // 사진이 좁아 날짜와 겹치면 로고는 생략 (날짜가 규칙상 우선)
    final pillX2 = image.width - 20;
    final pillX1 = pillX2 - contentW - 24;
    if (pillX1 < x + textW + 24) return;

    img.fillRect(
      image,
      x1: pillX1,
      y1: boxY1,
      x2: pillX2,
      y2: boxY2,
      color: img.ColorRgba8(0, 0, 0, 140),
    );

    var cx = pillX1 + 12;
    if (hasLogo) {
      final face = img.copyResize(logo, width: faceH, height: faceH);
      img.compositeImage(image, face,
          dstX: cx, dstY: boxY1 + (boxH - faceH) ~/ 2);
      cx += faceH + 10;
    }
    img.drawString(
      image,
      brand,
      font: brandFont,
      x: cx,
      y: boxY1 + (boxH - brandFont.lineHeight) ~/ 2,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  static String _fileName(DateTime when) =>
      'cert_${when.millisecondsSinceEpoch}.jpg';
}
