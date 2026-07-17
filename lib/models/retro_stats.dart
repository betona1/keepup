import 'routine.dart';

/// 회고 카드 도장 그리드의 칸 상태
class DayMark {
  static const outside = 0; // 시즌 밖 (빈칸)
  static const rest = 1; // 쉬는 날 (의무 아님)
  static const upcoming = 2; // 아직 오지 않은 의무일
  static const missed = 3; // 놓친 의무일
  static const stamped = 4; // 도장 찍은 날
}

/// 시즌 회고 통계 — 루틴 하나의 여정을 숫자로 요약한다.
/// (기획서 3.4: 시즌 종료 시 회고 카드 — 총 인증 n회 / 달성률 %)
class RetroStats {
  final Routine routine;
  final int totalDutyDays; // 시즌 전체 의무 인증일
  final int certifiedDays; // 도장 찍은 의무일 수
  final int percent; // 달성률 (0~100)
  final int longestStreak; // 최장 연속 인증 (의무일 기준)
  final int missedDays; // 놓친 의무일 (오늘 이전)
  final int backupCount; // 백업 루틴으로 인증한 횟수
  final int totalCerts; // 전체 인증 건수
  final int totalMinutes; // 타이머 인증 누적 시간(분)
  final int totalSteps; // 걸음수 인증 누적 걸음
  final DateTime? firstCertAt;
  final DateTime? lastCertAt;
  final List<Certification> photoCerts; // 대표 사진 (최신순)
  final List<int> dayMarks; // 월요일 시작으로 정렬된 시즌 전체 칸 (7의 배수)
  final bool ended;

  const RetroStats({
    required this.routine,
    required this.totalDutyDays,
    required this.certifiedDays,
    required this.percent,
    required this.longestStreak,
    required this.missedDays,
    required this.backupCount,
    required this.totalCerts,
    required this.totalMinutes,
    required this.totalSteps,
    required this.firstCertAt,
    required this.lastCertAt,
    required this.photoCerts,
    required this.dayMarks,
    required this.ended,
  });

  /// 시즌 전체 일수 (시작·종료일 포함)
  int get seasonDays => routine.endDate.difference(routine.startDate).inDays + 1;

  int get weeks => dayMarks.length ~/ 7;

  /// 타이머·걸음수처럼 카드에 자랑할 누적 수치가 있는지
  bool get hasTally => totalMinutes > 0 || totalSteps > 0;

  /// 누적 수치 한 줄 (예: "누적 12시간 30분", "누적 248,300보")
  String? get tallyLabel {
    if (totalSteps > 0) return '누적 ${_comma(totalSteps)}보';
    if (totalMinutes > 0) {
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      if (h > 0) return m > 0 ? '누적 $h시간 $m분' : '누적 $h시간';
      return '누적 $m분';
    }
    return null;
  }

  /// 달성 등급 도장 문구
  String get badge => switch (percent) {
        100 => 'PERFECT',
        >= 90 => 'GREAT',
        >= 70 => 'GOOD',
        >= 40 => 'KEEP',
        _ => 'START',
      };

  /// 카드 하단 한 줄 — 숫자 대신 감정을 남긴다
  String get headline => switch (percent) {
        100 => '단 하루도 빠지지 않았어요.\n이건 이제 습관이 아니라 나 자신입니다.',
        >= 90 => '거의 완벽한 시즌이었어요.\n놓친 며칠까지도 기록의 일부예요.',
        >= 70 => '꾸준함이 습관이 됐어요.\n$certifiedDays번의 도장이 그 증거입니다.',
        >= 40 => '절반의 여정을 지나왔어요.\n남은 절반은 더 쉬워집니다.',
        > 0 => '시작했고, 흔적을 남겼어요.\n작심삼일도 시작은 했으니까요.',
        _ => '아직 첫 도장이 없어요.\n오늘이 1일차가 될 수 있습니다.',
      };

  static String _comma(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
