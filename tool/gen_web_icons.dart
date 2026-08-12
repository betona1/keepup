// PWA 아이콘 생성기 — assets/icon/icon.png 하나로 웹에 필요한 크기를 모두 만든다.
//   실행: dart run tool/gen_web_icons.dart
//
// 앱 아이콘을 바꾸면 이 스크립트를 다시 돌리면 된다.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final srcFile = File('assets/icon/icon.png');
  if (!srcFile.existsSync()) {
    stderr.writeln('assets/icon/icon.png 를 찾을 수 없습니다');
    exitCode = 1;
    return;
  }
  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('아이콘 PNG 디코드 실패');
    exitCode = 1;
    return;
  }

  final iconsDir = Directory('web/icons');
  if (!iconsDir.existsSync()) iconsDir.createSync(recursive: true);

  void write(String path, int size, {double inset = 0}) {
    // 원본 아이콘(바브바브 얼굴 + 딥네이비 배경)을 그대로 줄인다.
    // maskable 아이콘만 안전영역(80%) 안으로 밀어 넣어 모서리가 잘려도 얼굴이 남게 한다.
    final inner = (size * (1 - inset * 2)).round();
    final resized = img.copyResize(src, width: inner, height: inner);
    if (inset == 0) {
      File(path).writeAsBytesSync(img.encodePng(resized));
      stdout.writeln('· $path (${size}px)');
      return;
    }
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(11, 15, 26, 255)); // 캐릭터 배경 네이비
    final offset = ((size - inner) / 2).round();
    img.compositeImage(canvas, resized, dstX: offset, dstY: offset);
    File(path).writeAsBytesSync(img.encodePng(canvas));
    stdout.writeln('· $path (${size}px)');
  }

  write('web/icons/Icon-192.png', 192);
  write('web/icons/Icon-512.png', 512);
  write('web/icons/Icon-maskable-192.png', 192, inset: 0.1);
  write('web/icons/Icon-maskable-512.png', 512, inset: 0.1);
  write('web/icons/apple-touch-icon.png', 180);
  write('web/favicon.png', 32);
  stdout.writeln('완료 — 웹 아이콘 생성');
}
