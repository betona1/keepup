import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/models/routine.dart';
import 'package:keepup/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Routine make(DateTime start) => Routine(
        id: 't1',
        title: '테스트',
        reason: '',
        type: RoutineType.accumulate,
        dutyCycle: DutyCycle.everyday,
        startDate: start,
        endDate: start.add(const Duration(days: 365)),
        createdAt: start,
      );

  group('stampLevelOn — 5단계 진화 타임라인', () {
    final start = DateTime(2026, 1, 1);
    final r = make(start);

    int levelAtDay(int d) => r.stampLevelOn(start.add(Duration(days: d)));

    test('첫 1주(0~6일차) = 1단계', () {
      expect(levelAtDay(0), 1);
      expect(levelAtDay(6), 1);
    });
    test('1주 뒤(7일차)부터 2단계 — 1→2는 1주', () {
      expect(levelAtDay(7), 2);
      expect(levelAtDay(20), 2);
    });
    test('3주 뒤(21일차)부터 3단계 — 2→3은 2주 더', () {
      expect(levelAtDay(21), 3);
      expect(levelAtDay(41), 3);
    });
    test('6주 뒤(42일차)부터 4단계 — 3→4는 3주 더', () {
      expect(levelAtDay(42), 4);
      expect(levelAtDay(69), 4);
    });
    test('10주 뒤(70일차)부터 5단계 — 4→5는 4주 더, 최종 진화', () {
      expect(levelAtDay(70), 5);
      expect(levelAtDay(365), 5);
    });
  });

  group('레벨별 에셋·스타일', () {
    test('얼굴 에셋 파일이 레벨·변형별로 전부 번들에 있다', () async {
      for (var level = 1; level <= 5; level++) {
        final variants = level >= 4 ? 4 : 1;
        for (var v = 0; v < variants; v++) {
          final path = AppTheme.faceAssetFor(level, variant: v);
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(1000),
              reason: '$path 가 비어 있음');
        }
      }
    });

    test('4·5단계 변형은 4장이 순환한다', () {
      final a = AppTheme.faceAssetFor(5, variant: 0);
      final b = AppTheme.faceAssetFor(5, variant: 1);
      expect(a, isNot(b));
      expect(AppTheme.faceAssetFor(5, variant: 4), a); // % 4 순환
    });

    test('링 색 — 4단계는 3색 플레임, 5단계는 3색 오로라', () {
      expect(AppTheme.stampRingColors(4).length, 3);
      expect(AppTheme.stampRingColors(5).length, 3);
      expect(AppTheme.stampRingColors(3).length, 2);
    });

    test('레벨 배지 라벨', () {
      expect(AppTheme.levelBadge(4), contains('4단계'));
      expect(AppTheme.levelBadge(5), contains('5단계'));
    });
  });
}
