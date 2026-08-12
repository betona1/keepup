// 바브바브 원본 이미지 조사용 임시 스크립트 (크기·배경색·주요 팔레트)
//   dart run tool/probe_character.dart
import 'dart:io';

import 'package:image/image.dart' as img;

String hex(img.Pixel p) =>
    '#${p.r.toInt().toRadixString(16).padLeft(2, '0')}'
    '${p.g.toInt().toRadixString(16).padLeft(2, '0')}'
    '${p.b.toInt().toRadixString(16).padLeft(2, '0')}';

void main() {
  final src = img.decodePng(File('etc/바브바브01.png').readAsBytesSync())!;
  stdout.writeln('크기: ${src.width} x ${src.height}');

  // 모서리·가장자리 = 배경
  for (final spot in [
    ['좌상', 10, 10],
    ['우상', src.width - 10, 10],
    ['좌하', 10, src.height - 10],
    ['우하', src.width - 10, src.height - 10],
    ['중앙상단', src.width ~/ 2, 8],
  ]) {
    final p = src.getPixel(spot[1] as int, spot[2] as int);
    stdout.writeln('배경 ${spot[0]}: ${hex(p)}');
  }

  // 세로 중앙선을 훑어 캐릭터가 시작/끝나는 y를 찾는다 (밝기 기준)
  int? top, bottom;
  for (var y = 0; y < src.height; y++) {
    var bright = 0;
    for (var x = 0; x < src.width; x += 4) {
      final p = src.getPixel(x, y);
      if (p.r + p.g + p.b > 330) bright++; // 평균 110 이상 = 캐릭터 밝은 부분
    }
    if (bright > 6) {
      top ??= y;
      bottom = y;
    }
  }
  stdout.writeln('밝은 영역 y: $top ~ $bottom');

  // 가로도 동일하게
  int? left, right;
  for (var x = 0; x < src.width; x++) {
    var bright = 0;
    for (var y = 0; y < src.height; y += 4) {
      final p = src.getPixel(x, y);
      if (p.r + p.g + p.b > 330) bright++;
    }
    if (bright > 6) {
      left ??= x;
      right = x;
    }
  }
  stdout.writeln('밝은 영역 x: $left ~ $right');

  // 눈 높이 근처 가로 스캔 — 얼굴 폭 추정용으로 몇 줄 샘플
  for (final y in [
    (src.height * 0.42).round(),
    (src.height * 0.46).round(),
    (src.height * 0.50).round(),
  ]) {
    int? l, r;
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (p.r + p.g + p.b > 420) {
        l ??= x;
        r = x;
      }
    }
    stdout.writeln('y=$y 밝은 x 범위: $l ~ $r');
  }
}
