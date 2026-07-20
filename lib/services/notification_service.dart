import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/routine.dart';
import '../models/notif_settings.dart';

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

  // 알람급 채널 — 소리/진동 특성은 채널 생성 시 굳으므로, 강화하며 새 ID 사용
  static const _channelId = 'habit_alarm_v2';
  static const _channelName = '습관 마감 알람';

  // 알람이 오래 울리도록 긴 진동 패턴 (대기, 진동, 대기, 진동…)
  static final Int64List _vibrationPattern =
      Int64List.fromList([0, 600, 300, 600, 300, 600, 300, 800]);

  static NotificationDetails _alarmDetails() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '습관 마감 전 인증 리마인더 (알람)',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // 알람 사용 특성 → 무음/방해금지에서도 잘 들리게
          audioAttributesUsage: AudioAttributesUsage.alarm,
          playSound: true,
          enableVibration: true,
          vibrationPattern: _vibrationPattern,
          // insistent(무한반복) 제거 — 소리·진동은 강하게 한 번, 확인 버튼으로 끄기
          autoCancel: true, // 탭하면 사라짐
          ticker: '습관 인증 알림',
          actions: const [
            AndroidNotificationAction(
              _actionConfirm,
              '확인',
              cancelNotification: true, // 확인 → 즉시 알림 종료
            ),
            AndroidNotificationAction(
              _actionOpen,
              '지금 인증하기',
              showsUserInterface: true, // 앱 열기
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

  static const _actionConfirm = 'confirm';
  static const _actionOpen = 'open';

  // 마감(23:59) 몇 분 전에 알릴지. "3시간 전부터" 요구를 3개 슬롯으로 구현.
  // 실제 사용 여부는 NotifSettings의 슬롯 on/off로 결정.
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

  /// 현재 상태(루틴 + 인증 + 알림 설정)를 기준으로 알림 전체를 다시 예약한다.
  ///
  /// 알림 예약은 앱 데이터 흐름의 부수 작업이다 — 권한 취소·플랫폼 미지원 등으로
  /// 실패해도 인증 저장이나 설정 변경까지 깨지지 않도록 예외를 삼킨다.
  Future<void> reconcile(List<Routine> routines, List<Certification> certs,
      [NotifSettings settings = NotifSettings.defaults]) async {
    final notices = planNotices(routines, certs, settings);
    try {
      await _plugin.cancelAll();
      var id = 1;
      for (final n in notices) {
        await _scheduleOne(id++, n);
      }
    } catch (e, st) {
      debugPrint('알림 재예약 실패(무시하고 진행): $e\n$st');
    }
  }

  /// 어떤 알림을 언제 예약할지 계산하는 순수 함수 (플러그인 호출 없음 → 테스트 가능).
  /// 미인증 의무일에 대해 설정에 맞춰 마감 임박·아침 리마인더 알림을 만들고,
  /// 시각순으로 정렬해 상한(_maxPending)까지 자른다.
  @visibleForTesting
  List<PlannedNotice> planNotices(
    List<Routine> routines,
    List<Certification> certs,
    NotifSettings settings, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final certifiedKeys =
        certs.map((c) => '${c.routineId}|${c.dateKey}').toSet();

    final notices = <PlannedNotice>[];

    for (final r in routines) {
      for (var i = 0; i < _horizonDays; i++) {
        final day = today.add(Duration(days: i));
        if (!r.isDutyDay(day)) continue;
        if (certifiedKeys.contains('${r.id}|${dateKeyOf(day)}')) {
          continue; // 이미 인증 → 알림 없음
        }

        final deadline = r.deadlineOf(day);
        // 마감 당일 긴박 알림 (3h/1h/30m 전) — 설정에서 켠 슬롯만
        for (final offset in settings.activeOffsets) {
          final when = deadline.subtract(Duration(minutes: offset));
          if (when.isAfter(ref)) {
            notices.add(_notice(r, day, when, offsetMin: offset));
          }
        }
        // 결과형: 마감 3일 전부터 마감일까지 매일 아침(설정 시각) 리마인더
        if (r.isResultCycle) {
          for (var back = 3; back >= 0; back--) {
            final remindDay = day.subtract(Duration(days: back));
            final when = DateTime(remindDay.year, remindDay.month,
                remindDay.day, settings.morningHour, settings.morningMinute);
            if (when.isAfter(ref)) {
              final label = back == 0 ? '오늘이 마감일!' : '마감 D-$back';
              notices.add(_notice(r, day, when, customLabel: label));
            }
          }
        }
      }
    }

    notices.sort((a, b) => a.when.compareTo(b.when));
    return notices.take(_maxPending).toList();
  }

  /// 예약 항목 하나의 제목·본문을 만든다.
  PlannedNotice _notice(Routine r, DateTime day, DateTime when,
      {int? offsetMin, String? customLabel}) {
    final label = customLabel ??
        switch (offsetMin) {
          180 => '마감 3시간 전',
          60 => '마감 1시간 전',
          _ => '마감 30분 전',
        };
    // 이 알림 시점 기준으로 마감까지 남은 시간을 "N시간 M분"으로 명시
    final deadline = r.deadlineOf(day);
    final remain = deadline.difference(when);
    final remainText = _remainLabel(remain);
    return PlannedNotice(
      when: when,
      title: '⏰ 오늘 습관챌린지 마감까지 $remainText 남았습니다',
      body: "'${r.title}' 아직 인증 안 했어요. 완료하면 알람이 꺼집니다. ($label)",
      routineId: r.id,
      dateKey: dateKeyOf(day),
      isMorningReminder: customLabel != null,
    );
  }

  /// "N시간 M분" 형식 (알림 제목용)
  static String _remainLabel(Duration d) {
    if (d.inMinutes <= 0) return '0시간 0분';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h시간 $m분';
  }

  /// [임시] 알림 동작 확인용 — 1분 뒤 테스트 알림 (실기기 테스트 끝나면 제거)
  Future<void> scheduleTestNotification() async {
    final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      id: 999999,
      title: '⏰ 오늘 습관챌린지 마감까지 3시간 0분 남았습니다',
      body: '테스트 알람입니다. [확인]을 누르면 꺼져요. — KeepUp',
      scheduledDate: when,
      notificationDetails: _alarmDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _scheduleOne(int id, PlannedNotice n) async {
    await _plugin.zonedSchedule(
      id: id,
      title: n.title,
      body: n.body,
      scheduledDate: tz.TZDateTime.from(n.when, tz.local),
      notificationDetails: _alarmDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // 하루 단위 반복이 아니라 개별 예약이므로 matchDateTimeComponents 미사용
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

/// 예약될 알림 하나의 설명 — reconcile 전에 계산되어 예약·테스트에 함께 쓰인다.
class PlannedNotice {
  final DateTime when;
  final String title;
  final String body;
  final String routineId;
  final String dateKey; // 이 알림이 붙은 의무일
  final bool isMorningReminder; // 결과형 아침 리마인더 여부

  const PlannedNotice({
    required this.when,
    required this.title,
    required this.body,
    required this.routineId,
    required this.dateKey,
    required this.isMorningReminder,
  });
}
