import 'dart:io' show File;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:path_provider/path_provider.dart';
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

  // 알람급 채널.
  // 안드로이드는 채널을 한 번 만들면 소리·중요도를 코드로 바꿀 수 없다.
  // 그래서 알람 특성을 손볼 때마다 새 ID로 만들고 옛 채널은 지운다.
  static const _channelId = 'habit_alarm_v4';
  static const _channelName = '습관 마감 알람';
  static const _oldChannelIds = [
    'habit_alarm',
    'habit_alarm_v2',
    'habit_alarm_v3',
  ];

  // 잔여 알림용 조용한 채널 — 알람(1분)이 끝나 사라진 뒤,
  // 소리·진동 없이 알림창에 남아 "아직 인증 전"을 상기시킨다.
  static const _silentChannelId = 'habit_reminder_v1';
  static const _silentChannelName = '습관 리마인더 (무음)';

  /// 잔여 알림 ID 대역 — 알람 슬롯 id(1.._maxPending)에 이 값을 더해 쓴다.
  static const _residualBase = 10000;

  /// 알람이 끝나고 잔여 알림이 뜨기까지의 여유 (알람 1분 + 15초)
  static Duration get _residualDelay =>
      alarmRingDuration + const Duration(seconds: 15);

  /// 잔여 알림은 안드로이드 전용.
  /// iOS는 소리가 한 번 울리고 알림이 알림센터에 계속 남으므로 필요 없고,
  /// 대기 알림 64개 제한이 있어 오히려 알람 슬롯을 잡아먹는다.
  static bool get _wantsResidual =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// **기기의 시스템 알람음**을 쓴다.
  ///
  /// 알림음(notification_sound)이 아니라 알람음(alarm_alert)이라서
  /// 기본 알림음이 '없음'으로 설정된 기기에서도 소리가 난다.
  /// (앱에 wav를 넣는 방식은 이 프로젝트 빌드에서 raw 리소스가 APK에 포함되지 않아
  ///  `invalid_sound` 예외로 예약 자체가 실패했다 — 2026-08-07)
  static const _alarmSound =
      UriAndroidNotificationSound('content://settings/system/alarm_alert');

  /// 상태바 작은 아이콘. 런처 아이콘을 그대로 쓴다 —
  /// 이 프로젝트는 새로 추가한 안드로이드 리소스가 APK에 병합되지 않는 문제가 있어
  /// (raw/drawable 모두 재현) 이미 번들된 리소스만 참조한다.
  static const _statusIcon = '@mipmap/ic_launcher';

  static const _brandColor = Color(0xFF7C5CFF); // AppTheme.stamp (도장 바이올렛)

  /// 알림 오른쪽에 뜨는 바브바브 얼굴.
  /// Flutter 에셋을 앱 폴더에 복사해 파일 경로로 넘긴다(안드로이드 리소스 우회).
  static String? _largeIconPath;

  /// 얼굴 이미지를 파일로 준비한다. 실패해도 알림 자체는 정상 동작.
  Future<void> _prepareLargeIcon() async {
    if (kIsWeb) return;
    try {
      final bytes = await rootBundle.load('assets/character/vave_face.png');
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/notify_vave.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _largeIconPath = file.path;
    } catch (e) {
      debugPrint('알림용 캐릭터 이미지 준비 실패(무시): $e');
    }
  }

  /// 알람이 울리는 동안 계속 이어지는 진동 패턴 (대기, 진동, 대기, 진동…)
  static final Int64List _vibrationPattern =
      Int64List.fromList([0, 700, 300, 700, 300, 700, 300, 900]);

  /// 소리가 계속 울리는 시간. 이 시간이 지나면 시스템이 알림을 스스로 거둬
  /// 소리도 멈춘다. 그전에 사용자가 끄면 즉시 멈춘다.
  static const alarmRingDuration = Duration(minutes: 1);

  /// FLAG_INSISTENT — 알림이 사라질 때까지 소리를 반복 재생한다.
  /// (안드로이드 Notification.FLAG_INSISTENT = 4)
  static final Int32List _insistentFlag = Int32List.fromList([4]);

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '습관 마감 전 인증 알람 — 소리가 1분간 울립니다',
        importance: Importance.max,
        playSound: true,
        sound: _alarmSound,
        enableVibration: true,
        vibrationPattern: _vibrationPattern,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

  static const _silentChannel = AndroidNotificationChannel(
        _silentChannelId,
        _silentChannelName,
        description: '알람이 끝난 뒤 조용히 남는 인증 리마인더',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      );

  /// 내장 알람음을 쓸 수 있는지. 기기가 리소스를 못 찾는 예외를 한 번 내면
  /// 이후로는 기본 알림음으로 내려가 **알람이 아예 안 울리는 일은 없게** 한다.
  bool _customSoundOk = true;

  NotificationDetails _alarmDetails({String? bigText}) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '습관 마감 전 인증 알람 — 소리가 1분간 울립니다',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          // ── 바브바브가 함께 뜨는 알림 ──
          icon: _statusIcon,
          largeIcon: _largeIconPath == null
              ? null
              : FilePathAndroidBitmap(_largeIconPath!),
          color: _brandColor,
          subText: 'Log Challenge',
          styleInformation: bigText == null
              ? null
              : BigTextStyleInformation(
                  bigText,
                  htmlFormatBigText: true,
                  summaryText: '바브바브가 도장 들고 기다리는 중 🐒',
                  htmlFormatSummaryText: true,
                ),
          // 알람 사용 특성 → 알람 볼륨으로, 무음 모드에서도 들리게
          audioAttributesUsage: AudioAttributesUsage.alarm,
          playSound: true,
          sound: _customSoundOk ? _alarmSound : null,
          enableVibration: true,
          vibrationPattern: _vibrationPattern,
          // 사용자가 끌 때까지 소리 반복 (알람답게)
          additionalFlags: _insistentFlag,
          // 다만 무한정 울리지 않도록 1분 뒤에는 시스템이 알림을 거둔다
          timeoutAfter: alarmRingDuration.inMilliseconds,
          // 화면이 꺼져 있거나 잠금화면이어도 알람처럼 크게 뜬다
          fullScreenIntent: true,
          autoCancel: true, // 탭하면 사라짐 → 소리도 멈춤
          ticker: '습관 인증 알람',
          actions: const [
            AndroidNotificationAction(
              _actionConfirm,
              '알람 끄기',
              cancelNotification: true, // 누르면 즉시 소리 정지
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
          presentSound: true,
        ),
      );

  /// 잔여 알림 — 소리·진동 없이 알림창에 남는 카드.
  /// 알람과 같은 얼굴·색을 쓰되 조용한 채널로 보낸다.
  NotificationDetails _silentDetails({String? bigText}) => NotificationDetails(
        android: AndroidNotificationDetails(
          _silentChannelId,
          _silentChannelName,
          channelDescription: '알람이 끝난 뒤 조용히 남는 인증 리마인더',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          icon: _statusIcon,
          largeIcon: _largeIconPath == null
              ? null
              : FilePathAndroidBitmap(_largeIconPath!),
          color: _brandColor,
          subText: 'Log Challenge',
          styleInformation: bigText == null
              ? null
              : BigTextStyleInformation(
                  bigText,
                  htmlFormatBigText: true,
                  summaryText: '바브바브가 도장 들고 기다리는 중 🐒',
                  htmlFormatSummaryText: true,
                ),
          playSound: false,
          enableVibration: false,
          autoCancel: true,
          actions: const [
            AndroidNotificationAction(
              _actionOpen,
              '지금 인증하기',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
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

  /// 웹(PWA)에는 예약형 로컬 알림이 없다 — 알림 관련 호출을 전부 건너뛴다.
  /// (앱이 닫혀 있어도 울리는 마감 알람은 설치형 앱에서만 가능)
  static const bool supported = !kIsWeb;

  Future<void> init() async {
    if (!supported) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    await _ensureChannel();
    await _prepareLargeIcon();
  }

  /// 알람 채널을 실제로 만들어 둔다.
  ///
  /// 예약 시점에 자동 생성되기를 기다리지 않고 앱 시작 때 확실히 만들어야
  /// 소리·중요도가 의도대로 굳는다. 예전 채널은 지워서 설정 목록도 깔끔하게 유지.
  Future<void> _ensureChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      for (final old in _oldChannelIds) {
        await android.deleteNotificationChannel(channelId: old);
      }
      await android.createNotificationChannel(_channel);
      await android.createNotificationChannel(_silentChannel);
    } catch (e) {
      debugPrint('알람 채널 준비 실패(무시): $e');
    }
  }

  /// 권한 요청 (Android 13+, iOS)
  Future<void> requestPermissions() async {
    if (!supported) return;
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
    if (!supported) return;
    final notices = planNotices(routines, certs, settings);
    try {
      // 마감 알림 슬롯(1..maxPending)과 그 잔여 알림만 지운다.
      // cancelAll()을 쓰면 타이머 완료 알림·알람 테스트까지 함께 날아가서,
      // 예약해 둔 알람이 앱을 다시 열자마자 조용히 사라진다.
      for (var id = 1; id <= _maxPending; id++) {
        await _plugin.cancel(id: id);
        await _plugin.cancel(id: _residualBase + id);
      }
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
        // 나쁜 버릇 교정: 최근 연속으로 놓친 횟수만큼 마감 전 알람을 늘린다.
        // 0회=기본, 1회=+2시간 전, 2회=+3시간 전 … (놓칠수록 더 자주 압박)
        final missStreak = _recentMissStreak(r, day, today, certifiedKeys);
        final offsets = <int>{...settings.activeOffsets};
        for (var k = 1; k <= missStreak; k++) {
          offsets.add(60 * (k + 1)); // 2h, 3h, 4h… 전 슬롯 추가
        }
        for (final offset in offsets) {
          final when = deadline.subtract(Duration(minutes: offset));
          if (when.isAfter(ref)) {
            notices.add(
                _notice(r, day, when, offsetMin: offset, missStreak: missStreak));
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

  /// 이 의무일 직전까지 '연속으로 놓친 의무일 수'. 인증한 의무일을 만나면 끊긴다.
  /// (알람 폭주 방지를 위해 최대 5로 캡)
  int _recentMissStreak(
      Routine r, DateTime day, DateTime today, Set<String> certifiedKeys) {
    var streak = 0;
    var d = day.subtract(const Duration(days: 1));
    while (!d.isBefore(r.startDate)) {
      // '놓쳤다'는 마감이 지난 날만 — 오늘은 아직 인증 기회가 남아 있으므로 제외
      if (d.isBefore(today) && r.isDutyDay(d)) {
        if (certifiedKeys.contains('${r.id}|${dateKeyOf(d)}')) break;
        streak++;
        if (streak >= 5) break;
      }
      d = d.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 예약 항목 하나의 제목·본문을 만든다.
  PlannedNotice _notice(Routine r, DateTime day, DateTime when,
      {int? offsetMin, String? customLabel, int missStreak = 0}) {
    final label = customLabel ??
        switch (offsetMin) {
          240 => '마감 4시간 전',
          180 => '마감 3시간 전',
          120 => '마감 2시간 전',
          60 => '마감 1시간 전',
          _ => '마감 30분 전',
        };
    // 이 알림 시점 기준으로 마감까지 남은 시간을 "N시간 M분"으로 명시
    final deadline = r.deadlineOf(day);
    final remain = deadline.difference(when);
    final remainText = _remainLabel(remain);
    // 연속으로 놓쳤으면 압박 문구 (나쁜 버릇 교정)
    final streakTail = missStreak > 0 ? ' 벌써 $missStreak번 놓쳤어요!' : '';
    return PlannedNotice(
      when: when,
      // 제목에 앱 이름을 박는다 — 삼성 등은 헤드업에서 앱 이름을 숨겨서,
      // 제목만으로 "어느 앱의 알람인지"가 바로 보여야 한다.
      title: '⏰ 로그챌린지 — 마감까지 $remainText',
      body: "터치하면 알람이 꺼져요. '${r.title}' 오늘의 습관을 마무리하세요!"
          '$streakTail ($label)',
      // 알람(1분)이 끝난 뒤 조용히 남는 카드용 문구
      residualTitle: '📌 로그챌린지 — 아직 인증 전이에요',
      residualBody: "'${r.title}' 오늘의 습관을 마무리하세요! ($label)",
      // 알림을 펼쳤을 때 보이는 긴 문구 — 캐릭터가 말을 거는 톤으로
      bigText: _bigText(r, remainText, label, missStreak),
      routineId: r.id,
      dateKey: dateKeyOf(day),
      isMorningReminder: customLabel != null,
    );
  }

  /// 펼친 알림 본문. 굵게/줄바꿈이 되도록 간단한 HTML만 쓴다.
  static String _bigText(
      Routine r, String remainText, String label, int missStreak) {
    final b = StringBuffer()
      ..write('<b>${_escape(r.title)}</b><br>')
      ..write('마감까지 <b>$remainText</b> 남았어요. ($label)<br><br>');
    if (missStreak > 0) {
      b.write('연속 <b>$missStreak번</b> 놓쳤어요. 오늘은 꼭 도장 하나 찍고 가요!');
    } else {
      b.write('지금 인증하면 오늘 도장이 딱 찍힙니다. 1분이면 끝나요!');
    }
    return b.toString();
  }

  /// 루틴 제목에 <, >, & 가 있어도 알림이 깨지지 않게
  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// "N시간 M분" 형식 (알림 제목용)
  static String _remainLabel(Duration d) {
    if (d.inMinutes <= 0) return '0시간 0분';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h시간 $m분';
  }

  /// 알람 동작 확인용 — 10초 뒤에 실제와 똑같은 알람을 울린다.
  /// (앱을 끄거나 화면을 꺼도 울리는지 바로 확인할 수 있게 짧게 잡았다)
  static const testDelay = Duration(seconds: 10);

  /// 성공하면 null, 실패하면 화면에 보여줄 이유를 돌려준다.
  /// (예전엔 예외가 그대로 터져서 '아무 일도 안 일어나는' 것처럼 보였다)
  Future<String?> scheduleTestNotification() async {
    if (!supported) return '이 환경에서는 알람을 쓸 수 없어요';
    try {
      final when = tz.TZDateTime.now(tz.local).add(testDelay);
      await _schedule(
        id: 999999,
        title: '⏰ 로그챌린지 — 테스트 알람',
        body: '터치하면 알람이 꺼져요. 소리는 1분 뒤 저절로 멈춥니다.',
        when: when,
        bigText: '<b>알람 테스트</b><br>실제 마감 알람도 이렇게 울립니다.<br><br>'
            '터치하거나 <b>[알람 끄기]</b>를 누르면 바로 멈추고,<br>'
            '안 누르면 1분 뒤 저절로 멈춰요.',
      );
      // 알람이 끝난 뒤 남는 조용한 카드도 테스트에서 그대로 재현
      await _scheduleResidual(
        id: _residualBase + 999,
        title: '📌 로그챌린지 — 알람이 끝나면 이렇게 남아요',
        body: '소리·진동 없이 알림창에 조용히 남는 카드입니다.',
        when: when.add(_residualDelay),
        bigText: '알람(1분)이 끝나 사라져도 이 카드는 남습니다.<br>'
            '실제 마감 알람에서도 똑같이 동작해요.',
      );
      return null;
    } catch (e) {
      debugPrint('알람 테스트 예약 실패: $e');
      return '$e';
    }
  }

  /// 알람 하나 예약 — 내장 알람음을 못 찾으면 기본 알림음으로 한 번 더 시도한다.
  /// 소리를 잃더라도 알람이 통째로 사라지는 것보다는 낫다.
  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? bigText,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _alarmDetails(bigText: bigText),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
    } on PlatformException catch (e) {
      if (e.code != 'invalid_sound' || !_customSoundOk) rethrow;
      debugPrint('알람음을 찾지 못해 기본 알림음으로 전환합니다: ${e.message}');
      _customSoundOk = false;
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _alarmDetails(bigText: bigText),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
    }
  }

  /// 잔여 알림 예약 — 조용한 채널로, 정확도가 덜 중요해 일반 정확 모드를 쓴다.
  /// 실패해도 알람 본체에는 영향이 없도록 예외를 삼킨다.
  Future<void> _scheduleResidual({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? bigText,
  }) async {
    if (!_wantsResidual) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _silentDetails(bigText: bigText),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('잔여 알림 예약 실패(무시): $e');
    }
  }

  // 타이머 완료 알림 전용 ID (백그라운드에서 목표 시간을 채우면 울림)
  static const int _timerDoneId = 999998;
  static const int _timerDoneResidualId = 999996;

  /// 타이머가 [when]에 목표를 채우면 울릴 완료 알림을 예약한다.
  /// 앱이 꺼져 있어도 이 알림을 눌러 인증 화면으로 올 수 있다.
  Future<void> scheduleTimerDone(DateTime when, String title) async {
    if (!supported) return;
    try {
      final at = tz.TZDateTime.from(when, tz.local);
      await _schedule(
        id: _timerDoneId,
        title: '⏱️ 로그챌린지 — \'$title\' 목표 완료!',
        body: '터치하면 알람이 꺼져요. 오늘 도장을 찍어 주세요 🎉',
        when: at,
        bigText: '<b>${_escape(title)}</b><br>목표 시간을 다 채웠어요!<br><br>'
            '눌러서 오늘 도장을 찍어 주세요 🎉',
      );
      await _scheduleResidual(
        id: _timerDoneResidualId,
        title: '📌 로그챌린지 — \'$title\' 도장이 기다려요',
        body: '목표 시간을 다 채웠는데 아직 도장을 안 찍었어요.',
        when: at.add(_residualDelay),
        bigText: '<b>${_escape(title)}</b><br>목표 시간은 이미 다 채웠어요.<br><br>'
            '탭해서 오늘 도장을 찍어 주세요 🎉',
      );
    } catch (e) {
      debugPrint('타이머 완료 알림 예약 실패(무시): $e');
    }
  }

  Future<void> cancelTimerDone() async {
    if (!supported) return;
    try {
      await _plugin.cancel(id: _timerDoneId);
      await _plugin.cancel(id: _timerDoneResidualId);
    } catch (_) {/* 무시 */}
  }

  // 하루 단위 반복이 아니라 개별 예약이므로 matchDateTimeComponents 미사용
  Future<void> _scheduleOne(int id, PlannedNotice n) async {
    final at = tz.TZDateTime.from(n.when, tz.local);
    await _schedule(
      id: id,
      title: n.title,
      body: n.body,
      when: at,
      bigText: n.bigText,
    );
    // 알람(1분)이 끝나 사라진 뒤에도 조용한 카드로 남아 마감을 상기시킨다
    await _scheduleResidual(
      id: _residualBase + id,
      title: n.residualTitle ?? n.title.replaceFirst('⏰', '📌'),
      body: n.residualBody ?? n.body,
      when: at.add(_residualDelay),
      bigText: n.bigText,
    );
  }

  Future<void> cancelAll() async {
    if (!supported) return;
    await _plugin.cancelAll();
  }

  /// 알람이 울릴 수 있는 상태인지 스스로 점검한다.
  ///
  /// "알람이 안 울려요"는 원인이 여러 겹(알림 권한·정확 알람 권한·예약 0건)이라
  /// 눈으로 확인할 방법이 없으면 진단에 오래 걸린다. 앱 안에서 바로 보이게 한다.
  Future<AlarmStatus> diagnose() async {
    if (!supported) {
      return const AlarmStatus(
        notificationsAllowed: false,
        exactAlarmAllowed: false,
        pendingCount: 0,
        usingSystemAlarmSound: false,
      );
    }
    // 진단은 어디까지나 참고 정보 — 플러그인이 준비 안 된 환경(테스트 등)에서도
    // 화면이 죽지 않도록 조회 전체를 감싼다.
    var notifOk = true;
    var exactOk = true;
    var pending = 0;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      notifOk = await android?.areNotificationsEnabled() ?? true;
      exactOk = await android?.canScheduleExactNotifications() ?? true;
      // 마감 알람 슬롯만 센다 (잔여 알림·테스트·타이머 등 보조 예약은 제외)
      pending = (await _plugin.pendingNotificationRequests())
          .where((r) => r.id >= 1 && r.id <= _maxPending)
          .length;
    } catch (e) {
      debugPrint('알람 진단 실패(무시): $e');
    }
    return AlarmStatus(
      notificationsAllowed: notifOk,
      exactAlarmAllowed: exactOk,
      pendingCount: pending,
      usingSystemAlarmSound: _customSoundOk,
    );
  }
}

/// 알람 자가진단 결과
class AlarmStatus {
  final bool notificationsAllowed; // 알림 권한
  final bool exactAlarmAllowed; // 정확한 알람 권한(시간 맞춰 울리기)
  final int pendingCount; // 지금 예약돼 있는 알람 수
  final bool usingSystemAlarmSound; // 알람음이 정상인지(기본음으로 내려갔는지)

  const AlarmStatus({
    required this.notificationsAllowed,
    required this.exactAlarmAllowed,
    required this.pendingCount,
    required this.usingSystemAlarmSound,
  });

  bool get healthy =>
      notificationsAllowed && exactAlarmAllowed && usingSystemAlarmSound;

  /// 문제가 있으면 사용자가 바로 조치할 수 있는 문장으로
  List<String> get problems => [
        if (!notificationsAllowed) '알림 권한이 꺼져 있어요 — 휴대폰 설정에서 켜주세요',
        if (!exactAlarmAllowed) '"알람 및 리마인더" 권한이 꺼져 있어요 — 시간에 맞춰 울리려면 필요해요',
        if (!usingSystemAlarmSound) '알람음을 찾지 못해 기본 알림음으로 울려요',
      ];
}

/// 예약될 알림 하나의 설명 — reconcile 전에 계산되어 예약·테스트에 함께 쓰인다.
class PlannedNotice {
  final DateTime when;
  final String title;
  final String body;
  final String routineId;
  final String dateKey; // 이 알림이 붙은 의무일
  final bool isMorningReminder; // 결과형 아침 리마인더 여부
  final String? bigText; // 알림을 펼쳤을 때 보이는 긴 문구 (간단한 HTML)
  final String? residualTitle; // 알람 종료 후 남는 조용한 카드 제목
  final String? residualBody; // 알람 종료 후 남는 조용한 카드 본문

  const PlannedNotice({
    required this.when,
    required this.title,
    required this.body,
    required this.routineId,
    required this.dateKey,
    required this.isMorningReminder,
    this.bigText,
    this.residualTitle,
    this.residualBody,
  });
}
