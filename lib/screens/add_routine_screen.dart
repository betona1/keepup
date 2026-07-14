import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models/routine.dart';

class AddRoutineScreen extends StatefulWidget {
  final AppState state;
  const AddRoutineScreen({super.key, required this.state});

  @override
  State<AddRoutineScreen> createState() => _AddRoutineScreenState();
}

class _AddRoutineScreenState extends State<AddRoutineScreen> {
  RoutineType _type = RoutineType.accumulate;
  DutyCycle _accumCycle = DutyCycle.everyday;
  DutyCycle _resultCycle = DutyCycle.weekly;
  int _dueWeekday = 7; // 매주 주기의 마감 요일 (기본 일요일)
  VerifyMethod _verify = VerifyMethod.photo;
  int _timerMinutes = 15;
  int _targetSteps = 6000;
  bool _requireNote = false;
  bool _useWindow = false;
  TimeOfDay _windowStart = const TimeOfDay(hour: 5, minute: 0);
  TimeOfDay _windowEnd = const TimeOfDay(hour: 8, minute: 0);
  late DateTime _endDate; // 완료 목표일 (기본 63일)

  final _title = TextEditingController();
  final _reason = TextEditingController();
  final _backup = TextEditingController();
  final _target = TextEditingController();
  final _mediaUrl = TextEditingController(); // 명상 미디어 (파일 경로/URL)

