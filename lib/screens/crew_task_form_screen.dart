import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/crew.dart';
import '../models/routine.dart';
import '../services/crew_api.dart';
import '../widgets/crew_form_editor.dart';

/// 동호회 공통 과제 만들기·수정 (반장·부반장).
///  - 인증형: 매일(또는 월~토) 인증 — 앱 인증 방식 하나(사진·타이머·녹음·링크 등)
///  - 과제 점검형: 매주 정한 요일들(예: 목·일)·시각에 마감, 반장이 꾸민 양식으로 제출 → 운영진 점검
class CrewTaskFormScreen extends StatefulWidget {
  final CrewInfo crew;
  final CrewTask? initial;
  const CrewTaskFormScreen({super.key, required this.crew, this.initial});

  @override
  State<CrewTaskFormScreen> createState() => _CrewTaskFormScreenState();
}

class _CrewTaskFormScreenState extends State<CrewTaskFormScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  late CrewTaskKind _kind = widget.initial?.kind ?? CrewTaskKind.assignment;
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _reason = TextEditingController(text: widget.initial?.reason);
  late final _backup = TextEditingController(text: widget.initial?.backupTitle);
  late DutyCycle _cycle = widget.initial?.dutyCycle ??
      (_kind == CrewTaskKind.cert ? DutyCycle.everyday : DutyCycle.weekly);
  // 새 과제는 '매주 목·일'을 기본으로 (원조 모임의 과제 마감 방식)
  late final Set<int> _days = {
    ...(widget.initial?.dueWeekdays.isNotEmpty ?? false)
        ? widget.initial!.dueWeekdays
        : widget.initial != null
            ? [widget.initial!.dueWeekday]
            : const [4, 7],
  };
  late int? _deadlineMin = widget.initial?.deadlineMin;
  /// 요일별 '수업 시작 시각'(분)과 마감 규칙 — 수업 N분 전 / 수업 전날 밤
  late final Map<int, int> _classStart = {
    ...?widget.initial?.classSchedule?.days,
  };
  late bool _prevDay = widget.initial?.classSchedule?.prevDay ?? false;
  late final _beforeMin = TextEditingController(
      text: '${widget.initial?.classSchedule?.minutes ?? 1}');
  late int _prevDayTime = widget.initial?.classSchedule?.time ?? 23 * 60 + 59;
  late List<FormItem> _form = (widget.initial?.form.isNotEmpty ?? false)
      ? widget.initial!.form
      : CrewFormEditor.starter;
  late VerifyMethod _method = widget.initial?.verifyMethod ?? VerifyMethod.photo;
  late int _timerMinutes = widget.initial?.timerMinutes ?? 15;
  late bool _requireNote = widget.initial?.requireNote ?? false;
  late int? _winStart = widget.initial?.windowStartMin;
  late int? _winEnd = widget.initial?.windowEndMin;
  late DateTime _start;
  late DateTime _end;
  bool _saving = false;

  bool get _cert => _kind == CrewTaskKind.cert;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final crewStart = DateTime.parse(widget.crew.startDate);
    _start = widget.initial != null
        ? DateTime.parse(widget.initial!.startDate)
        : (crewStart.isAfter(today) ? crewStart : today);
    _end = DateTime.parse(widget.initial?.endDate ?? widget.crew.endDate);
    if (_end.isBefore(_start)) _end = _start;
  }

  @override
  void dispose() {
    _title.dispose();
    _reason.dispose();
    _backup.dispose();
    _beforeMin.dispose();
    super.dispose();
  }

  List<DutyCycle> get _cycles => _cert
      ? const [DutyCycle.everyday, DutyCycle.sixDays]
      : const [DutyCycle.weekly, DutyCycle.every15days, DutyCycle.once];

  String _cycleLabel(DutyCycle c) => switch (c) {
        DutyCycle.weekly => '매주 (요일 선택)',
        DutyCycle.once => '기간 끝에 1회',
        _ => c.label,
      };

  Future<int?> _pickTime(int? initial) async {
    final m = initial ?? 23 * 60 + 59;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    return t == null ? null : t.hour * 60 + t.minute;
  }

  /// 그 요일의 실제 마감 안내 — "목 19:29 마감", "수 23:59 마감(전날)"
  String _deadlineText(int day, int start) {
    final m = _prevDay
        ? _prevDayTime - 1440
        : start - (int.tryParse(_beforeMin.text.trim()) ?? 1);
    final prev = m < 0;
    final dayName = weekdayNames[(day - 1 + (prev ? 6 : 0)) % 7];
    return '$dayName ${fmtMinute((m + 1440) % 1440)} 마감${prev ? ' (전날)' : ''}';
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return _snack('과제 이름을 적어 주세요');
    if (!_cert && _cycle == DutyCycle.weekly && _days.isEmpty) {
      return _snack('마감 요일을 하나 이상 골라 주세요');
    }
    if (!_cert && _form.isEmpty) return _snack('제출 양식 항목을 하나 이상 넣어 주세요');
    if (_cert &&
        ((_winStart == null) != (_winEnd == null) ||
            (_winStart != null && _winStart! >= _winEnd!))) {
      return _snack('인증 시간대를 다시 확인해 주세요 (시작 < 끝)');
    }
    final days = _days.toList()..sort();
    final task = CrewTask(
      id: widget.initial?.id ?? 0,
      crewId: widget.crew.id,
      kind: _kind,
      dueWeekdays: !_cert && _cycle == DutyCycle.weekly ? days : const [],
      deadlineMin: _cert ? null : _deadlineMin,
      // 수업 시간표 (선택한 요일만) — 마감은 규칙대로 계산된다
      classSchedule: !_cert &&
              _cycle == DutyCycle.weekly &&
              days.any((d) => _classStart[d] != null)
          ? ClassSchedule(
              days: {
                for (final d in days)
                  if (_classStart[d] != null) d: _classStart[d]!
              },
              rule: _prevDay ? 'prevDay' : 'before',
              minutes: (int.tryParse(_beforeMin.text.trim()) ?? 1).clamp(0, 1440),
              time: _prevDayTime,
            )
          : null,
      form: _cert ? const [] : _form,
      type: _cert ? RoutineType.accumulate : RoutineType.result,
      title: title,
      reason: _reason.text.trim(),
      dutyCycle: _cycle,
      dueWeekday: days.isEmpty ? 7 : days.first,
      backupTitle:
          _cert && _backup.text.trim().isNotEmpty ? _backup.text.trim() : null,
      verifyMethod: _method,
      timerMinutes: _timerMinutes,
      requireNote: _requireNote,
      windowStartMin: _cert ? _winStart : null,
      windowEndMin: _cert ? _winEnd : null,
      startDate: _fmt.format(_start),
      endDate: _fmt.format(_end),
      archived: false,
    );
    setState(() => _saving = true);
    try {
      if (widget.initial == null) {
        await CrewApi.createTask(widget.crew.id, task);
      } else {
        await CrewApi.updateTask(widget.crew.id, widget.initial!.id, task);
      }
      if (mounted) Navigator.pop(context, true);
    } on CrewApiException catch (e) {
      _snack(e.message);
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (sub != null)
              Text(sub, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '과제 수정' : '공통 과제 만들기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (editing)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    '수정 내용은 회원들의 앱에 다음 동기화 때 반영돼요. '
                    '주기·기간을 바꾸면 지난 제출 기록과 의무일이 어긋날 수 있어요.',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          _section('과제 유형', editing ? '유형은 만든 뒤에 바꿀 수 없어요' : null),
          SegmentedButton<CrewTaskKind>(
            segments: const [
              ButtonSegment(
                  value: CrewTaskKind.assignment,
                  icon: Icon(Icons.fact_check_outlined),
                  label: Text('과제 점검형')),
              ButtonSegment(
                  value: CrewTaskKind.cert,
                  icon: Icon(Icons.verified_outlined),
                  label: Text('인증형 (매일)')),
            ],
            selected: {_kind},
            onSelectionChanged: editing
                ? null
                : (v) => setState(() {
                      _kind = v.first;
                      _cycle = _cycles.first;
                    }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _cert
                  ? '회원이 매일 인증하면 개인 도장과 함께 자동 제출돼요.'
                  : '정한 요일·시각까지 양식대로 제출하면, 반장·부반장이 확인하거나 보완을 요청해요.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _section('과제'),
          TextField(
            controller: _title,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: _cert
                  ? '과제 이름 (예: 영어 원서 20분 읽기)'
                  : '과제 이름 (예: 주간 독서 과제)',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_cert)
            TextField(
              controller: _backup,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: '백업 과제 (선택, 예: 5분만 읽기)',
                  border: OutlineInputBorder()),
            ),
          TextField(
            controller: _reason,
            maxLength: 1000,
            maxLines: 5,
            minLines: 2,
            decoration: InputDecoration(
                labelText: _cert ? '과제를 하는 이유 · 안내 (선택)' : '과제 안내 (공통, 선택)',
                alignLabelWithHint: true,
                border: const OutlineInputBorder()),
          ),
          _section('마감'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _cycles
                .map((c) => ChoiceChip(
                      label: Text(_cycleLabel(c)),
                      selected: _cycle == c,
                      onSelected: (_) => setState(() => _cycle = c),
                    ))
                .toList(),
          ),
          if (!_cert && _cycle == DutyCycle.weekly) ...[
            const SizedBox(height: 10),
            const Text('마감 요일 (여러 개 선택 가능 — 예: 목·일)',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: List.generate(7, (i) {
                final wd = i + 1;
                return FilterChip(
                  label: Text(weekdayNames[i]),
                  selected: _days.contains(wd),
                  onSelected: (on) => setState(() {
                    on ? _days.add(wd) : _days.remove(wd);
                  }),
                );
              }),
            ),
          ],
          if (!_cert && _cycle == DutyCycle.weekly && _days.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('요일별 수업 시작 시각 (비워 둔 요일은 아래 공통 마감 시각)',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('수업 N분 전 마감')),
                ButtonSegment(value: true, label: Text('수업 전날 밤 마감')),
              ],
              selected: {_prevDay},
              onSelectionChanged: (v) => setState(() => _prevDay = v.first),
            ),
            const SizedBox(height: 6),
            if (!_prevDay)
              Row(
                children: [
                  const Text('수업 시작'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _beforeMin,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('분 전에 마감'),
                ],
              )
            else
              Row(
                children: [
                  const Text('수업 전날'),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final m = await _pickTime(_prevDayTime);
                      if (m != null) setState(() => _prevDayTime = m);
                    },
                    child: Text(fmtMinute(_prevDayTime)),
                  ),
                  const SizedBox(width: 8),
                  const Text('까지 마감'),
                ],
              ),
            ...(_days.toList()..sort()).map((d) {
              final start = _classStart[d];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                    radius: 16, child: Text(weekdayNames[d - 1])),
                title: Text(start == null
                    ? '${weekdayNames[d - 1]}요일 수업 시각 미정'
                    : '${weekdayNames[d - 1]}요일 ${fmtMinute(start)} 수업'),
                subtitle: Text(start == null
                    ? '공통 마감 ${fmtMinute(_deadlineMin ?? 23 * 60 + 59)}'
                    : _deadlineText(d, start)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final m = await _pickTime(start ?? 21 * 60);
                        if (m == null) return;
                        setState(() => _classStart[d] = m);
                      },
                      child: Text(start == null ? '수업 시각' : fmtMinute(start)),
                    ),
                    if (start != null)
                      IconButton(
                        tooltip: '지우기',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _classStart.remove(d)),
                      ),
                  ],
                ),
              );
            }),
          ],
          if (!_cert)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(_cycle == DutyCycle.weekly ? '공통 마감 시각' : '마감 시각'),
              subtitle: const Text('이 시각이 지나면 제출할 수 없어요 (알람도 이 시각 기준)'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final m = await _pickTime(_deadlineMin);
                  if (m != null) setState(() => _deadlineMin = m);
                },
                child: Text(fmtMinute(_deadlineMin ?? 23 * 60 + 59)),
              ),
            ),
          if (!_cert) ...[
            _section('제출 양식',
                '회원이 채울 항목을 골라 꾸며 주세요. 회차마다 다른 양식은 과제를 만든 뒤 「회차별 과제 내용」에서 바꿀 수 있어요.'),
            CrewFormEditor(initial: _form, onChanged: (f) => _form = f),
          ],
          if (_cert) ...[
            _section('인증 방식'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectableVerifyMethods
                  .map((m) => ChoiceChip(
                        label: Text(m.label),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ))
                  .toList(),
            ),
            if (_method == VerifyMethod.audio || _method == VerifyMethod.video)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    '녹음·동영상 파일은 동호회에 올라가지 않고, 인증 여부와 소감만 제출돼요. '
                    '녹음을 들어 보고 점검하려면 「과제 점검형」의 녹음 항목을 쓰세요.',
                    style: TextStyle(fontSize: 12)),
              ),
            if (_method == VerifyMethod.timer)
              Row(
                children: [
                  const Text('목표 시간'),
                  const Spacer(),
                  IconButton(
                      onPressed: _timerMinutes > 1
                          ? () => setState(() => _timerMinutes =
                              _timerMinutes > 5 ? _timerMinutes - 5 : _timerMinutes - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$_timerMinutes분',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(
                      onPressed: () => setState(() => _timerMinutes += 5),
                      icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _requireNote,
              onChanged: (v) => setState(() => _requireNote = v),
              title: const Text('소감 필수'),
              subtitle: const Text('요약·느낀점을 꼭 적어야 제출돼요'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _winStart != null,
              onChanged: (v) => setState(() {
                _winStart = v ? 300 : null; // 기본 05:00~08:00
                _winEnd = v ? 480 : null;
              }),
              title: const Text('인증 시간대 제한'),
              subtitle: Text(_winStart == null
                  ? '예: 일찍 일어나기 — 정해진 시간에만 인증'
                  : '${fmtMinute(_winStart!)} ~ ${fmtMinute(_winEnd!)} (끝 시각이 마감)'),
            ),
            if (_winStart != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final m = await _pickTime(_winStart);
                        if (m != null) setState(() => _winStart = m);
                      },
                      child: Text('시작 ${fmtMinute(_winStart!)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final m = await _pickTime(_winEnd);
                        if (m != null) setState(() => _winEnd = m);
                      },
                      child: Text('끝 ${fmtMinute(_winEnd!)}'),
                    ),
                  ),
                ],
              ),
          ],
          _section('기간'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final p = await showDatePicker(
                        context: context,
                        initialDate: _start,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2035));
                    if (p != null) {
                      setState(() {
                        _start = p;
                        if (_end.isBefore(p)) _end = p;
                      });
                    }
                  },
                  child: Text('시작 ${_fmt.format(_start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final p = await showDatePicker(
                        context: context,
                        initialDate: _end,
                        firstDate: _start,
                        lastDate: DateTime(2035));
                    if (p != null) setState(() => _end = p);
                  },
                  child: Text('종료 ${_fmt.format(_end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving
                ? '저장 중…'
                : editing
                    ? '저장'
                    : '과제 만들기 (회원 앱에 자동 추가)'),
          ),
        ],
      ),
    );
  }
}
