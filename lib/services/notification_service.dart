import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/routine.dart';

/// 마감 전 로컬 알림을 관리한다.
///
/// 전략: 서버 없이 폰의 로컬 알림만 사용하므로,
/// "앞으로의 의무일들"에 대해 마감 3시간 전 / 1시간 전 / 30분 전 알림을
/// 미리 예약한다. 이미 인증한 날은 예약에서 제외한다.
/// 인증하거나 앱을 열 때마다 reconcile()로 전체 재예약해 상태를 맞춘다.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'habit_reminder';
  static const _channelName = '습관 인증 알림';

  // 마감(23:59) 몇 분 전에 알릴지. "3시간 전부터" 요구를 3개 슬롯으로 구현.
  static const List<int> offsetsMinutes = [180, 60, 30];

  // 예약 상한 (iOS는 대기 알림 64개 제한이 있어 여유 있게 60으로 캡)
  static const int _maxPending = 60;
  static const int _horizonDays = 21; // 결과형 D-3 리마인더까지 여유 있게

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );
  }

  /// 권한 요청 (Android 13+, iOS)
  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// 현재 상태(루틴 + 인증)를 기준으로 알림 전체를 다시 예약한다.
  Future<void> reconcile(
      List<Routine> routines, List<Certification> certs) async {
    await _plugin.cancelAll();

    final now = DateTime.now();
    final certifiedKeys =
        certs.map((c) => '${c.routineId}|${c.dateKey}').toSet();

    final pendings = <_Pending>[];
    final today = DateTime(now.year, now.month, now.day);

    for (final r in routines) {
      for (var i = 0; i < _horizonDays; i++) {
        final day = today.add(Duration(days: i));
        if (!r.isDutyDay(day)) continue;
        final key = '${r.id}|${dateKeyOf(day)}';
        if (certifiedKeys.contains(key)) continue; // 이미 인증 → 알림 없음

        final deadline = r.deadlineOf(day);
        // 마감 당일 긴박 알림 (3h/1h/30m 전) — 공통
        for (var s = 0; s < offsetsMinutes.length; s++) {
          final when = deadline.subtract(Duration(minutes: offsetsMinutes[s]));
          if (when.isAfter(now)) {
            pendings.add(_Pending(r, day, s, offsetsMinutes[s], when));
          }
        }
        // 결과형: 마감 3일 전부터 마감일까지 매일 아침 9시 리마인더
        if (r.isResultCycle) {
          for (var back = 3; back >= 0; back--) {
            final remindDay = day.subtract(Duration(days: back));
            final when = DateTime(
                remindDay.year, remindDay.month, remindDay.day, 9, 0);
            if (when.isAfter(now)) {
              final label = back == 0 ? '오늘이 마감일!' : '마감 D-$back';
              pendings.add(_Pending(r, day, 10 + back, 0, when,
                  customLabel: label));
            }
          }
        }
      }
    }

    pendings.sort((a, b) => a.when.compareTo(b.when));
    final capped = pendings.take(_maxPending).toList();

    var id = 1;
    for (final p in capped) {
      await _scheduleOne(id++, p);
    }
  }

  /// [임시] 알림 동작 확인용 — 1분 뒤 테스트 알림 (실기기 테스트 끝나면 제거)
  Future<void> scheduleTestNotification() async {
    final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      id: 999999,
      title: '⏰ 테스트 알림',
      body: 'KeepUp 알림이 정상 동작합니다! (예약 1분 뒤 발사)',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '습관 마감 전 인증 리마인더',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _scheduleOne(int id, _Pending p) async {
    final tzTime = tz.TZDateTime.from(p.when, tz.local);

    final label = p.customLabel ??
        switch (p.offsetMin) {
          180 => '마감 3시간 전',
          60 => '마감 1시간 전',
          _ => '마감 30분 전',
        };
    final title = '⏰ $label · 아직 인증 안 했어요';
    final body = p.routine.isResultCycle
        ? "'${p.routine.title}' 마감(${dateKeyOf(p.day)})까지 결과를 인증해 주세요!"
        : "'${p.routine.title}' 오늘(${dateKeyOf(p.day)}) 인증하고 습관 지키기!";

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '습관 마감 전 인증 리마인더',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // 하루 단위 반복이 아니라 개별 예약이므로 matchDateTimeComponents 미사용
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

class _Pending {
  final Routine routine;
  final DateTime day;
  final int slot;
  final int offsetMin;
  final DateTime when;
  final String? customLabel; // 결과형 D-n 리마인더 등
  _Pending(this.routine, this.day, this.slot, this.offsetMin, this.when,
      {this.customLabel});
}