  String? _titleError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // 기간은 본인이 설정 — 최소 30일(한 달), 초기 제안값 30일
    _endDate = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 29));
  }

  @override
  void dispose() {
    _title.dispose();
    _reason.dispose();
    _backup.dispose();
    _target.dispose();
    _mediaUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = '루틴 이름을 입력해 주세요');
      return;
    }
    final r = Routine(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      title: _title.text.trim(),
      reason: _reason.text.trim(),
      dutyCycle:
          _type == RoutineType.accumulate ? _accumCycle : _resultCycle,
      dueWeekday: _dueWeekday,
      backupTitle: _type == RoutineType.accumulate && _backup.text.trim().isNotEmpty
          ? _backup.text.trim()
          : null,
      targetValue: _type == RoutineType.result && _target.text.trim().isNotEmpty
          ? _target.text.trim()
          : null,
      createdAt: DateTime.now(),
      verifyMethod: _verify,
      timerMinutes: _timerMinutes,
      targetSteps: _targetSteps,
      mediaSource:
          _mediaUrl.text.trim().isEmpty ? null : _mediaUrl.text.trim(),
      requireNote: _requireNote,
      windowStartMin:
          _useWindow ? _windowStart.hour * 60 + _windowStart.minute : null,
      windowEndMin:
          _useWindow ? _windowEnd.hour * 60 + _windowEnd.minute : null,
      endDate: _endDate,
    );
    await widget.state.addRoutine(r);
    if (mounted) Navigator.pop(context);
  }

  /// 원조 카톡 챌린지 회원들의 실제 수행 예시
  static const _presets = [
    '매일 1만보 걷기',
    '하루 20분 독서하기',
    '팔굽혀펴기 50개',
    '명상 15분 이상',
    '계단 오르기 15층',
    '중국어 한마디 발음연습',
    '건강식품 챙겨먹기',
    '일찍 일어나 모닝 명상',
    '자기계발서 읽고 요약',
    '출근해서 기도하기',
    '주식 공부 1시간',
    '유튜브 1개 내용 정리',
    '온라인몰 상품 1개 등록',
    '문장 50번 쓰기',
    'AI 프롬프트 100개 바이브코딩',
  ];

  @override
  Widget build(BuildContext context) {
    final isAccum = _type == RoutineType.accumulate;
    return Scaffold(
      appBar: AppBar(title: const Text('루틴 선언')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('유형', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<RoutineType>(
            segments: const [
              ButtonSegment(
                  value: RoutineType.accumulate,
                  label: Text('적립형'),
                  icon: Icon(Icons.calendar_month)),
              ButtonSegment(
                  value: RoutineType.result,
                  label: Text('결과형'),
                  icon: Icon(Icons.flag)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            isAccum
                ? '매일(또는 주6일) 실행하고 인증하며 쌓아가는 방식'
                : '목표값을 미리 정하고, 매주 일요일에 진행 결과를 인증하는 방식',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: isAccum ? '메인 루틴' : '목표 이름',
              hintText: isAccum ? '예: 아침 스트레칭 10분' : '예: 9주간 책 5권 읽기',
              errorText: _titleError,
            ),
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          const SizedBox(height: 10),
          // 실제 챌린지 회원들의 수행 예시 — 탭하면 이름 채움
          Text('추천 루틴', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ActionChip(
                label: Text(_presets[i],
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _title.text = _presets[i];
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isAccum) ...[
            TextField(
              controller: _backup,
              decoration: const InputDecoration(
                labelText: '백업 루틴 (선택)',
                hintText: '더 가볍게 실행할 수 있는 대체 루틴',
              ),
            ),
            const SizedBox(height: 12),
            Text('의무 인증 주기',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<DutyCycle>(
              segments: const [
                ButtonSegment(
                    value: DutyCycle.everyday, label: Text('매일 (주7일)')),
                ButtonSegment(
                    value: DutyCycle.sixDays, label: Text('월~토 (주6일)')),
              ],
              selected: {_accumCycle},
              onSelectionChanged: (s) =>
                  setState(() => _accumCycle = s.first),
            ),
          ] else ...[
            TextField(
              controller: _target,
              decoration: const InputDecoration(
                labelText: '목표값 (구체적으로)',
                hintText: '예: 총 300페이지, 10km 4회 등',
              ),
            ),
            const SizedBox(height: 12),
            Text('인증 주기', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<DutyCycle>(
              segments: const [
                ButtonSegment(value: DutyCycle.weekly, label: Text('매주 1회')),
                ButtonSegment(
                    value: DutyCycle.every15days, label: Text('15일마다')),
                ButtonSegment(value: DutyCycle.once, label: Text('1회성')),
              ],
              selected: {_resultCycle},
              onSelectionChanged: (s) =>
                  setState(() => _resultCycle = s.first),
            ),
            if (_resultCycle == DutyCycle.weekly) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('마감 요일',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      children: List.generate(7, (i) {
                        final wd = i + 1; // 1=월 ... 7=일
                        return ChoiceChip(
                          label: Text(weekdayNames[i]),
                          selected: _dueWeekday == wd,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _dueWeekday = wd),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _InfoBox(
              text: switch (_resultCycle) {
                DutyCycle.weekly =>
                  '매주 ${weekdayNames[_dueWeekday - 1]}요일 23:59가 마감입니다. 그 주 안이면 언제든 미리 인증할 수 있어요.\n마감 3일 전부터 매일 아침 9시에 알림을 드립니다.',
                DutyCycle.every15days =>
                  '15일마다 한 번씩 결과를 인증합니다. 각 기간 안이면 언제든 미리 인증 가능.\n마감 3일 전부터 매일 아침 9시에 알림을 드립니다.',
                _ =>
                  '완료 목표일에 한 번만 결과를 인증하는 방식입니다. 기간 안이면 언제든 인증 가능.\n마감 3일 전부터 매일 아침 9시에 알림을 드립니다.',
              },
            ),
          ],
          const SizedBox(height: 20),
          // ── 검증 방식 선택 — 루틴 성격에 맞게 고르기 쉽게 카드로 ──
          Text('검증 방법', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...VerifyMethod.values.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _VerifyCard(
                  method: m,
                  selected: _verify == m,
                  onTap: () => setState(() => _verify = m),
                ),
              )),
          if (_verify == VerifyMethod.timer) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('목표 시간',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                ...[10, 15, 20, 30, 60].map((min) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text('$min분'),
                        selected: _timerMinutes == min,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) =>
                            setState(() => _timerMinutes = min),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            // 명상 모드 배경 미디어 — 내 음악 파일 / 오디오 URL / 유튜브 URL
            Text('명상 음악·영상 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _mediaUrl,
              decoration: InputDecoration(
                hintText: '유튜브 주소, 음악 스트리밍 URL 붙여넣기',
                hintStyle: const TextStyle(fontSize: 13),
                suffixIcon: _mediaUrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _mediaUrl.clear()),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final res = await FilePicker.platform
                    .pickFiles(type: FileType.audio);
                final path = res?.files.single.path;
                if (path != null) {
                  setState(() => _mediaUrl.text = path);
                }
              },
              icon: const Icon(Icons.library_music_outlined, size: 18),
              label: const Text('내 폰의 음악 파일 선택'),
            ),
            const SizedBox(height: 4),
            Text('타이머가 도는 동안 재생됩니다. 음악·URL은 앱 안에서, 유튜브는 유튜브로 열려요.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_verify == VerifyMethod.steps) ...[
            const SizedBox(height: 4),
            Text('목표 걸음수',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [5000, 6000, 8000, 10000].map((s) => ChoiceChip(
                    label: Text('${s ~/ 1000}천보'),
                    selected: _targetSteps == s,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _targetSteps = s),
                  )).toList(),
            ),
            const SizedBox(height: 4),
            Text('삼성헬스·구글 피트니스가 기록한 걸음수를 헬스커넥트로 읽어 자동 확인합니다.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          // 소감 필수 — 명상 등 내면 기록이 중요한 습관용
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _requireNote,
            onChanged: (v) => setState(() => _requireNote = v),
            title: const Text('소감/느낀점 필수 작성'),
            subtitle: const Text('인증할 때 오늘의 느낌을 꼭 적게 합니다 (명상·독서 추천)'),
          ),
          // 인증 시간대 제한 — 일찍 일어나기 등 (마감 알림도 이 시각 기준으로 변경)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useWindow,
            onChanged: (v) => setState(() => _useWindow = v),
            title: const Text('인증 시간대 제한'),
            subtitle: const Text('정해진 시간에만 도장 가능 (일찍 일어나기 추천)'),
          ),
          if (_useWindow) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: _windowStart);
                      if (t != null) setState(() => _windowStart = t);
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(
                        '시작 ${_windowStart.hour.toString().padLeft(2, '0')}:${_windowStart.minute.toString().padLeft(2, '0')}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: _windowEnd);
                      if (t != null) setState(() => _windowEnd = t);
                    },
                    icon: const Icon(Icons.timer_off_outlined, size: 18),
                    label: Text(
                        '마감 ${_windowEnd.hour.toString().padLeft(2, '0')}:${_windowEnd.minute.toString().padLeft(2, '0')}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                ('기상 05~08시', 5, 0, 8, 0),
                ('아침 06~09시', 6, 0, 9, 0),
                ('저녁 20~23시', 20, 0, 23, 0),
              ].map((p) {
                return ActionChip(
                  label: Text(p.$1, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _windowStart = TimeOfDay(hour: p.$2, minute: p.$3);
                    _windowEnd = TimeOfDay(hour: p.$4, minute: p.$5);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text('마감 전 알림(3시간·1시간·30분 전)도 이 마감 시각 기준으로 울립니다.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          // ── 완료 목표일 — 기본 63일 (습관이 몸에 붙는 9주) ──
          Text('완료 목표일', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              // 적립형 최소 30일~2년, 결과형 최소 1주~1년
              final minDays = isAccum ? 29 : 6;
              final maxDays = isAccum ? 730 : 364;
              final minEnd = today.add(Duration(days: minDays));
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _endDate.isBefore(minEnd) ? minEnd : _endDate,
                firstDate: minEnd,
                lastDate: today.add(Duration(days: maxDays)),
                helpText: isAccum
                    ? '완료 목표일 선택 (최소 30일)'
                    : '완료 목표일 선택 (최소 1주 ~ 최대 1년)',
              );
              if (picked != null) setState(() => _endDate = picked);
            },
            icon: const Icon(Icons.event),
            label: Text(
                '${_endDate.year}.${_endDate.month.toString().padLeft(2, '0')}.${_endDate.day.toString().padLeft(2, '0')}'
                ' (${_endDate.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays + 1}일간)'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: (isAccum
                    ? const [
                        (30, '30일'),
                        (63, '63일'),
                        (100, '100일'),
                        (365, '1년'),
                        (730, '2년'),
                      ]
                    : const [
                        (7, '1주'),
                        (14, '2주'),
                        (30, '1개월'),
                        (90, '3개월'),
                        (180, '6개월'),
                        (365, '1년'),
                      ])
                .map((preset) {
              final now = DateTime.now();
              final target = DateTime(now.year, now.month, now.day)
                  .add(Duration(days: preset.$1 - 1));
              final selected = _endDate == target;
              return ChoiceChip(
                label: Text(preset.$2),
                selected: selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _endDate = target),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text(
              isAccum
                  ? '기간은 내가 정합니다 (최소 30일). 1년, 2년 쌓일 때 진짜 습관이 됩니다.'
                  : '결과형 기간: 최소 1주 ~ 최대 1년. "이번 달 말까지"처럼 자유롭게 정하세요.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '정한 이유 / 다짐 (선택)',
              hintText: '왜 이 루틴을 정했는지 적으면 실행력이 올라가요',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('선언하고 시작'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

/// 검증 방식 선택 카드 — 아이콘 + 설명으로 고르기 쉽게
class _VerifyCard extends StatelessWidget {
  final VerifyMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _VerifyCard(
      {required this.method, required this.selected, required this.onTap});

  IconData get _icon => switch (method) {
        VerifyMethod.photo => Icons.photo_camera_outlined,
        VerifyMethod.timer => Icons.timer_outlined,
        VerifyMethod.audio => Icons.mic_none_rounded,
        VerifyMethod.video => Icons.videocam_outlined,
        VerifyMethod.steps => Icons.directions_walk_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(_icon, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? cs.primary : cs.onSurface,
                      )),
                  const SizedBox(height: 2),
                  Text(method.description,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: cs.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}
