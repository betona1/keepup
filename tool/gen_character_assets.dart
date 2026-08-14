// 바브바브(VAVEVAVE) 캐릭터 에셋 생성기
//   dart run tool/gen_character_assets.dart
//
// 원본: etc/바브바브01.png (1254x1254, 다크 네이비 배경에 합성된 일러스트)
// 만드는 것:
//   assets/character/vave_face.png  — 얼굴 원형 컷아웃(투명) · 도장/아이콘/로고용
//   assets/character/vave_full.png  — 전신(원본 배경 유지 + 가장자리 페이드) · 스플래시용
//   assets/icon/icon.png            — 앱 아이콘(브랜드 배경 + 얼굴)
//   assets/icon/icon_fg.png         — 안드로이드 적응형 아이콘 전경
//   assets/icon/icon_bg.png         — 안드로이드 적응형 아이콘 배경
//
// 크롭 좌표를 바꾸고 싶으면 아래 상수만 손보면 된다.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _source = 'etc/바브바브01.png';

// ── 얼굴 원형 크롭 (원본 픽셀 기준) ──
const faceCx = 573.0; // 얼굴 중심 x (귀 258~889의 가운데)
const faceCy = 505.0; // 얼굴 중심 y (머리 뿔털 끝 175가 원 안에 들어오도록)
const faceR = 330.0; // 반지름

// ── 전신 크롭 ──
const bodyLeft = 180;
const bodyTop = 120;
const bodyRight = 1010;
const bodyBottom = 1200;

void main() {
  final src = img.decodePng(File(_source).readAsBytesSync());
  if (src == null) {
    stderr.writeln('$_source 를 읽지 못했습니다');
    exitCode = 1;
    return;
  }

  Directory('assets/character').createSync(recursive: true);
  Directory('assets/icon').createSync(recursive: true);

  _reportPalette(src);
  final face = _faceCutout(src, 512);
  _write('assets/character/vave_face.png', face);
  _write('assets/character/vave_full.png', _fullBody(src, 900));
  _writeIcons(src);
  _writeNotificationAssets(face);
  _writeLevelFaces();

  stdout.writeln('완료 — 캐릭터 에셋 생성');
}

void _write(String path, img.Image im) {
  File(path).writeAsBytesSync(img.encodePng(im));
  stdout.writeln('· $path (${im.width}x${im.height})');
}

/// 얼굴을 원형으로 오려낸다 — 도장·아이콘에 쓸 "얼굴만" 남기는 게 목표.
///
/// · 눈·코·입이 있는 위쪽 절반은 건드리지 않는다.
/// · 아래쪽에서는 어두운 픽셀(후드·목)과 채도 높은 파란 픽셀(홀로그램 태블릿)을
///   지워서, 턱 아래로 자연스럽게 털만 남고 사라지게 만든다.
img.Image _faceCutout(img.Image src, int size) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  final scale = (faceR * 2) / size;
  final c = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - c, dy = y - c;
      final dist = math.sqrt(dx * dx + dy * dy) / c; // 0=중심, 1=원 가장자리
      if (dist > 1) continue; // 원 밖 → 투명

      final sx = (faceCx - faceR + x * scale).round();
      final sy = (faceCy - faceR + y * scale).round();
      if (sx < 0 || sy < 0 || sx >= src.width || sy >= src.height) continue;
      final p = src.getPixel(sx, sy);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final lum = (r + g + b) / 3;

      var alpha = 255.0;

      // ① 바깥쪽 링에 있는 어두운 픽셀 = 배경. 눈·코·입은 안쪽(dist<0.6)이라 안전하다.
      if (dist > 0.68 && lum < 60) {
        alpha *= ((lum - 26) / 34).clamp(0.0, 1.0);
      }
      // 머리 위쪽에는 이목구비가 없으므로 배경을 더 과감히 지운다 (뿔털 주변 정리).
      // 아래로 내려갈수록 강도를 서서히 줄여 가로 경계선이 생기지 않게 한다.
      if (y < size * 0.52 && dist > 0.50 && lum < 78) {
        final strength = (1 - (y / size - 0.34) / 0.18).clamp(0.0, 1.0);
        final erased = ((lum - 30) / 48).clamp(0.0, 1.0);
        alpha *= erased + (1 - erased) * (1 - strength);
      }

      // ② 오른쪽 아래 홀로그램 태블릿 제거 — 도장에 들어오면 산만하다.
      //    털은 크림색(빨강>파랑)이고 태블릿은 청백색(파랑≥빨강)이라 색으로 구분된다.
      if (sx > 645 && sy > 630 && b - r > 16) {
        alpha = 0;
      }

      // ③ 가장자리 페이드
      if (dist > 0.88) {
        alpha *= ((1 - dist) / 0.12).clamp(0.0, 1.0);
      }

      // ④ 원 아래쪽 끝(후드·목)은 서서히 사라지게 — 뚝 잘린 티가 나지 않도록
      final vy = y / size;
      if (vy > 0.80) {
        alpha *= (1 - (vy - 0.80) / 0.20).clamp(0.0, 1.0);
      }

      if (alpha <= 1) continue;
      out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(),
          alpha.round().clamp(0, 255));
    }
  }
  return out;
}

