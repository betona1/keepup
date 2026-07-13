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

String dateKeyOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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
    this.changeUsedCount = 0,
  });

  /// 해당 날짜가 이 루틴의 '의무 인증일'인지
  bool isDutyDay(DateTime date) {
    // DateTime.weekday: 월=1 ... 일=7
    return switch (dutyCycle) {
      DutyCycle.everyday => true,
      DutyCycle.sixDays => date.weekday != DateTime.sunday,
      DutyCycle.weeklySunday => date.weekday == DateTime.sunday,
    };
  }

  /// 해당 날짜의 마감 시각 (그날 23:59:00)
  DateTime deadlineOf(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'reason': reason,
        'dutyCycle': dutyCycle.name,
        'backupTitle': backupTitle,
        'targetValue': targetValue,
        'createdAt': createdAt.toIso8601String(),
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
        changeUsedCount: (j['changeUsedCount'] as num?)?.toInt() ?? 0,
      );
}

/// 인증 기록 1건
class Certification {
  final String id;
  final String routineId;
  final String dateKey; // 이 인증이 카운트되는 의무일 (yyyy-MM-dd)
  final String photoPath; // 워터마크 처리된 사진 경로
  final String memo;
  final String? progressValue; // 결과형 진행 수치
  final DateTime timestamp; // 실제 인증 시각 (판정 기준)
  final bool isBackup; // 적립형 백업으로 인증했는지

  Certification({
    required this.id,
    required this.routineId,
    required this.dateKey,
    required this.photoPath,
    required this.memo,
    this.progressValue,
    required this.timestamp,
    this.isBackup = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'routineId': routineId,
        'dateKey': dateKey,
        'photoPath': photoPath,
        'memo': memo,
        'progressValue': progressValue,
        'timestamp': timestamp.toIso8601String(),
        'isBackup': isBackup,
      };

  factory Certification.fromJson(Map<String, dynamic> j) => Certification(
        id: j['id'] as String,
        routineId: j['routineId'] as String,
        dateKey: j['dateKey'] as String,
        photoPath: j['photoPath'] as String,
        memo: j['memo'] as String? ?? '',
        progressValue: j['progressValue'] as String?,
        timestamp: DateTime.parse(j['timestamp'] as String),
        isBackup: j['isBackup'] as bool? ?? false,
      );
}
