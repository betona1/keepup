import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/app_state.dart';
import 'package:keepup/models/crew.dart';
import 'package:keepup/models/notif_settings.dart';
import 'package:keepup/models/routine.dart';
import 'package:keepup/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 크루 과제 ↔ 개인 루틴 연동 (Pro).
/// 서버 마감 계산(duty.ts)과 앱 Routine 규칙의 일치는 별도로 516건 대조 검증했고,
/// 여기서는 앱 쪽 변환·동기화 규칙을 검증한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notifChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
  });

  CrewTask task({
    int id = 7,
    String title = '매일 독서 20분',
    DutyCycle cycle = DutyCycle.everyday,
    String start = '2026-10-01',
    String end = '2026-12-02',
    String? joined,
  }) =>
      CrewTask(
        id: id,
        crewId: 3,
        crewName: '독서크루',
        type: resultCycles.contains(cycle)
            ? RoutineType.result
            : RoutineType.accumulate,
        title: title,
        reason: '함께 읽기',
        dutyCycle: cycle,
        dueWeekday: 7,
        verifyMethod: VerifyMethod.photo,
        timerMinutes: 15,
        requireNote: true,
        startDate: start,
        endDate: end,
        archived: false,
        myJoinedAt: joined,
      );

  group('CrewTask.toRoutine', () {
    test('과제가 크루 연결 정보를 가진 개인 루틴이 된다', () {
      final r = task().toRoutine();
      expect(r.id, 'crew-7');
      expect(r.isCrew, isTrue);
      expect(r.crewId, 3);
      expect(r.crewName, '독서크루');
      expect(r.requireNote, isTrue);
      expect(r.startDate, DateTime(2026, 10, 1));
      expect(r.endDate, DateTime(2026, 12, 2));
    });

    test('늦게 가입한 회원은 가입일부터 의무가 시작된다', () {
      final r = task(joined: '2026-10-06').toRoutine();
      expect(r.startDate, DateTime(2026, 10, 6));
      expect(r.isDutyDay(DateTime(2026, 10, 5)), isFalse);
      expect(r.isDutyDay(DateTime(2026, 10, 6)), isTrue);
    });

    test('15일 주기는 시작일이 마감 기준점이라 가입일로 옮기지 않는다', () {
      final t = task(cycle: DutyCycle.every15days, joined: '2026-10-06');
      final r = t.toRoutine();
      expect(r.startDate, DateTime(2026, 10, 1));
      // 서버와 같은 마감일: 시작 10/1 → 첫 마감 10/15
      expect(r.dutyKeyDate(DateTime(2026, 10, 6)), DateTime(2026, 10, 15));
    });

    test('기존 루틴의 아이콘·생성일은 이어받는다', () {
      final first = task().toRoutine()..iconPath = 'icon.jpg';
      final again = task(title: '독서 30분').toRoutine(existing: first);
      expect(again.iconPath, 'icon.jpg');
      expect(again.createdAt, first.createdAt);
      expect(again.title, '독서 30분');
    });

    CrewTask classTask(ClassSchedule cs) => CrewTask(
          id: 11,
          crewId: 3,
          kind: CrewTaskKind.assignment,
          dueWeekdays: const [4, 7],
          classSchedule: cs,
          type: RoutineType.result,
          title: '주간 과제',
          reason: '',
          dutyCycle: DutyCycle.weekly,
          dueWeekday: 4,
          verifyMethod: VerifyMethod.photo,
          timerMinutes: 15,
          requireNote: false,
          startDate: '2026-10-05',
          endDate: '2026-12-31',
          archived: false,
        );

    test('수업 시간표: 목 19:30·일 15:00 수업, 1분 전 마감', () {
      final t = classTask(const ClassSchedule(
          days: {4: 19 * 60 + 30, 7: 15 * 60}, rule: 'before', minutes: 1));
      final r = t.toRoutine();
      // 목(10/8) 19:29, 일(10/11) 14:59 — 마감 알람도 이 시각 기준
      expect(r.deadlineOf(DateTime(2026, 10, 8)), DateTime(2026, 10, 8, 19, 29));
      expect(r.deadlineOf(DateTime(2026, 10, 11)), DateTime(2026, 10, 11, 14, 59));
      expect(t.scheduleLabel, '매주 목 19:30·일 15:00 수업 · 수업 1분 전 마감');
      final back = Routine.fromJson(r.toJson());
      expect(back.deadlineOf(DateTime(2026, 10, 11)), DateTime(2026, 10, 11, 14, 59));
    });

    test('수업 시간표: 수업 30분 전 / 수업 전날 23:59 마감', () {
      final r30 = classTask(const ClassSchedule(
              days: {4: 19 * 60 + 30, 7: 15 * 60}, rule: 'before', minutes: 30))
          .toRoutine();
      expect(r30.deadlineOf(DateTime(2026, 10, 8)), DateTime(2026, 10, 8, 19));
      final prev = classTask(const ClassSchedule(
              days: {4: 19 * 60 + 30, 7: 15 * 60}, rule: 'prevDay'))
          .toRoutine();
      // 목요일 회차는 수요일 23:59, 일요일 회차는 토요일 23:59에 마감
      expect(prev.deadlineOf(DateTime(2026, 10, 8)), DateTime(2026, 10, 7, 23, 59));
      expect(prev.deadlineOf(DateTime(2026, 10, 11)), DateTime(2026, 10, 10, 23, 59));
    });

    test('과제 점검형: 매주 목·일 21:00 마감이 개인 루틴에 그대로 들어온다', () {
      final t = CrewTask(
        id: 9,
        crewId: 3,
        crewName: '독서모임',
        kind: CrewTaskKind.assignment,
        dueWeekdays: const [4, 7],
        deadlineMin: 21 * 60,
        type: RoutineType.result,
        title: '주간 독서 과제',
        reason: '',
        dutyCycle: DutyCycle.weekly,
        dueWeekday: 4,
        verifyMethod: VerifyMethod.photo,
        timerMinutes: 15,
        requireNote: false,
        startDate: '2026-10-05', // 월
        endDate: '2026-12-31',
        archived: false,
      );
      final r = t.toRoutine();
      expect(r.crewAssignment, isTrue);
      expect(r.weeklyDueLabel, '목·일');
      // 월요일엔 목요일 회차, 금요일엔 일요일 회차로 카운트
      expect(r.dutyKeyDate(DateTime(2026, 10, 5)), DateTime(2026, 10, 8));
      expect(r.dutyKeyDate(DateTime(2026, 10, 9)), DateTime(2026, 10, 11));
      expect(r.isDutyDay(DateTime(2026, 10, 8)), isTrue);
      expect(r.isDutyDay(DateTime(2026, 10, 10)), isFalse);
      // 마감 21:00 — 알람도 이 시각 기준
      expect(r.deadlineOf(DateTime(2026, 10, 8)), DateTime(2026, 10, 8, 21));
      expect(t.scheduleLabel, '매주 목·일 21:00 마감');
      final back = Routine.fromJson(r.toJson());
      expect(back.dueWeekdays, [4, 7]);
      expect(back.deadlineMin, 21 * 60);
      expect(back.crewAssignment, isTrue);
    });

    test('직렬화 라운드트립에 크루 필드가 남는다', () {
      final r = task().toRoutine();
      final back = Routine.fromJson(r.toJson());
      expect(back.crewTaskId, 7);
      expect(back.crewId, 3);
      expect(back.crewName, '독서크루');
    });
  });

  group('AppState.applyCrewTasks', () {
    Certification cert(String routineId) => Certification(
          id: 'c1',
          routineId: routineId,
          dateKey: '2026-10-06',
          photoPath: '',
          memo: '30쪽',
          timestamp: DateTime(2026, 10, 6, 21),
        );

    test('새 과제 추가 → 내용 변경 반영 → 변경 없으면 0', () async {
      final state = AppState(_FakeStorage());
      expect(await state.applyCrewTasks([task()]), 1);
      expect(state.routineById('crew-7')!.title, '매일 독서 20분');
      expect(await state.applyCrewTasks([task(title: '독서 30분')]), 1);
      expect(state.routineById('crew-7')!.title, '독서 30분');
      expect(await state.applyCrewTasks([task(title: '독서 30분')]), 0);
    });

    test('개인 루틴은 건드리지 않는다', () async {
      final state = AppState(_FakeStorage());
      state.routines = [
        Routine(
            id: 'mine',
            type: RoutineType.accumulate,
            title: '걷기',
            reason: '',
            dutyCycle: DutyCycle.everyday,
            createdAt: DateTime(2026, 10, 1)),
      ];
      await state.applyCrewTasks([task()]);
      expect(state.routines.map((r) => r.id), ['mine', 'crew-7']);
      await state.applyCrewTasks([]);
      expect(state.routines.map((r) => r.id), ['mine']);
    });

    test('과제가 빠지면: 도장 없으면 정리, 도장 있으면 개인 루틴으로 남는다', () async {
      final state = AppState(_FakeStorage());
      await state.applyCrewTasks([task(), task(id: 8, title: '영어')]);
      state.certs = [cert('crew-7')];
      expect(await state.applyCrewTasks([]), 2);
      expect(state.routineById('crew-8'), isNull);
      final kept = state.routineById('crew-7')!;
      expect(kept.isCrew, isFalse);
      expect(kept.title, '매일 독서 20분');
    });

    test('나갔다 다시 들어오면 같은 루틴에 다시 연결된다 (중복 없음)', () async {
      final state = AppState(_FakeStorage());
      await state.applyCrewTasks([task()]);
      state.certs = [cert('crew-7')];
      await state.applyCrewTasks([]); // 탈퇴 → 개인 루틴으로 남음
      await state.applyCrewTasks([task()]); // 재가입
      expect(state.routines.where((r) => r.id == 'crew-7').length, 1);
      expect(state.routineById('crew-7')!.isCrew, isTrue);
    });

    test('크루 루틴은 개인이 변경·기간수정·삭제할 수 없다', () async {
      final state = AppState(_FakeStorage());
      await state.applyCrewTasks([task()]);
      expect(await state.changeRoutine('crew-7', newTitle: '딴거'), isFalse);
      expect(await state.updateEndDate('crew-7', DateTime(2027, 1, 1)), isFalse);
      expect(await state.updateStartDate('crew-7', DateTime(2026, 9, 1)),
          isFalse);
      expect(await state.deleteRoutine('crew-7'), isFalse);
      expect(state.routineById('crew-7'), isNotNull);
    });
  });
}

class _FakeStorage implements StorageService {
  @override
  List<Routine> loadRoutines() => [];
  @override
  List<Certification> loadCerts() => [];
  @override
  NotifSettings loadNotifSettings() => NotifSettings.defaults;
  @override
  Future<void> saveRoutines(List<Routine> r) async {}
  @override
  Future<void> saveCerts(List<Certification> c) async {}
  @override
  Future<void> saveNotifSettings(NotifSettings s) async {}
}
