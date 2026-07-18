/// 알림 설정 (전역) — 혼자 쓰는 앱이라 루틴별이 아닌 앱 전체 하나의 설정.
///
/// · 아침 리마인더 시각: 결과형 마감 D-3부터 매일 이 시각에 알림
/// · 마감 임박 슬롯: 마감 3시간/1시간/30분 전 알림 각각 on/off
class NotifSettings {
  final int morningHour; // 0~23
  final int morningMinute; // 0~59
  final bool slot180; // 마감 3시간 전
  final bool slot60; // 마감 1시간 전
  final bool slot30; // 마감 30분 전

  const NotifSettings({
    this.morningHour = 9,
    this.morningMinute = 0,
    this.slot180 = true,
    this.slot60 = true,
    this.slot30 = true,
  });

  static const defaults = NotifSettings();

  /// 활성화된 마감 임박 오프셋(분) — 큰 값(먼저 울릴 것)부터
  List<int> get activeOffsets => [
        if (slot180) 180,
        if (slot60) 60,
        if (slot30) 30,
      ];

  /// "09:00" 형식
  String get morningLabel =>
      '${morningHour.toString().padLeft(2, '0')}:${morningMinute.toString().padLeft(2, '0')}';

  bool slotEnabled(int offsetMin) => switch (offsetMin) {
        180 => slot180,
        60 => slot60,
        _ => slot30,
      };

  NotifSettings copyWith({
    int? morningHour,
    int? morningMinute,
    bool? slot180,
    bool? slot60,
    bool? slot30,
  }) =>
      NotifSettings(
        morningHour: morningHour ?? this.morningHour,
        morningMinute: morningMinute ?? this.morningMinute,
        slot180: slot180 ?? this.slot180,
        slot60: slot60 ?? this.slot60,
        slot30: slot30 ?? this.slot30,
      );

  Map<String, dynamic> toJson() => {
        'morningHour': morningHour,
        'morningMinute': morningMinute,
        'slot180': slot180,
        'slot60': slot60,
        'slot30': slot30,
      };

  factory NotifSettings.fromJson(Map<String, dynamic> j) => NotifSettings(
        morningHour: (j['morningHour'] as num?)?.toInt() ?? 9,
        morningMinute: (j['morningMinute'] as num?)?.toInt() ?? 0,
        slot180: j['slot180'] as bool? ?? true,
        slot60: j['slot60'] as bool? ?? true,
        slot30: j['slot30'] as bool? ?? true,
      );
}
