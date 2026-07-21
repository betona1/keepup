import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/routine.dart';
import 'notification_service.dart';

/// 타이머 인증을 화면 이동·앱 종료와 무관하게 이어가는 서비스.
///
/// 핵심: 경과 시간을 '시작 시각' 기준 실시간(wall-clock)으로 계산한다.
/// 그래서 다른 화면으로 가거나 앱이 잠들어도 달리기·명상 시간이 실제로 계속 흐른다.
/// (Timer.periodic은 화면 표시 갱신용일 뿐, 시간 계산의 근거가 아니다.)
///
/// 완료 시:
///  - 앱이 켜져 있으면 [onComplete]로 인증 화면 자동 이동 → 도장 자동 찍기.
///  - 앱이 꺼져 있으면 시작할 때 예약해 둔 '완료 알림'이 대신 울린다.
class TimerService extends ChangeNotifier {
  static final TimerService instance = TimerService._();
  TimerService._();

  static const _kKey = 'active_timer_v1';

  SharedPreferences? _prefs;

  // ── 활성 세션 ──
  String? routineId;
  String? routineTitle;
  int _dayMillis = 0;
  int targetSec = 0;
  int _accumulatedSec = 0; // 지난 구간(일시정지 이전)들에서 쌓인 시간
  DateTime? _runningSince; // 현재 구간 시작 시각 (일시정지면 null)
  bool _completedHandled = false; // 완료 후처리(자동 도장)를 이미 했는지

  Timer? _ticker;

  /// 완료 시 호출 — (routineId, day). RootScreen이 인증 화면 이동/자동 도장에 사용.
  void Function(String routineId, DateTime day)? onComplete;

  bool get active => routineId != null;
  bool get running => _runningSince != null;
  DateTime get day => DateTime.fromMillisecondsSinceEpoch(_dayMillis);

  /// 시작 시각 기준 실시간 경과초
  int get elapsedSec {
    var e = _accumulatedSec;
    if (_runningSince != null) {
      e += DateTime.now().difference(_runningSince!).inSeconds;
    }
    return e < 0 ? 0 : e;
  }

  bool get done => targetSec > 0 && elapsedSec >= targetSec;

  bool isActiveFor(String rid) => active && routineId == rid;

  /// 특정 루틴의 실시간 경과초 (그 루틴의 활성 세션이 아니면 0)
  int elapsedFor(String rid) => isActiveFor(rid) ? elapsedSec : 0;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      routineId = m['routineId'] as String?;
      routineTitle = m['routineTitle'] as String?;
      _dayMillis = (m['dayMillis'] as num?)?.toInt() ?? 0;
      targetSec = (m['targetSec'] as num?)?.toInt() ?? 0;
      _accumulatedSec = (m['accumulatedSec'] as num?)?.toInt() ?? 0;
      final since = (m['runningSinceMillis'] as num?)?.toInt();
      _runningSince =
          since == null ? null : DateTime.fromMillisecondsSinceEpoch(since);
      _completedHandled = m['completedHandled'] as bool? ?? false;
      if (running && !done) _startTicker();
    } catch (_) {
      _clearFields();
    }
  }

  Future<void> _persist() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    if (!active) {
      await p.remove(_kKey);
      return;
    }
    await p.setString(
        _kKey,
        jsonEncode({
          'routineId': routineId,
          'routineTitle': routineTitle,
          'dayMillis': _dayMillis,
          'targetSec': targetSec,
          'accumulatedSec': _accumulatedSec,
          'runningSinceMillis': _runningSince?.millisecondsSinceEpoch,
          'completedHandled': _completedHandled,
        }));
  }

  void _clearFields() {
    routineId = null;
    routineTitle = null;
    _dayMillis = 0;
    targetSec = 0;
    _accumulatedSec = 0;
    _runningSince = null;
    _completedHandled = false;
  }

  /// 이 루틴의 타이머를 시작/이어가기 ↔ 일시정지 (화면의 시작/일시정지 버튼).
  Future<void> toggle(Routine r, DateTime day) async {
    if (!isActiveFor(r.id)) {
      // 다른(또는 없는) 세션 → 이 루틴으로 새 세션 시작
      _clearFields();
      routineId = r.id;
      routineTitle = r.title;
      final d = DateTime(day.year, day.month, day.day);
      _dayMillis = d.millisecondsSinceEpoch;
      targetSec = r.timerMinutes * 60;
      await _resume();
      return;
    }
    if (running) {
      await _pause();
    } else {
      await _resume();
    }
  }

  Future<void> _resume() async {
    _runningSince = DateTime.now();
    _startTicker();
    // 앱이 꺼져 있어도 완료 시점에 울리도록 완료 알림 예약
    await _armNotification();
    await _persist();
    notifyListeners();
  }

  Future<void> _pause() async {
    _accumulatedSec = elapsedSec;
    _runningSince = null;
    _stopTicker();
    await NotificationService.instance.cancelTimerDone();
    await _persist();
    notifyListeners();
  }

  /// 타이머를 완전히 지운다 (리셋 버튼 / 인증 완료 후).
  Future<void> reset() async {
    _stopTicker();
    await NotificationService.instance.cancelTimerDone();
    _clearFields();
    await _persist();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (done && !_completedHandled) {
        _handleComplete();
      } else {
        notifyListeners();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 앱이 백그라운드였다가 돌아왔을 때 완료 여부를 점검 (ticker가 안 돌았을 수 있음).
  void checkCompletion() {
    if (active && done && !_completedHandled) {
      _handleComplete();
    }
  }

  void _handleComplete() {
    // 목표 시간에서 정확히 멈춘다
    _accumulatedSec = targetSec;
    _runningSince = null;
    _completedHandled = true;
    _stopTicker();
    NotificationService.instance.cancelTimerDone();
    _persist();
    notifyListeners();
    final rid = routineId;
    final d = day;
    if (rid != null) onComplete?.call(rid, d);
  }

  /// reconcile()이 cancelAll로 지운 뒤 다시 완료 알림을 걸어준다.
  Future<void> rearmNotification() async {
    if (active && running && !done) await _armNotification();
  }

  Future<void> _armNotification() async {
    final remain = targetSec - elapsedSec;
    if (remain <= 0) return;
    final when = DateTime.now().add(Duration(seconds: remain));
    await NotificationService.instance
        .scheduleTimerDone(when, routineTitle ?? '타이머');
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
