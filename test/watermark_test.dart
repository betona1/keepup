import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:keepup/services/watermark_service.dart';

/// 워터마크 그리기 — 좌하단 날짜 + 우하단 로고 필.
/// 결과 PNG를 시스템 임시 폴더에 남겨 눈으로도 확인할 수 있다.
void main() {
  final bg = img.ColorRgb8(60, 120, 60);

  img.Image makeBase({int w = 1440, int h = 1080}) {
    final base = img.Image(width: w, height: h);
    img.fill(base, color: bg);
    return base;
  }

  img.Image makeLogo() {
    final logo = img.Image(width: 200, height: 200, numChannels: 4);
    img.fillCircle(logo,
        x: 100, y: 100, radius: 100, color: img.ColorRgb8(240, 240, 255));
    return logo;
  }

  /// [x1..x2] 가로 구간의 하단 띠에서 배경과 다른 픽셀 수
  int changedIn(img.Image im, int x1, int x2) {
    var n = 0;
    for (var yy = im.height - 110; yy < im.height - 10; yy++) {
      for (var xx = x1; xx < x2; xx++) {
        final p = im.getPixel(xx, yy);
        if (p.r != bg.r || p.g != bg.g || p.b != bg.b) n++;
      }
    }
    return n;
  }

  test('날짜 박스(좌하단)와 로고 필(우하단)이 함께 찍힌다', () {
    final im = makeBase();
    WatermarkService.draw(im, DateTime(2026, 8, 15, 9, 30), logo: makeLogo());

    expect(changedIn(im, 0, 500), greaterThan(1000)); // 날짜 박스+텍스트
    expect(changedIn(im, im.width - 300, im.width), greaterThan(1000)); // 로고 필

    final out =
        File('${Directory.systemTemp.path}/keepup_watermark_test.png');
    out.writeAsBytesSync(img.encodePng(im));
    // 눈 확인용: 파일 경로는 테스트 러너 로그에 남는다
    // ignore: avoid_print
    print('워터마크 미리보기: ${out.path}');
  });

  test('로고가 없으면 날짜만 찍히고 예외가 없다', () {
    final im = makeBase();
    WatermarkService.draw(im, DateTime(2026, 8, 15, 9, 30));
    expect(changedIn(im, 0, 500), greaterThan(1000));
  });

  test('좁은 사진은 날짜와 겹치는 로고를 생략한다', () {
    final im = makeBase(w: 560, h: 700);
    WatermarkService.draw(im, DateTime(2026, 8, 15, 9, 30), logo: makeLogo());
    expect(changedIn(im, 0, 500), greaterThan(1000)); // 날짜는 있고
    expect(changedIn(im, im.width - 40, im.width), 0); // 우측 끝은 그대로
  });
}
