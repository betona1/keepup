import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/models/notif_settings.dart';
import 'package:keepup/models/routine.dart';
import 'package:keepup/services/notification_service.dart';

/// 알림 설정이 실제 예약 계획(planNotices)을 바꾸는지 검증한다.
/// planNotices는 플러그인 호출이 없는 순수 함수라 실기기 없이 돌아간다.
void main() {
  final svc = NotificationService.instance;

  // 기준 시각을 고정 — 오늘 정오 (임박 알림이 아직 미래가 되도록)
  final now = DateTime(2026, 1, 5, 12, 0); // 2026-01-05는 월요일

  Routine dailyPhoto() => Routine(
        id: 'acc',
        type: RoutineType.accumulate,
        title: '매일 걷기',
        reason: '',
        dutyCycle: DutyCycle.everyday,
        createdAt: now,
        verifyMethod: VerifyMethod.photo,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 1),
      );

  Routine weeklyResult() => Routine(
        id: 'res',
        type: RoutineType.result,
        title: '주간 독서',
        reason: '',
        dutyCycle: DutyCycle.weekly,
        dueWeekday: DateTime.friday,
        createdAt: now,
        verifyMethod: VerifyMethod.timer,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 1),
      );

  List<PlannedNotice> plan(Routine r, NotifSettings s) =>
      svc.planNotices([r], const [], s, now: now);

  group('마감 임박 슬롯 on/off', () {
    test('기본값 — 오늘 마감 임박 슬롯 3개 모두 예약된다', () {
      final today = plan(dailyPhoto(), NotifSettings.defaults)
          .where((n) => n.dateKey == '2026-01-05' && !n.isMorningReminder)
          .toList();
      // 정오 기준 23:59 마감의 3h/1h/30m 전은 모두 미래
      expect(today.length, 3);
    });

    test('30분 전만 켜면 오늘 임박 알림은 1개', () {
      const s = NotifSettings(slot180: false, slot60: false, slot30: true);
      final today = plan(dailyPhoto(), s)
          .where((n) => n.dateKey == '2026-01-05' && !n.isMorningReminder)
          .toList();
      expect(today.length, 1);
      expect(today.single.title, contains('30분 전'));
    });

    test('슬롯을 모두 끄면 적립형은 예약이 하나도 없다', () {
      const s = NotifSettings(slot180: false, slot60: false, slot30: false);
      expect(plan(dailyPhoto(), s), isEmpty);
    });

    test('activeOffsets는 큰 값(먼저 울릴 것)부터', () {
      expect(NotifSettings.defaults.activeOffsets, [180, 60, 30]);
      expect(
        const NotifSettings(slot180: false).activeOffsets,
        [60, 30],
      );
    });
  });

  group('아침 리마인더 시각', () {
    List<PlannedNotice> morningReminders(NotifSettings s) =>
        plan(weeklyResult(), s).where((n) => n.isMorningReminder).toList();

    test('기본 09:00에 예약된다', () {
      final ms = morningReminders(NotifSettings.defaults);
      expect(ms, isNotEmpty);
      expect(ms.every((n) => n.when.hour == 9 && n.when.minute == 0), isTrue);
    });

    test('06:30으로 바꾸면 모든 아침 리마인더가 그 시각', () {
      final ms = morningReminders(
          const NotifSettings(morningHour: 6, morningMinute: 30));
      expect(ms, isNotEmpty);
      expect(ms.every((n) => n.when.hour == 6 && n.when.minute == 30), isTrue);
    });

    test('아침 리마인더는 결과형에만 — 적립형엔 없다', () {
      final ms = plan(dailyPhoto(), NotifSettings.defaults)
          .where((n) => n.isMorningReminder);
      expect(ms, isEmpty);
    });

    test('마감 임박 슬롯을 꺼도 아침 리마인더는 남는다', () {
      const s = NotifSettings(slot180: false, slot60: false, slot30: false);
      expect(morningReminders(s), isNotEmpty);
    });
  });

  group('인증한 날은 제외', () {
    test('오늘 인증하면 오늘 알림이 사라진다', () {
      final r = dailyPhoto();
      final cert = Certification(
        id: 'c1',
        routineId: r.id,
        dateKey: '2026-01-05',
        photoPath: '',
        memo: '',
        timestamp: now,
      );
      final after =
          svc.planNotices([r], [cert], NotifSettings.defaults, now: now);
      expect(after.any((n) => n.dateKey == '2026-01-05'), isFalse);
      // 내일 것은 남아 있다
      expect(after.any((n) => n.dateKey == '2026-01-06'), isTrue);
    });
  });

  group('직렬화', () {
    test('round-trip', () {
      const s = NotifSettings(
          morningHour: 7, morningMinute: 15, slot60: false);
      final back = NotifSettings.fromJson(s.toJson());
      expect(back.morningHour, 7);
      expect(back.morningMinute, 15);
      expect(back.slot60, isFalse);
      expect(back.slot180, isTrue);
    });

    test('빈/누락 필드는 기본값', () {
      final back = NotifSettings.fromJson(const {});
      expect(back.morningHour, 9);
      expect(back.slot180, isTrue);
    });
  });
}
