import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/models/routine.dart';

void main() {
  Routine make() => Routine(
        id: 'r1',
        title: '달리기 10분',
        reason: '체력',
        type: RoutineType.accumulate,
        dutyCycle: DutyCycle.everyday,
        verifyMethod: VerifyMethod.photo,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 8, 1),
      );

  group('루틴 변경 이력 (RoutineChange)', () {
    test('이력 직렬화 라운드트립 — 언제·무엇→무엇·사유가 보존된다', () {
      final change = RoutineChange(
        at: DateTime(2026, 8, 14, 18, 30),
        beforeTitle: '달리기 10분',
        afterTitle: '스트레칭 10분',
        beforeMethod: VerifyMethod.photo,
        afterMethod: VerifyMethod.timer,
        note: '허리 부상으로 잠시 가볍게',
      );
      final restored = RoutineChange.fromJson(
          jsonDecode(jsonEncode(change.toJson())) as Map<String, dynamic>);
      expect(restored.at, DateTime(2026, 8, 14, 18, 30));
      expect(restored.beforeTitle, '달리기 10분');
      expect(restored.afterTitle, '스트레칭 10분');
      expect(restored.beforeMethod, VerifyMethod.photo);
      expect(restored.afterMethod, VerifyMethod.timer);
      expect(restored.note, '허리 부상으로 잠시 가볍게');
    });

    test('Routine 직렬화에 changeLog가 포함되고 복원된다', () {
      final r = Routine(
        id: 'r1',
        title: '스트레칭 10분',
        reason: '체력',
        type: RoutineType.accumulate,
        dutyCycle: DutyCycle.everyday,
        createdAt: DateTime(2026, 8, 1),
        changeUsedCount: 1,
        changeLog: [
          RoutineChange(
            at: DateTime(2026, 8, 14, 18, 30),
            beforeTitle: '달리기 10분',
            afterTitle: '스트레칭 10분',
            beforeMethod: VerifyMethod.photo,
            afterMethod: VerifyMethod.timer,
          ),
        ],
      );
      final restored = Routine.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(restored.changeUsedCount, 1);
      expect(restored.changeLog.length, 1);
      expect(restored.changeLog.first.beforeTitle, '달리기 10분');
      expect(restored.changeLog.first.afterMethod, VerifyMethod.timer);
      expect(restored.changeLog.first.note, isNull);
    });

    test('구버전 데이터(changeLog 없음)도 안전하게 읽힌다', () {
      final json = make().toJson()..remove('changeLog');
      final restored = Routine.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(restored.changeLog, isEmpty);
    });
  });
}
