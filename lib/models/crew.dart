import 'routine.dart';

/// 동호회(과제학습 그룹) 데이터 — 서버(log.keywordream.com/api/crews*) 응답 모델.
/// 날짜는 서버와 같은 'yyyy-MM-dd' 문자열을 그대로 쓴다.

enum CrewRole { leader, subleader, member }

extension CrewRoleLabel on CrewRole {
  String get label => switch (this) {
        CrewRole.leader => '반장',
        CrewRole.subleader => '부반장',
        CrewRole.member => '회원',
      };
  bool get isManager => this == CrewRole.leader || this == CrewRole.subleader;
}

CrewRole _role(Object? v) =>
    CrewRole.values.asNameMap()[v as String? ?? 'member'] ?? CrewRole.member;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime _day(String key) => DateTime.parse(key);

class ProStatus {
  final bool pro;
  final bool lifetime;
  final DateTime? expiresAt;
  final bool admin;
  final bool mainAdmin; // 메인 관리자(netkjy@gmail.com) — 키 발행·Pro 회원·동호회 전체 관리
  const ProStatus(
      {required this.pro,
      required this.lifetime,
      this.expiresAt,
      required this.admin,
      this.mainAdmin = false});

  static const none = ProStatus(pro: false, lifetime: false, admin: false);

  factory ProStatus.fromJson(Map<String, dynamic> j) => ProStatus(
        pro: j['pro'] == true,
        lifetime: j['lifetime'] == true,
        expiresAt: j['expiresAt'] == null
            ? null
            : DateTime.tryParse(j['expiresAt'] as String)?.toLocal(),
        admin: j['admin'] == true,
        mainAdmin: j['mainAdmin'] == true,
      );
}

class ProKey {
  final int id;
  final String code;
  final int? durationDays;
  final int maxUses;
  final int usedCount;
  final String? note;
  final DateTime createdAt;
  final bool revoked;
  const ProKey({
    required this.id,
    required this.code,
    this.durationDays,
    required this.maxUses,
    required this.usedCount,
    this.note,
    required this.createdAt,
    required this.revoked,
  });

  String get durationLabel =>
      durationDays == null ? '평생' : '$durationDays일';

  factory ProKey.fromJson(Map<String, dynamic> j) => ProKey(
        id: _int(j['id']),
        code: j['code'] as String,
        durationDays: (j['durationDays'] as num?)?.toInt(),
        maxUses: _int(j['maxUses']),
        usedCount: _int(j['usedCount']),
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        revoked: j['revoked'] == true,
      );
}

class CrewSummary {
  final int id;
  final String name;
  final String? description;
  final String startDate;
  final String endDate;
  final CrewRole myRole;
  final int memberCount;
  final String? inviteCode;
  const CrewSummary({
    required this.id,
    required this.name,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.myRole,
    required this.memberCount,
    this.inviteCode,
  });

  factory CrewSummary.fromJson(Map<String, dynamic> j) => CrewSummary(
        id: _int(j['id']),
        name: j['name'] as String,
        description: j['description'] as String?,
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        myRole: _role(j['myRole']),
        memberCount: _int(j['memberCount']),
        inviteCode: j['inviteCode'] as String?,
      );
}

class CrewInfo {
  final int id;
  final String name;
  final String? description;
  final String startDate;
  final String endDate;
  final int fineAmount;
  final int fineCap;
  final bool leaderExempt;
  final String? inviteCode;
  const CrewInfo({
    required this.id,
    required this.name,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.fineAmount,
    required this.fineCap,
    required this.leaderExempt,
    this.inviteCode,
  });

  factory CrewInfo.fromJson(Map<String, dynamic> j) => CrewInfo(
        id: _int(j['id']),
        name: j['name'] as String,
        description: j['description'] as String?,
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        fineAmount: _int(j['fineAmount']),
        fineCap: _int(j['fineCap']),
        leaderExempt: j['leaderExempt'] != false,
        inviteCode: j['inviteCode'] as String?,
      );
}

class CrewMember {
  final int id;
  final String displayName;
  final CrewRole role;
  final bool offline; // 앱 미설치 — 부반장이 대신 체크
  final String? note;
  final String joinedAt;
  final String? avatarUrl;
  final bool isMe;
  const CrewMember({
    required this.id,
    required this.displayName,
    required this.role,
    required this.offline,
    this.note,
    required this.joinedAt,
    this.avatarUrl,
    required this.isMe,
  });

  factory CrewMember.fromJson(Map<String, dynamic> j) => CrewMember(
        id: _int(j['id']),
        displayName: j['displayName'] as String? ?? '',
        role: _role(j['role']),
        offline: j['offline'] == true,
        note: j['note'] as String?,
        joinedAt: j['joinedAt'] as String,
        avatarUrl: j['avatarUrl'] as String?,
        isMe: j['isMe'] == true,
      );
}

