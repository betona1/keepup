@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keepup/services/media_store.dart';
import 'package:keepup/services/watermark_service.dart';

/// 웹(PWA) 전용 경로 검증 — 실제 브라우저에서 돌린다.
///   flutter test --platform chrome test/web_media_store_test.dart
///
/// 사진이 브라우저 저장소(IndexedDB)에 실제로 들어가고 다시 나오는지,
/// 워터마크가 파일 경로 없이(바이트만으로) 찍히는지를 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MediaStore.init();
  });

  test('웹 구현이 선택된다', () {
    expect(MediaStore.isWeb, isTrue);
  });

  test('브라우저 저장소에 저장하고 그대로 다시 읽는다', () async {
    final bytes = Uint8List.fromList(List.generate(512, (i) => i % 256));
    final path = await MediaStore.saveBytes('roundtrip.bin', bytes);

    expect(path, 'roundtrip.bin');
    expect(MediaStore.existsSync(path), isTrue);
    expect(await MediaStore.readBytes(path), bytes);
  });

  test('없는 파일은 없다고 답한다', () async {
    expect(MediaStore.existsSync('없는파일.jpg'), isFalse);
    expect(await MediaStore.readBytes('없는파일.jpg'), isNull);
  });

  test('워터마크 — 바이트만으로 찍고 저장하고 다시 읽어 디코드된다', () async {
    // 원본 사진 대역: 단색 800x600 JPEG
    final source = img.Image(width: 800, height: 600);
    img.fill(source, color: img.ColorRgb8(180, 200, 240));
    final sourceJpg = Uint8List.fromList(img.encodeJpg(source));

    final when = DateTime(2026, 8, 6, 21, 30);
    final path = await WatermarkService.stamp(sourceJpg, when);

    expect(path, 'cert_${when.millisecondsSinceEpoch}.jpg');
    expect(MediaStore.existsSync(path), isTrue);

    final saved = await MediaStore.readBytes(path);
    expect(saved, isNotNull);
    final decoded = img.decodeJpg(saved!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 800); // 1440 이하라 축소 없음
    expect(decoded.height, 600);

    // 좌하단 워터마크 박스가 실제로 그려졌는지 (원본 단색과 달라야 한다)
    final pixel = decoded.getPixel(30, 600 - 40);
    expect(pixel.r < 120 && pixel.g < 140 && pixel.b < 180, isTrue,
        reason: '좌하단에 반투명 어두운 날짜 박스가 그려져야 한다');
  });

  test('저장한 사진은 즉시 그릴 수 있는 이미지가 된다', () async {
    final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
    final path = await MediaStore.saveBytes('provider.png', bytes);
    expect(MediaStore.providerFor(path), isNotNull);
  });
}