/// 전신 — 원본 배경(다크 네이비)을 그대로 살리고 가장자리만 서서히 녹인다.
/// 스플래시가 같은 다크 배경 위에 그려지므로 경계가 보이지 않는다.
img.Image _fullBody(img.Image src, int width) {
  final cropped = img.copyCrop(
    src,
    x: bodyLeft,
    y: bodyTop,
    width: bodyRight - bodyLeft,
    height: bodyBottom - bodyTop,
  );
  final scaled = img.copyResize(cropped, width: width);
  final out = img.Image(
      width: scaled.width, height: scaled.height, numChannels: 4);
  const fade = 0.26; // 가장자리에서 넓게 페이드 — 스플래시 배경과 경계가 보이지 않게
  for (var y = 0; y < scaled.height; y++) {
    for (var x = 0; x < scaled.width; x++) {
      final p = scaled.getPixel(x, y);
      final fx = math.min(x, scaled.width - 1 - x) / (scaled.width * fade);
      final fy = math.min(y, scaled.height - 1 - y) / (scaled.height * fade);
      final a = (math.min(fx, fy)).clamp(0.0, 1.0);
      out.setPixelRgba(
          x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), (255 * a).round());
    }
  }
  return out;
}

/// 앱 아이콘 — 브랜드 다크 네이비 배경 + 네온 링 + 얼굴
void _writeIcons(img.Image src) {
  const size = 1024;
  final face = _faceCutout(src, (size * 0.88).round());

  img.Image background() {
    final bg = img.Image(width: size, height: size, numChannels: 4);
    // 위(#131A2B) → 아래(#0B1020) 세로 그라데이션 + 중앙 네온 글로우
    for (var y = 0; y < size; y++) {
      final t = y / size;
      final r = (19 + (11 - 19) * t).round();
      final g = (26 + (16 - 26) * t).round();
      final b = (43 + (32 - 43) * t).round();
      for (var x = 0; x < size; x++) {
        final dx = (x - size / 2) / (size / 2);
        final dy = (y - size / 2) / (size / 2);
        final d = math.sqrt(dx * dx + dy * dy);
        final glow = (1 - d).clamp(0.0, 1.0) * 0.30; // 중앙이 살짝 밝게
        bg.setPixelRgba(
          x,
          y,
          (r + (79 - r) * glow).round(),
          (g + (169 - g) * glow).round(),
          (b + (255 - b) * glow).round(),
          255,
        );
      }
    }
    return bg;
  }

  // 아이콘: 배경 + 얼굴
  final icon = background();
  img.compositeImage(icon, face,
      dstX: ((size - face.width) / 2).round(),
      dstY: ((size - face.height) / 2).round() - (size * 0.02).round());
  _write('assets/icon/icon.png', icon);

  // 안드로이드 적응형 — 전경은 얼굴만(안전영역 고려해 조금 작게), 배경은 그라데이션
  final fg = img.Image(width: size, height: size, numChannels: 4);
  final small = img.copyResize(face, width: (size * 0.62).round());
  img.compositeImage(fg, small,
      dstX: ((size - small.width) / 2).round(),
      dstY: ((size - small.height) / 2).round());
  _write('assets/icon/icon_fg.png', fg);
  _write('assets/icon/icon_bg.png', background());
}