/// 동호회 공통 과제 — 앱 Routine과 같은 규칙을 쓴다.
/// 동호회 과제 유형 — 인증형(매일 인증) / 과제 점검형(양식 제출 → 운영진 점검)
enum CrewTaskKind { cert, assignment }

extension CrewTaskKindLabel on CrewTaskKind {
  String get label => switch (this) {
        CrewTaskKind.cert => '인증형',
        CrewTaskKind.assignment => '과제 점검형',
      };
}

class CrewTask {
  final int id;
  final int crewId;
  final String? crewName;
  final CrewTaskKind kind;
  final List<int> dueWeekdays; // 매주 마감 요일들 (목·일 = [4, 7])
  final int? deadlineMin; // 마감 시각 (null = 23:59)
  final ClassSchedule? classSchedule; // 요일별 수업 시작 + 마감 규칙

  /// 요일별 마감 분 (그 날 자정 기준, 음수 = 전날) — 개인 루틴 알람·도장에 그대로 쓴다
  Map<int, int> get dueTimes => classSchedule?.dueTimes ?? const {};
  final List<FormItem> form; // 과제 점검형 기본 제출 양식
  final RoutineType type;
  final String title;
  final String reason;
  final DutyCycle dutyCycle;
  final int dueWeekday;
  final String? targetValue;
  final String? backupTitle;
  final VerifyMethod verifyMethod;
  final int timerMinutes;
  final bool requireNote;
  final int? windowStartMin;
  final int? windowEndMin;
  final String startDate;
  final String endDate;
  final bool archived;
  final String? myJoinedAt;

  const CrewTask({
    required this.id,
    required this.crewId,
    this.crewName,
    this.kind = CrewTaskKind.cert,
    this.dueWeekdays = const [],
    this.deadlineMin,
    this.classSchedule,
    this.form = const [],
    required this.type,
    required this.title,
    required this.reason,
    required this.dutyCycle,
    required this.dueWeekday,
    this.targetValue,
    this.backupTitle,
    required this.verifyMethod,
    required this.timerMinutes,
    required this.requireNote,
    this.windowStartMin,
    this.windowEndMin,
    required this.startDate,
    required this.endDate,
    required this.archived,
    this.myJoinedAt,
  });

