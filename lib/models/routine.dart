import 'package:intl/intl.dart';

/// 챌린지 유형
enum RoutineType {
  accumulate, // 적립형: 매일 쌓기
  result, // 결과형: 목표 달성, 주 1회
}

/// 의무 인증 주기
enum DutyCycle {
  everyday, // 적립형 주7일 (매일)
  sixDays, // 적립형 주6일 (월~토)
  weeklySunday, // 결과형 매주 일요일
}

/// 검증(인증) 방식 — "스마트폰으로 모든 검증"
enum VerifyMethod {
  photo, // 사진 (날짜 워터마크)
  timer, // 앱 내 타이머 (n분 이상 측정)
  audio, // 녹음 (발음 연습 등)
  video, // 동영상 (명상·운동 장면)
  steps, // 걸음수 자동 검증 (Health Connect)
}

extension RoutineTypeLabel on RoutineType {
  String get label => switch (this) {
        RoutineType.accumulate => '적립형',
        RoutineType.result => '결과형',
      };
}

extension DutyCycleLabel on DutyCycle {
  String get label => switch (this) {
        DutyCycle.everyday => '매일 (주7일)',
        DutyCycle.sixDays => '월~토 (주6일)',
        DutyCycle.weeklySunday => '매주 일요일',
      };
}

extension VerifyMethodLabel on VerifyMethod {
  String get label => switch (this) {
        VerifyMethod.photo => '사진 인증',
        VerifyMethod.timer => '타이머 인증',
        VerifyMethod.audio => '녹음 인증',
        VerifyMethod.video => '동영상 인증',
        VerifyMethod.steps => '걸음수 인증',
      };

  String get description => switch (this) {
        VerifyMethod.photo => '실행 장면을 촬영 — 날짜·시각 워터마크 자동',
        VerifyMethod.timer => '앱 타이머로 목표 시간 측정 (독서·명상·공부)',
        VerifyMethod.audio => '음성 녹음으로 남기기 (발음 연습·낭독)',
        VerifyMethod.video => '짧은 영상으로 남기기 (명상·운동 장면)',
        VerifyMethod.steps => '오늘 걸음수를 자동으로 확인 (삼성헬스·헬스커넥트)',
      };
}

String dateKeyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 하나의 루틴(습관 선언)
class Routine {
  final String id;
  final RoutineType type;
  final String title; // 메인 루틴 / 결과형 목표 이름
  final String reason; // 정한 이유 (선언)
  final DutyCycle dutyCycle;
  final String? backupTitle; // 적립형 백업 루틴 (선택)
  final String? targetValue; // 결과형 목표값 (구체적 수치)
  final DateTime createdAt;
  final VerifyMethod verifyMethod;
  final int timerMinutes; // 타이머 인증 목표(분)
  final int targetSteps; // 걸음수 인증 목표(보)
  final bool requireNote; // 소감/느낀점 필수 작성
  final int? windowStartMin; // 인증 가능 시작 시각 (자정 기준 분, 예: 300 = 05:00)
  final int? windowEndMin; // 인증 마감 시각 — 설정 시 이 시각이 그날의 마감이 된다
  final DateTime startDate; // 시즌 시작일 (날짜만)
  final DateTime endDate; // 완료 목표일 (기본: 시작 +62일 = 63일간)
  int changeUsedCount; // 루틴 변경 찬스 사용 횟수 (0 또는 1)

  Routine({
    required this.id,
    required this.type,
    required this.title,
    required this.reason,
    required this.dutyCycle,
    this.backupTitle,
    this.targetValue,
    required this.createdAt,
    this.verifyMethod = VerifyMethod.photo,
    this.timerMinutes = 15,
    this.targetSteps = 6000,
    this.requireNote = false,
    this.windowStartMin,
    this.windowEndMin,
    DateTime? startDate,
    DateTime? endDate,
    this.changeUsedCount = 0,
  })  : startDate = _dateOnly(startDate ?? createdAt),
        endDate = _dateOnly(
            endDate ?? (startDate ?? createdAt).add(const Duration(days: 62)));

  /// 해당 날짜가 이 루틴의 '의무 인증일'인지 (시즌 기간 내에서만)
  bool isDutyDay(DateTime date) {
    final d = _dateOnly(date);
    if (d.isBefore(startDate) || d.isAfter(endDate)) return false;
    // DateTime.weekday: 월=1 ... 일=7
    return switch (dutyCycle) {
      DutyCycle.everyday => true,
      DutyCycle.sixDays => date.weekday != DateTime.sunday,
      DutyCycle.weeklySunday => date.weekday == DateTime.sunday,
    };
  }

  /// 오늘 인증을 '할 수 있는' 날인지 — 결과형은 주중 언제든 미리 인증 가능
  bool canCertifyOn(DateTime date) {
    final d = _dateOnly(date);
    if (d.isBefore(startDate) || d.isAfter(endDate)) return false;
    if (dutyCycle == DutyCycle.weeklySunday) return true; // 주중 아무 때나
    return isDutyDay(date);
  }

  /// 인증이 카운트되는 의무일 — 결과형은 그 주 일요일, 나머지는 그날
  DateTime dutyKeyDate(DateTime date) {
    final d = _dateOnly(date);
    if (dutyCycle != DutyCycle.weeklySunday) return d;
    final sunday = d.add(Duration(days: DateTime.sunday - d.weekday));
    // 주 마감(일요일)이 시즌 종료일을 넘으면 종료일로 캡
    return sunday.isAfter(endDate) ? endDate : sunday;
  }

  /// 시즌이 끝났는지
  bool isEnded(DateTime today) => _dateOnly(today).isAfter(endDate);