/// 레벨별 얼굴 — 도장 진화(2~5단계)용.
/// 2·3단계는 바브바브02(탐구)·03(마스터), 4단계는 초사이언 바브 4종,
/// 5단계는 코스믹 마스터 바브 4종에서 오려낸다.
/// 원본들이 인포그래픽이라 얼굴 주변에 글자·콜아웃이 있어, 얼굴 반경을
/// 보수적으로 잡고 어두운 배경만 지우는 일반 규칙을 쓴다.
/// 4·5단계는 변형 4장씩(vave_face4~4d, 5~5d) — 앱에서 날마다 얼굴이 바뀐다.
void _writeLevelFaces() {
  final configs = [
    ('etc/바브바브02.png', 645.0, 545.0, 300.0, 'assets/character/vave_face2.png'),
    ('etc/바브바브03.png', 665.0, 420.0, 295.0, 'assets/character/vave_face3.png'),
    // ── 4단계 초사이언 바브 (골드) ──
    ('etc/바브바브4단계1.png', 665.0, 460.0, 230.0, 'assets/character/vave_face4.png'),
    ('etc/바브바브4단계2.png', 640.0, 450.0, 225.0, 'assets/character/vave_face4b.png'),
    ('etc/바브바브4단계3.png', 668.0, 469.0, 220.0, 'assets/character/vave_face4c.png'),
    ('etc/바브바브4단계4.png', 660.0, 470.0, 220.0, 'assets/character/vave_face4d.png'),
    // ── 5단계 코스믹 마스터 바브 (우주) ──
    ('etc/바브바브5단계-03.png', 470.0, 660.0, 245.0, 'assets/character/vave_face5.png'),
    ('etc/바브바브5단계-01.png', 430.0, 640.0, 230.0, 'assets/character/vave_face5b.png'),
    ('etc/바브바브5단계-02.png', 455.0, 620.0, 230.0, 'assets/character/vave_face5c.png'),
    ('etc/바브바브5단계-04.png', 445.0, 650.0, 220.0, 'assets/character/vave_face5d.png'),
  ];
  for (final (srcPath, cx, cy, r, outPath) in configs) {
    final f = File(srcPath);
    if (!f.existsSync()) {
      stderr.writeln('$srcPath 없음 — 건너뜀');
      continue;
    }
    final src = img.decodePng(f.readAsBytesSync());
    if (src == null) continue;
    _write(outPath, _genericFaceCutout(src, 512, cx: cx, cy: cy, r: r));
  }
}

/// 일반 얼굴 컷아웃 — 어두운 배경 픽셀 제거 + 가장자리·하단 페이드만 적용.
img.Image _genericFaceCutout(img.Image src, int size,
    {required double cx, required double cy, required double r}) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  final scale = (r * 2) / size;
  final c = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x - c, dy = y - c;
      final dist = math.sqrt(dx * dx + dy * dy) / c;
      if (dist > 1) continue;

      final sx = (cx - r + x * scale).round();
      final sy = (cy - r + y * scale).round();
      if (sx < 0 || sy < 0 || sx >= src.width || sy >= src.height) continue;
      final p = src.getPixel(sx, sy);
      final lum = (p.r + p.g + p.b) / 3;

      var alpha = 255.0;
      // 바깥 링의 어두운 픽셀 = 배경 (이목구비는 안쪽이라 안전)
      if (dist > 0.62 && lum < 66) {
        alpha *= ((lum - 28) / 38).clamp(0.0, 1.0);
      }
      // 가장자리 페이드
      if (dist > 0.86) {
        alpha *= ((1 - dist) / 0.14).clamp(0.0, 1.0);
      }
      // 하단(목·몸통) 페이드
      final vy = y / size;
      if (vy > 0.78) {
        alpha *= (1 - (vy - 0.78) / 0.22).clamp(0.0, 1.0);
      }
      if (alpha <= 1) continue;
      out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(),
          alpha.round().clamp(0, 255));
    }
  }
  return out;
}

