import 'package:flutter/foundation.dart';
import 'models/routine.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';

/// 앱 전역 상태. 저장소와 알림 예약을 함께 관리한다.
class AppState extends ChangeNotifier {
  final StorageService _storage;
  AppState(this._storage);

  List<Routine> routines = [];
  List<Certification> certs = [];

  Future<void> load() async {
    routines = _storage.loadRoutines();
    certs = _storage.loadCerts();
    await _syncNotifications();
    notifyListeners();
  }

  Future<void> _persistAndSync() async {
    await _storage.saveRoutines(routines);
    await _storage.saveCerts(certs);
    await _syncNotifications();
    notifyListeners();
  }

  Future<void> _syncNotifications() async {
    await NotificationService.instance.reconcile(routines, certs);
  }

  // ---- 루틴 ----

  Future<void> addRoutine(Routine r) async {
    routines = [...routines, r];
    await _persistAndSync();
  }

  Future<void> deleteRoutine(String routineId) async {
    routines = routines.where((r) => r.id != routineId).toList();
    certs = certs.where((c) => c.routineId != routineId).toList();
    await _persistAndSync();
  }

  /// 기간 내 루틴 변경 찬스 (인당 1회). 성공 시 true.
  Future<bool> changeRoutine(String routineId,
      {required String newTitle, String? newTarget, String? newBackup}) async {
    final idx = routines.indexWhere((r) => r.id == routineId);
    if (idx < 0) return false;
    final r = routines[idx];
    if (r.changeUsedCount >= 1) return false; // 이미 변경 찬스 소진

    routines[idx] = Routine(
      id: r.id,
      type: r.type,
      title: newTitle,
      reason: r.reason,
      dutyCycle: r.dutyCycle,
      backupTitle: newBackup ?? r.backupTitle,
      targetValue: newTarget ?? r.targetValue,
      createdAt: r.createdAt,
      verifyMethod: r.verifyMethod,
      timerMinutes: r.timerMinutes,
      requireNote: r.requireNote,
      windowStartMin: r.windowStartMin,
      windowEndMin: r.windowEndMin,
      startDate: r.startDate,
      endDate: r.endDate,
      changeUsedCount: r.changeUsedCount + 1,
    );
    routines = [...routines];
    await _persistAndSync();
    return true;
  }

  /// 완료 목표일 변경 (최소: 시작일+29일 = 30일 시즌)
  Future<bool> updateEndDate(String routineId, DateTime newEnd) async {
    final idx = routines.indexWhere((r) => r.id == routineId);
    if (idx < 0) return false;
    final r = routines[idx];
    final minEnd = r.startDate.add(const Duration(days: 29));
    if (newEnd.isBefore(minEnd)) return false;

    routines[idx] = Routine(
      id: r.id,
      type: r.type,
      title: r.title,
      reason: r.reason,
      dutyCycle: r.dutyCycle,
      backupTitle: r.backupTitle,
      targetValue: r.targetValue,
      createdAt: r.createdAt,
      verifyMethod: r.verifyMethod,
      timerMinutes: r.timerMinutes,
      requireNote: r.requireNote,
      windowStartMin: r.windowStartMin,
      windowEndMin: r.windowEndMin,
      startDate: r.startDate,
      endDate: newEnd,
      changeUsedCount: r.changeUsedCount,
    );
    routines = [...routines];
    await _persistAndSync();
    return true;
  }

  // ---- 인증 ----

  Future<void> addCertification(Certification c) async {
    certs = [...certs, c];
    await _persistAndSync();
  }

  // ---- 조회 헬퍼 ----

  /// 오늘 의무 인증 대상 루틴들
  List<Routine> dutyRoutinesForDay(DateTime day) =>
      routines.where((r) => r.isDutyDay(day)).toList();

  /// 특정 루틴이 특정 날짜에 인증됐는지
  bool isCertified(String routineId, DateTime day) {
    final key = dateKeyOf(day);
    return certs.any((c) => c.routineId == routineId && c.dateKey == key);
  }

  List<Certification> certsForRoutine(String routineId) {
    final list =
        certs.where((c) => c.routineId == routineId).toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  List<Certification> allCertsSorted() {
    final list = [...certs];
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Routine? routineById(String id) {
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 성취 완성도(%) — 시즌 전체 의무일 중 인증 완료한 비율 (0~100)
  int progressPercent(String routineId) {
    final r = routineById(routineId);
    if (r == null) return 0;
    final total = r.totalDutyDays();
    if (total == 0) return 0;
    final done = certs
        .where((c) => c.routineId == routineId)
        .map((c) => c.dateKey)
        .toSet()
        .length;
    return ((done / total) * 100).round().clamp(0, 100);
  }

  /// 인증 완료한 의무일 수
  int certifiedDayCount(String routineId) => certs
      .where((c) => c.routineId == routineId)
      .map((c) => c.dateKey)
      .toSet()
      .length;

  /// 미인증 카운트 (반장 제외 등은 혼자 쓰므로 생략, 순수 통계용)
  int missCountForRoutine(String routineId) {
    final r = routineById(routineId);
    if (r == null) return 0;
    final now = DateTime.now();
    final start = DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day);
    var miss = 0;
    for (var d = start;
        d.isBefore(DateTime(now.year, now.month, now.day));
        d = d.add(const Duration(days: 1))) {
      if (r.isDutyDay(d) && !isCertified(routineId, d)) miss++;
    }
    return miss;
  }
}