  /// 완료일까지 남은 일수 (오늘 포함 안 함, 지났으면 음수)
  int daysLeft(DateTime today) => endDate.difference(_dateOnly(today)).inDays;

  /// 시즌 전체 의무 인증일 수
  int totalDutyDays() {
    var n = 0;
    for (var d = startDate;
        !d.isAfter(endDate);
        d = d.add(const Duration(days: 1))) {
      if (isDutyDay(d)) n++;
    }
    return n;
  }

  /// 인증 시간대 제한 여부 (일찍 일어나기 등)
  bool get hasWindow => windowStartMin != null && windowEndMin != null;

  /// 지금이 인증 가능 시간대인지
  bool isWithinWindow(DateTime t) {
    if (!hasWindow) return true;
    final min = t.hour * 60 + t.minute;
    return min >= windowStartMin! && min <= windowEndMin!;
  }

  static String _fmtMin(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// "05:00~08:00" 형식 라벨
  String get windowLabel =>
      hasWindow ? '${_fmtMin(windowStartMin!)}~${_fmtMin(windowEndMin!)}' : '';

  /// 해당 날짜의 마감 시각 — 시간대 제한이 있으면 그 마감, 없으면 23:59
  DateTime deadlineOf(DateTime date) => hasWindow
      ? DateTime(date.year, date.month, date.day, windowEndMin! ~/ 60,
          windowEndMin! % 60)
      : DateTime(date.year, date.month, date.day, 23, 59, 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'reason': reason,
        'dutyCycle': dutyCycle.name,
        'backupTitle': backupTitle,
        'targetValue': targetValue,
        'createdAt': createdAt.toIso8601String(),
        'verifyMethod': verifyMethod.name,
        'timerMinutes': timerMinutes,
        'targetSteps': targetSteps,
        'requireNote': requireNote,
        'windowStartMin': windowStartMin,
        'windowEndMin': windowEndMin,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'changeUsedCount': changeUsedCount,
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'] as String,
        type: RoutineType.values.byName(j['type'] as String),
        title: j['title'] as String,
        reason: j['reason'] as String? ?? '',
        dutyCycle: DutyCycle.values.byName(j['dutyCycle'] as String),
        backupTitle: j['backupTitle'] as String?,
        targetValue: j['targetValue'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        verifyMethod: j['verifyMethod'] != null
            ? VerifyMethod.values.byName(j['verifyMethod'] as String)
            : VerifyMethod.photo,
        timerMinutes: (j['timerMinutes'] as num?)?.toInt() ?? 15,
        targetSteps: (j['targetSteps'] as num?)?.toInt() ?? 6000,
        requireNote: j['requireNote'] as bool? ?? false,
        windowStartMin: (j['windowStartMin'] as num?)?.toInt(),
        windowEndMin: (j['windowEndMin'] as num?)?.toInt(),
        startDate: j['startDate'] != null
            ? DateTime.parse(j['startDate'] as String)
            : null,
        endDate: j['endDate'] != null
            ? DateTime.parse(j['endDate'] as String)
            : null,
        changeUsedCount: (j['changeUsedCount'] as num?)?.toInt() ?? 0,
      );
}

/// 인증 기록 1건
class Certification {
  final String id;
  final String routineId;
  final String dateKey; // 이 인증이 카운트되는 의무일 (yyyy-MM-dd)
  final String photoPath; // 워터마크 처리된 사진 경로 (없으면 '')
  final String memo;
  final String? progressValue; // 결과형 진행 수치
  final DateTime timestamp; // 실제 인증 시각 (판정 기준)
  final bool isBackup; // 적립형 백업으로 인증했는지
  final String verifyMethod; // 인증에 사용한 검증 방식 (photo/timer/audio)
  final int? durationSec; // 타이머 인증: 측정 시간(초)
  final String? audioPath; // 녹음 인증: 음성 파일 경로
  final String? videoPath; // 동영상 인증: 영상 파일 경로
  final int? steps; // 걸음수 인증: 확인된 오늘 걸음수

  Certification({
    required this.id,
    required this.routineId,
    required this.dateKey,
    required this.photoPath,
    required this.memo,
    this.progressValue,
    required this.timestamp,
    this.isBackup = false,
    this.verifyMethod = 'photo',
    this.durationSec,
    this.audioPath,
    this.videoPath,
    this.steps,
  });

  bool get hasPhoto => photoPath.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'routineId': routineId,
        'dateKey': dateKey,
        'photoPath': photoPath,
        'memo': memo,
        'progressValue': progressValue,
        'timestamp': timestamp.toIso8601String(),
        'isBackup': isBackup,
        'verifyMethod': verifyMethod,
        'durationSec': durationSec,
        'audioPath': audioPath,
        'videoPath': videoPath,
        'steps': steps,
      };

  factory Certification.fromJson(Map<String, dynamic> j) => Certification(
        id: j['id'] as String,
        routineId: j['routineId'] as String,
        dateKey: j['dateKey'] as String,
        photoPath: j['photoPath'] as String? ?? '',
        memo: j['memo'] as String? ?? '',
        progressValue: j['progressValue'] as String?,
        timestamp: DateTime.parse(j['timestamp'] as String),
        isBackup: j['isBackup'] as bool? ?? false,
        verifyMethod: j['verifyMethod'] as String? ?? 'photo',
        durationSec: (j['durationSec'] as num?)?.toInt(),
        audioPath: j['audioPath'] as String?,
        videoPath: j['videoPath'] as String?,
        steps: (j['steps'] as num?)?.toInt(),
      );
}