/// 알림용 안드로이드 리소스 — 마감 알람에 바브바브를 함께 띄운다.
///  · drawable-nodpi/vave_notify.png  : 알림 큰 아이콘(얼굴)
///  · drawable-nodpi/ic_stat_vave.png : 상태바 작은 아이콘(흰 실루엣, 알파만 사용됨)
void _writeNotificationAssets(img.Image face) {
  final dir = Directory('android/app/src/main/res/drawable-nodpi');
  dir.createSync(recursive: true);

  // 큰 아이콘 — 알림 오른쪽에 동그랗게 뜨므로 원본 얼굴 그대로 쓰면 된다
  final large = img.copyResize(face, width: 256, height: 256);
  File('${dir.path}/vave_notify.png').writeAsBytesSync(img.encodePng(large));
  stdout.writeln('· ${dir.path}/vave_notify.png (256px)');

  // 상태바 아이콘 — 안드로이드는 알파 채널만 쓰고 전부 흰색으로 칠한다.
  // 얼굴을 그대로 실루엣으로 만들면 '그냥 원'이 되어 알아볼 수 없으므로,
  // 브랜드 심볼인 '도장 링 + 체크'를 단순한 형태로 그린다.
  const s = 96;
  const cx = s / 2, cy = s / 2;
  const outer = 40.0, inner = 31.0; // 링 두께 9px
  final stat = img.Image(width: s, height: s, numChannels: 4);

  double ring(double x, double y) {
    final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
    if (d > outer + 0.7 || d < inner - 0.7) return 0;
    // 가장자리 0.7px을 부드럽게 (안티에일리어싱)
    final a = math.min(outer + 0.7 - d, d - (inner - 0.7));
    return a.clamp(0.0, 1.0);
  }

  /// 점(x,y)에서 선분 (x1,y1)-(x2,y2)까지의 거리
  double segDist(
      double x, double y, double x1, double y1, double x2, double y2) {
    final dx = x2 - x1, dy = y2 - y1;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((x - x1) * dx + (y - y1) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final px = x1 + t * dx, py = y1 + t * dy;
    return math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
  }

  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      final fx = x + 0.5, fy = y + 0.5;
      // 체크 마크 두 선분 (굵기 5px)
      final check = math.min(
        segDist(fx, fy, 33, 49, 43, 59),
        segDist(fx, fy, 43, 59, 64, 37),
      );
      final checkA = (5.0 - check).clamp(0.0, 1.0);
      final a = math.max(ring(fx, fy), checkA);
      if (a > 0) {
        stat.setPixelRgba(x, y, 255, 255, 255, (a * 255).round());
      }
    }
  }
  File('${dir.path}/ic_stat_vave.png').writeAsBytesSync(img.encodePng(stat));
  stdout.writeln('· ${dir.path}/ic_stat_vave.png (${s}px 도장 심볼)');
}

/// 원본에서 대표 색을 뽑아 콘솔에 보고 (테마 팔레트 잡을 때 참고)
void _reportPalette(img.Image src) {
  var neonR = 0.0, neonG = 0.0, neonB = 0.0, neonN = 0;
  var furR = 0.0, furG = 0.0, furB = 0.0, furN = 0;
  var bgR = 0.0, bgG = 0.0, bgB = 0.0, bgN = 0;

  for (var y = 0; y < src.height; y += 3) {
    for (var x = 0; x < src.width; x += 3) {
      final p = src.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final lum = (r + g + b) / 3;
      if (b > 150 && b - r > 60 && lum > 90) {
        neonR += r; neonG += g; neonB += b; neonN++;
      } else if (lum > 195) {
        furR += r; furG += g; furB += b; furN++;
      } else if (lum < 35) {
        bgR += r; bgG += g; bgB += b; bgN++;
      }
    }
  }

  String avg(double r, double g, double b, int n) => n == 0
      ? '(없음)'
      : '#${(r / n).round().toRadixString(16).padLeft(2, '0')}'
          '${(g / n).round().toRadixString(16).padLeft(2, '0')}'
          '${(b / n).round().toRadixString(16).padLeft(2, '0')}  (n=$n)';

  stdout.writeln('── 캐릭터 팔레트 ──');
  stdout.writeln('네온 블루 : ${avg(neonR, neonG, neonB, neonN)}');
  stdout.writeln('밝은 털   : ${avg(furR, furG, furB, furN)}');
  stdout.writeln('어두운 배경: ${avg(bgR, bgG, bgB, bgN)}');
}
