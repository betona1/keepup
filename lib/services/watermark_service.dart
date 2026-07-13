import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// 인증 사진에 날짜·시각을 자동으로 새겨 저장한다.
/// (규칙: "사진엔 필히 날짜가 표기되어야 함"을 앱이 자동 처리)
class WatermarkService {
  /// [sourcePath] 원본 사진에 워터마크를 찍어 앱 문서 폴더에 저장하고,
  /// 저장된 새 파일 경로를 반환한다.
  static Future<String> stamp(String sourcePath, DateTime when) async {
    final bytes = await File(sourcePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) {
      // 디코드 실패 시 원본 경로를 그대로 사용
      return sourcePath;
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

    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${dir.path}/certs');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final outPath =
        '${photosDir.path}/cert_${when.millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(image, quality: 88));
    return outPath;
  }
}