  factory CrewTask.fromJson(Map<String, dynamic> j) => CrewTask(
        id: _int(j['id']),
        crewId: _int(j['crewId']),
        crewName: j['crewName'] as String?,
        kind: j['kind'] == 'assignment'
            ? CrewTaskKind.assignment
            : CrewTaskKind.cert,
        dueWeekdays: ((j['dueWeekdays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        deadlineMin: (j['deadlineMin'] as num?)?.toInt(),
        classSchedule: j['classSchedule'] == null
            ? null
            : ClassSchedule.fromJson(j['classSchedule'] as Map<String, dynamic>),
        form: FormItem.listFrom(j['form']),
        type: RoutineType.values.byName(j['type'] as String),
        title: j['title'] as String,
        reason: j['reason'] as String? ?? '',
        dutyCycle: DutyCycle.values.byName(j['dutyCycle'] as String),
        dueWeekday: _int(j['dueWeekday']),
        targetValue: j['targetValue'] as String?,
        backupTitle: j['backupTitle'] as String?,
        verifyMethod: VerifyMethod.values.asNameMap()[j['verifyMethod']] ??
            VerifyMethod.photo,
        timerMinutes: _int(j['timerMinutes']),
        requireNote: j['requireNote'] == true,
        windowStartMin: (j['windowStartMin'] as num?)?.toInt(),
        windowEndMin: (j['windowEndMin'] as num?)?.toInt(),
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        archived: j['archived'] == true,
        myJoinedAt: j['myJoinedAt'] as String?,
      );

  bool get isAssignment => kind == CrewTaskKind.assignment;

  /// "매주 목·일 23:59 마감" 같은 마감 라벨
  String get scheduleLabel {
    final time = fmtMinute(deadlineMin ?? 23 * 60 + 59);
    final days = dueWeekdays.isEmpty ? [dueWeekday] : dueWeekdays;
    // 수업 시간표가 있으면 "매주 목 19:30·일 15:00 수업 · 1분 전 마감"
    final cs = classSchedule;
    if (dutyCycle == DutyCycle.weekly && cs != null && cs.days.isNotEmpty) {
      final classes = days
          .where((d) => cs.days[d] != null)
          .map((d) => '${weekdayNames[d - 1]} ${fmtMinute(cs.days[d]!)}')
          .join('·');
      return '매주 $classes 수업 · ${cs.ruleLabel}';
    }
    return switch (dutyCycle) {
      DutyCycle.weekly =>
        '매주 ${days.map((d) => weekdayNames[d - 1]).join('·')} $time 마감',
      DutyCycle.every15days => '15일마다 $time 마감',
      DutyCycle.once => '${endDate.replaceAll('-', '.')} $time 마감',
      _ => '${dutyCycle.label} $time 마감',
    };
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'dueWeekdays': dueWeekdays,
        'deadlineMin': deadlineMin,
        'classSchedule': classSchedule?.toJson(),
        if (isAssignment) 'form': form.map((f) => f.toJson()).toList(),
        'type': type.name,
        'title': title,
        'reason': reason,
        'dutyCycle': dutyCycle.name,
        'dueWeekday': dueWeekday,
        'targetValue': targetValue,
        'backupTitle': backupTitle,
        'verifyMethod': verifyMethod.name,
        'timerMinutes': timerMinutes,
        'requireNote': requireNote,
        'windowStartMin': windowStartMin,
        'windowEndMin': windowEndMin,
        'startDate': startDate,
        'endDate': endDate,
      };

  /// 개인 루틴 id — 같은 과제는 늘 같은 루틴으로 연결된다
  static String routineIdFor(int taskId) => 'crew-$taskId';

  /// 개인 루틴으로 변환. [existing]이 있으면 아이콘·생성일 등 개인 정보는 이어받는다.
  ///
  /// 시작일: 늦게 들어온 회원은 가입일부터 의무가 시작된다(서버 통계와 같게).
  /// 단 15일 주기는 시작일이 주기 기준점이라 과제 시작일을 그대로 둔다 — 바꾸면
  /// 앱과 서버의 마감일이 어긋난다.
  Routine toRoutine({Routine? existing}) {
    var start = _day(startDate);
    final joined = myJoinedAt == null ? null : _day(myJoinedAt!);
    if (dutyCycle != DutyCycle.every15days &&
        joined != null &&
        joined.isAfter(start)) {
      start = joined;
    }
    final end = _day(endDate);
    if (start.isAfter(end)) start = end;
    return Routine(
      id: routineIdFor(id),
      type: type,
      title: title,
      reason: reason,
      dutyCycle: dutyCycle,
      backupTitle: backupTitle,
      targetValue: targetValue,
      createdAt: existing?.createdAt ?? DateTime.now(),
      verifyMethod: verifyMethod,
      timerMinutes: timerMinutes,
      dueWeekday: dueWeekday,
      dueWeekdays: dueWeekdays,
      deadlineMin: deadlineMin,
      dueDeadlines: dueTimes,
      mediaSource: existing?.mediaSource,
      requireNote: requireNote,
      windowStartMin: windowStartMin,
      windowEndMin: windowEndMin,
      startDate: start,
      endDate: end,
      iconPath: existing?.iconPath,
      crewId: crewId,
      crewTaskId: id,
      crewName: crewName,
      crewAssignment: isAssignment,
    );
  }
}

/// 수업 시간표 — 요일별 수업 시작 시각과 마감 규칙 (서버 duty.ts ClassSchedule과 같다)
///  - before: 수업 시작 [minutes]분 전 마감
///  - prevDay: 수업 전날 [time](기본 23:59) 마감
class ClassSchedule {
  final Map<int, int> days; // {4: 1170} = 목 19:30
  final String rule; // before | prevDay
  final int minutes;
  final int time;
  const ClassSchedule({
    required this.days,
    this.rule = 'before',
    this.minutes = 1,
    this.time = 23 * 60 + 59,
  });

  bool get prevDay => rule == 'prevDay';

  /// 요일별 마감 분 (그 날 자정 기준, 음수 = 전날: -1 = 전날 23:59)
  Map<int, int> get dueTimes => {
        for (final e in days.entries)
          e.key: prevDay ? time - 1440 : e.value - minutes,
      };

  String get ruleLabel =>
      prevDay ? '수업 전날 ${fmtMinute(time)} 마감' : '수업 $minutes분 전 마감';

  factory ClassSchedule.fromJson(Map<String, dynamic> j) => ClassSchedule(
        days: {
          for (final e in ((j['days'] as Map?) ?? const {}).entries)
            int.parse('${e.key}'): (e.value as num).toInt()
        },
        rule: j['rule'] == 'prevDay' ? 'prevDay' : 'before',
        minutes: (j['minutes'] as num?)?.toInt() ?? 1,
        time: (j['time'] as num?)?.toInt() ?? 23 * 60 + 59,
      );

  Map<String, dynamic> toJson() => {
        'days': {for (final e in days.entries) '${e.key}': e.value},
        'rule': rule,
        'minutes': minutes,
        'time': time,
      };
}

/// 자정 기준 분 → "21:00"
String fmtMinute(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// 과제 점검형 제출 양식의 항목 — 반장·부반장이 골라 꾸민다
enum FormItemType { text, question, photo, file, audio, link, number }

extension FormItemTypeLabel on FormItemType {
  String get label => switch (this) {
        FormItemType.text => '글',
        FormItemType.question => '문항 답변',
        FormItemType.photo => '사진',
        FormItemType.file => '자료 파일',
        FormItemType.audio => '녹음',
        FormItemType.link => '링크',
        FormItemType.number => '수치',
      };
  bool get isFile =>
      this == FormItemType.photo ||
      this == FormItemType.file ||
      this == FormItemType.audio;
}

class FormItem {
  final String id;
  final FormItemType type;
  final String label;
  final bool required;
  final int? minChars;
  final String? unit;
  final int? maxFiles;
  const FormItem({
    required this.id,
    required this.type,
    required this.label,
    this.required = true,
    this.minChars,
    this.unit,
    this.maxFiles,
  });

  FormItem copyWith(
          {FormItemType? type,
          String? label,
          bool? required,
          int? minChars,
          String? unit,
          int? maxFiles}) =>
      FormItem(
        id: id,
        type: type ?? this.type,
        label: label ?? this.label,
        required: required ?? this.required,
        minChars: minChars ?? this.minChars,
        unit: unit ?? this.unit,
        maxFiles: maxFiles ?? this.maxFiles,
      );

  factory FormItem.fromJson(Map<String, dynamic> j) => FormItem(
        id: j['id'] as String,
        type: FormItemType.values.asNameMap()[j['type']] ?? FormItemType.text,
        label: j['label'] as String? ?? '',
        required: j['required'] != false,
        minChars: (j['minChars'] as num?)?.toInt(),
        unit: j['unit'] as String?,
        maxFiles: (j['maxFiles'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        'required': required,
        if (minChars != null) 'minChars': minChars,
        if (unit != null && unit!.isNotEmpty) 'unit': unit,
        if (maxFiles != null) 'maxFiles': maxFiles,
      };

  static List<FormItem> listFrom(Object? v) =>
      (v as List?)
          ?.map((e) => FormItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [];
}


class CrewDetail {
  final CrewInfo crew;
  final CrewMember me;
  final List<CrewMember> members;
  final List<CrewTask> tasks;
  final String today;
  const CrewDetail({
    required this.crew,
    required this.me,
    required this.members,
    required this.tasks,
    required this.today,
  });

  factory CrewDetail.fromJson(Map<String, dynamic> j) => CrewDetail(
        crew: CrewInfo.fromJson(j['crew'] as Map<String, dynamic>),
        me: CrewMember.fromJson(j['me'] as Map<String, dynamic>),
        members: (j['members'] as List)
            .map((e) => CrewMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        tasks: (j['tasks'] as List)
            .map((e) => CrewTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        today: j['today'] as String,
      );
}

enum SlotStatus { submitted, approved, rejected, excused, missed, pending }

extension SlotStatusLabel on SlotStatus {
  String get label => switch (this) {
        SlotStatus.submitted => '제출',
        SlotStatus.approved => '확인',
        SlotStatus.rejected => '보완 요청',
        SlotStatus.excused => '인정',
        SlotStatus.missed => '미제출',
        SlotStatus.pending => '대기',
      };
  bool get isDone =>
      this == SlotStatus.submitted ||
      this == SlotStatus.approved ||
      this == SlotStatus.excused;
}

class BoardEntry {
  final int memberId;
  final int? submissionId;
  final int fileCount;
  final String? reviewNote;
  final SlotStatus status;
  final String? memo;
  final String? progressValue;
  final String? verifyMethod;
  final int? durationSec;
  final String? linkUrl;
  final bool isBackup;
  final String? photoUrl;
  final DateTime? submittedAt;
  final bool byManager;
  const BoardEntry({
    required this.memberId,
    this.submissionId,
    this.fileCount = 0,
    this.reviewNote,
    required this.status,
    this.memo,
    this.progressValue,
    this.verifyMethod,
    this.durationSec,
    this.linkUrl,
    required this.isBackup,
    this.photoUrl,
    this.submittedAt,
    required this.byManager,
  });

  factory BoardEntry.fromJson(Map<String, dynamic> j) => BoardEntry(
        memberId: _int(j['memberId']),
        submissionId: (j['submissionId'] as num?)?.toInt(),
        fileCount: _int(j['fileCount']),
        reviewNote: j['reviewNote'] as String?,
        status: SlotStatus.values.byName(j['status'] as String),
        memo: j['memo'] as String?,
        progressValue: j['progressValue'] as String?,
        verifyMethod: j['verifyMethod'] as String?,
        durationSec: (j['durationSec'] as num?)?.toInt(),
        linkUrl: j['linkUrl'] as String?,
        isBackup: j['isBackup'] == true,
        photoUrl: j['photoUrl'] as String?,
        submittedAt: j['submittedAt'] == null
            ? null
            : DateTime.parse(j['submittedAt'] as String).toLocal(),
        byManager: j['byManager'] == true,
      );
}

class BoardTask {
  final CrewTask task;
  final String? sessionTitle; // 이번 회차 제목 (과제 점검형)
  final String dutyKey;
  final DateTime deadline;
  final List<BoardEntry> entries;
  const BoardTask({
    required this.task,
    this.sessionTitle,
    required this.dutyKey,
    required this.deadline,
    required this.entries,
  });

  int get doneCount => entries.where((e) => e.status.isDone).length;

  factory BoardTask.fromJson(Map<String, dynamic> j) => BoardTask(
        task: CrewTask.fromJson(j['task'] as Map<String, dynamic>),
        sessionTitle: j['sessionTitle'] as String?,
        dutyKey: j['dutyKey'] as String,
        deadline: DateTime.parse(j['deadline'] as String).toLocal(),
        entries: (j['entries'] as List)
            .map((e) => BoardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CrewBoard {
  final String date;
  final String today;
  final List<CrewMember> members;
  final List<BoardTask> tasks;
  const CrewBoard({
    required this.date,
    required this.today,
    required this.members,
    required this.tasks,
  });

  CrewMember? member(int id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  factory CrewBoard.fromJson(Map<String, dynamic> j) => CrewBoard(
        date: j['date'] as String,
        today: j['today'] as String,
        members: (j['members'] as List)
            .map((e) => CrewMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        tasks: (j['tasks'] as List)
            .map((e) => BoardTask.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MissedSlot {
  final int taskId;
  final String dateKey;
  const MissedSlot(this.taskId, this.dateKey);
}

class MemberStats {
  final CrewMember member;
  final int due;
  final int done;
  final int excused;
  final int missed;
  final int rate;
  final List<MissedSlot> missedList;
  const MemberStats({
    required this.member,
    required this.due,
    required this.done,
    required this.excused,
    required this.missed,
    required this.rate,
    required this.missedList,
  });

  factory MemberStats.fromJson(Map<String, dynamic> j) => MemberStats(
        member: CrewMember.fromJson(j),
        due: _int(j['due']),
        done: _int(j['done']),
        excused: _int(j['excused']),
        missed: _int(j['missed']),
        rate: _int(j['rate']),
        missedList: ((j['missedList'] as List?) ?? const [])
            .map((e) => MissedSlot(
                _int((e as Map)['taskId']), e['dateKey'] as String))
            .toList(),
      );
}

class CrewStats {
  final String from;
  final String to;
  final int overallRate;
  final Map<int, String> taskTitles;
  final List<MemberStats> members;
  const CrewStats({
    required this.from,
    required this.to,
    required this.overallRate,
    required this.taskTitles,
    required this.members,
  });

  factory CrewStats.fromJson(Map<String, dynamic> j) => CrewStats(
        from: j['from'] as String,
        to: j['to'] as String,
        overallRate: _int(j['overallRate']),
        taskTitles: {
          for (final t in (j['tasks'] as List))
            _int((t as Map)['id']): t['title'] as String,
        },
        members: (j['members'] as List)
            .map((e) => MemberStats.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SettlementLine {
  final CrewMember member;
  final int due;
  final int missed;
  final bool exempt;
  final int fine;
  final int finePaid;
  final int fineBalance;
  final bool winner;
  final int prize;
  final int prizePaid;
  const SettlementLine({
    required this.member,
    required this.due,
    required this.missed,
    required this.exempt,
    required this.fine,
    required this.finePaid,
    required this.fineBalance,
    required this.winner,
    required this.prize,
    required this.prizePaid,
  });

  factory SettlementLine.fromJson(Map<String, dynamic> j) => SettlementLine(
        member: CrewMember.fromJson(j),
        due: _int(j['due']),
        missed: _int(j['missed']),
        exempt: j['exempt'] == true,
        fine: _int(j['fine']),
        finePaid: _int(j['finePaid']),
        fineBalance: _int(j['fineBalance']),
        winner: j['winner'] == true,
        prize: _int(j['prize']),
        prizePaid: _int(j['prizePaid']),
      );
}

class CrewPayment {
  final int id;
  final int memberId;
  final String kind; // fine_paid | prize_paid | adjust
  final int amount;
  final String? memo;
  final DateTime createdAt;
  const CrewPayment({
    required this.id,
    required this.memberId,
    required this.kind,
    required this.amount,
    this.memo,
    required this.createdAt,
  });

  String get kindLabel => switch (kind) {
        'fine_paid' => '벌금 납부',
        'prize_paid' => '상금 지급',
        _ => '조정',
      };

  factory CrewPayment.fromJson(Map<String, dynamic> j) => CrewPayment(
        id: _int(j['id']),
        memberId: _int(j['memberId']),
        kind: j['kind'] as String,
        amount: _int(j['amount']),
        memo: j['memo'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class CrewSettlement {
  final String from;
  final String to;
  final int fineAmount;
  final int fineCap;
  final bool leaderExempt;
  final int pool;
  final int winnerCount;
  final int share;
  final bool canManage;
  final List<SettlementLine> lines;
  final List<CrewPayment> payments;
  const CrewSettlement({
    required this.from,
    required this.to,
    required this.fineAmount,
    required this.fineCap,
    required this.leaderExempt,
    required this.pool,
    required this.winnerCount,
    required this.share,
    required this.canManage,
    required this.lines,
    required this.payments,
  });

  factory CrewSettlement.fromJson(Map<String, dynamic> j) => CrewSettlement(
        from: j['from'] as String,
        to: j['to'] as String,
        fineAmount: _int(j['fineAmount']),
        fineCap: _int(j['fineCap']),
        leaderExempt: j['leaderExempt'] != false,
        pool: _int(j['pool']),
        winnerCount: _int(j['winnerCount']),
        share: _int(j['share']),
        canManage: j['canManage'] == true,
        lines: (j['lines'] as List)
            .map((e) => SettlementLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: (j['payments'] as List)
            .map((e) => CrewPayment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── 과제 점검형: 회차·제출 ──────────────────────────────────────────

/// 회차 내용 — 같은 과제라도 회차(마감일)마다 안내·양식이 다를 수 있다
class CrewSession {
  final String dateKey;
  final DateTime? deadline;
  final String? title;
  final String? guide;
  final bool customForm;
  final List<FormItem> form;
  const CrewSession({
    required this.dateKey,
    this.deadline,
    this.title,
    this.guide,
    required this.customForm,
    required this.form,
  });

  factory CrewSession.fromJson(Map<String, dynamic> j) => CrewSession(
        dateKey: j['dateKey'] as String,
        deadline: j['deadline'] == null
            ? null
            : DateTime.parse(j['deadline'] as String).toLocal(),
        title: j['title'] as String?,
        guide: j['guide'] as String?,
        customForm: j['customForm'] == true,
        form: FormItem.listFrom(j['form']),
      );
}

class SubmissionFile {
  final int id;
  final String itemId;
  final String kind; // photo | file | audio
  final String name;
  final int size;
  final String contentType;
  final String url;
  const SubmissionFile({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.name,
    required this.size,
    required this.contentType,
    required this.url,
  });

  String get sizeLabel => size < 1024 * 1024
      ? '${(size / 1024).toStringAsFixed(0)}KB'
      : '${(size / 1024 / 1024).toStringAsFixed(1)}MB';

  factory SubmissionFile.fromJson(Map<String, dynamic> j) => SubmissionFile(
        id: _int(j['id']),
        itemId: j['itemId'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String,
        size: _int(j['size']),
        contentType: j['contentType'] as String? ?? '',
        url: j['url'] as String,
      );
}

class CrewSubmission {
  final int id;
  final String dateKey;
  final String status; // submitted | excused
  final String? memo;
  final String? progressValue;
  final String? photoUrl;
  final String? linkUrl;
  final Map<String, dynamic> answers;
  final List<SubmissionFile> files;
  final DateTime submittedAt;
  final String? reviewStatus; // null | approved | rejected
  final String? reviewNote;
  const CrewSubmission({
    required this.id,
    required this.dateKey,
    required this.status,
    this.memo,
    this.progressValue,
    this.photoUrl,
    this.linkUrl,
    required this.answers,
    required this.files,
    required this.submittedAt,
    this.reviewStatus,
    this.reviewNote,
  });

  factory CrewSubmission.fromJson(Map<String, dynamic> j) => CrewSubmission(
        id: _int(j['id']),
        dateKey: j['dateKey'] as String,
        status: j['status'] as String,
        memo: j['memo'] as String?,
        progressValue: j['progressValue'] as String?,
        photoUrl: j['photoUrl'] as String?,
        linkUrl: j['linkUrl'] as String?,
        answers: (j['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
        files: ((j['files'] as List?) ?? const [])
            .map((e) => SubmissionFile.fromJson(e as Map<String, dynamic>))
            .toList(),
        submittedAt: DateTime.parse(j['submittedAt'] as String).toLocal(),
        reviewStatus: j['reviewStatus'] as String?,
        reviewNote: j['reviewNote'] as String?,
      );
}

/// 제출 화면용 — 이 회차의 양식과 내 제출
class CrewSlot {
  final CrewTask task;
  final CrewSession session;
  final DateTime deadline;
  final String? blockReason;
  final CrewSubmission? mine;
  const CrewSlot({
    required this.task,
    required this.session,
    required this.deadline,
    this.blockReason,
    this.mine,
  });

  factory CrewSlot.fromJson(Map<String, dynamic> j) => CrewSlot(
        task: CrewTask.fromJson(j['task'] as Map<String, dynamic>),
        session: CrewSession.fromJson(j['session'] as Map<String, dynamic>),
        deadline: DateTime.parse(j['deadline'] as String).toLocal(),
        blockReason: j['blockReason'] as String?,
        mine: j['mine'] == null
            ? null
            : CrewSubmission.fromJson(j['mine'] as Map<String, dynamic>),
      );
}

/// 제출 상세 (현황판에서 열기)
class SubmissionDetail {
  final CrewTask task;
  final CrewSession session;
  final CrewMember? member;
  final CrewSubmission submission;
  final DateTime deadline;
  final bool canReview;
  const SubmissionDetail({
    required this.task,
    required this.session,
    this.member,
    required this.submission,
    required this.deadline,
    required this.canReview,
  });

  factory SubmissionDetail.fromJson(Map<String, dynamic> j) =>
      SubmissionDetail(
        task: CrewTask.fromJson(j['task'] as Map<String, dynamic>),
        session: CrewSession.fromJson(j['session'] as Map<String, dynamic>),
        member: j['member'] == null
            ? null
            : CrewMember.fromJson(j['member'] as Map<String, dynamic>),
        submission:
            CrewSubmission.fromJson(j['submission'] as Map<String, dynamic>),
        deadline: DateTime.parse(j['deadline'] as String).toLocal(),
        canReview: j['canReview'] == true,
      );
}

// ── 동호회 게시판 ───────────────────────────────────────────────────

class CrewPostSummary {
  final int id;
  final bool notice;
  final String title;
  final String preview;
  final String author;
  final CrewRole authorRole;
  final DateTime createdAt;
  final int commentCount;
  const CrewPostSummary({
    required this.id,
    required this.notice,
    required this.title,
    required this.preview,
    required this.author,
    required this.authorRole,
    required this.createdAt,
    required this.commentCount,
  });

  factory CrewPostSummary.fromJson(Map<String, dynamic> j) => CrewPostSummary(
        id: _int(j['id']),
        notice: j['notice'] == true,
        title: j['title'] as String,
        preview: j['preview'] as String? ?? '',
        author: j['author'] as String? ?? '',
        authorRole: _role(j['authorRole']),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        commentCount: _int(j['commentCount']),
      );
}

class CrewComment {
  final int id;
  final String body;
  final String author;
  final CrewRole authorRole;
  final DateTime createdAt;
  final bool canDelete;
  const CrewComment({
    required this.id,
    required this.body,
    required this.author,
    required this.authorRole,
    required this.createdAt,
    required this.canDelete,
  });

  factory CrewComment.fromJson(Map<String, dynamic> j) => CrewComment(
        id: _int(j['id']),
        body: j['body'] as String,
        author: j['author'] as String? ?? '',
        authorRole: _role(j['authorRole']),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        canDelete: j['canDelete'] == true,
      );
}

class CrewPostDetail {
  final int id;
  final bool notice;
  final String title;
  final String body;
  final String author;
  final CrewRole authorRole;
  final DateTime createdAt;
  final bool canEdit;
  final bool canDelete;
  final List<CrewComment> comments;
  const CrewPostDetail({
    required this.id,
    required this.notice,
    required this.title,
    required this.body,
    required this.author,
    required this.authorRole,
    required this.createdAt,
    required this.canEdit,
    required this.canDelete,
    required this.comments,
  });

  factory CrewPostDetail.fromJson(Map<String, dynamic> j) {
    final p = j['post'] as Map<String, dynamic>;
    return CrewPostDetail(
      id: _int(p['id']),
      notice: p['notice'] == true,
      title: p['title'] as String,
      body: p['body'] as String,
      author: p['author'] as String? ?? '',
      authorRole: _role(p['authorRole']),
      createdAt: DateTime.parse(p['createdAt'] as String).toLocal(),
      canEdit: p['canEdit'] == true,
      canDelete: p['canDelete'] == true,
      comments: (j['comments'] as List)
          .map((e) => CrewComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}


// ── 메인 관리자 ─────────────────────────────────────────────────────

class AdminOverview {
  final int users;
  final int proActive;
  final int keys;
  final int keysAvailable;
  final int crews;
  final int crewMembers;
  final int activeTasks;
  final int submissions7d;
  final int reportsOpen;
  const AdminOverview({
    required this.users,
    required this.proActive,
    required this.keys,
    required this.keysAvailable,
    required this.crews,
    required this.crewMembers,
    required this.activeTasks,
    required this.submissions7d,
    this.reportsOpen = 0,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> j) => AdminOverview(
        users: _int(j['users']),
        proActive: _int(j['proActive']),
        keys: _int(j['keys']),
        keysAvailable: _int(j['keysAvailable']),
        crews: _int(j['crews']),
        crewMembers: _int(j['crewMembers']),
        activeTasks: _int(j['activeTasks']),
        submissions7d: _int(j['submissions7d']),
        reportsOpen: _int(j['reportsOpen']),
      );
}

/// Pro 회원 (관리자 목록) / 회원 검색 결과 공용
class AdminUserRow {
  final int userId;
  final String name;
  final String? email;
  final String provider;
  final bool admin;
  final bool pro;
  final DateTime? expiresAt; // null + pro = 평생
  final int keysUsed;
  const AdminUserRow({
    required this.userId,
    required this.name,
    this.email,
    required this.provider,
    required this.admin,
    required this.pro,
    this.expiresAt,
    this.keysUsed = 0,
  });

  String get providerLabel => switch (provider) {
        'google' => '구글',
        'kakao' => '카카오',
        'naver' => '네이버',
        'email' => '이메일',
        _ => provider,
      };

  factory AdminUserRow.fromJson(Map<String, dynamic> j) => AdminUserRow(
        userId: _int(j['userId'] ?? j['id']),
        name: j['name'] as String? ?? '',
        email: j['email'] as String?,
        provider: j['provider'] as String? ?? '',
        admin: j['admin'] == true,
        pro: j['active'] == true || j['pro'] == true,
        expiresAt: j['expiresAt'] == null
            ? null
            : DateTime.parse(j['expiresAt'] as String).toLocal(),
        keysUsed: _int(j['keysUsed']),
      );
}

class AdminCrewRow {
  final int id;
  final String name;
  final String startDate;
  final String endDate;
  final String? leader;
  final int memberCount;
  final int taskCount;
  final DateTime? lastSubmissionAt;
  final DateTime createdAt;
  final bool deleted;
  const AdminCrewRow({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.leader,
    required this.memberCount,
    required this.taskCount,
    this.lastSubmissionAt,
    required this.createdAt,
    required this.deleted,
  });

  factory AdminCrewRow.fromJson(Map<String, dynamic> j) => AdminCrewRow(
        id: _int(j['id']),
        name: j['name'] as String,
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        leader: j['leader'] as String?,
        memberCount: _int(j['memberCount']),
        taskCount: _int(j['taskCount']),
        lastSubmissionAt: j['lastSubmissionAt'] == null
            ? null
            : DateTime.parse(j['lastSubmissionAt'] as String).toLocal(),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        deleted: j['deleted'] == true,
      );
}

/// 신고 (관리자 화면) — 같은 대상에 대한 신고를 묶은 것
class ReportGroup {
  final String targetType; // post | comment | submission
  final int targetId;
  final int crewId;
  final String crewName;
  final int count;
  final String status; // open | resolved | dismissed
  final String? action;
  final DateTime latestAt;
  final List<({String reporter, String reason, String? memo, DateTime at})>
      reports;
  final bool exists;
  final String? author;
  final String? title;
  final String? text;
  final String? photoUrl;
  final List<({String name, String kind, String url})> files;
  const ReportGroup({
    required this.targetType,
    required this.targetId,
    required this.crewId,
    required this.crewName,
    required this.count,
    required this.status,
    this.action,
    required this.latestAt,
    required this.reports,
    required this.exists,
    this.author,
    this.title,
    this.text,
    this.photoUrl,
    this.files = const [],
  });

  String get typeLabel => switch (targetType) {
        'post' => '게시글',
        'comment' => '댓글',
        _ => '과제 제출',
      };

  factory ReportGroup.fromJson(Map<String, dynamic> j) {
    final p = (j['preview'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReportGroup(
      targetType: j['targetType'] as String,
      targetId: _int(j['targetId']),
      crewId: _int(j['crewId']),
      crewName: j['crewName'] as String? ?? '',
      count: _int(j['count']),
      status: j['status'] as String? ?? 'open',
      action: j['action'] as String?,
      latestAt: DateTime.parse(j['latestAt'] as String).toLocal(),
      reports: ((j['reports'] as List?) ?? const [])
          .map((e) => (
                reporter: (e as Map)['reporter'] as String? ?? '',
                reason: e['reasonLabel'] as String? ?? '',
                memo: e['memo'] as String?,
                at: DateTime.parse(e['createdAt'] as String).toLocal(),
              ))
          .toList(),
      exists: p['exists'] == true,
      author: p['author'] as String?,
      title: p['title'] as String?,
      text: p['text'] as String?,
      photoUrl: p['photoUrl'] as String?,
      files: ((p['files'] as List?) ?? const [])
          .map((e) => (
                name: (e as Map)['name'] as String? ?? '',
                kind: e['kind'] as String? ?? 'file',
                url: e['url'] as String? ?? '',
              ))
          .toList(),
    );
  }
}
