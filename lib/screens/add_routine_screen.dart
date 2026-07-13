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

  final _title = TextEditingController();
  final _reason = TextEditingController();
  final _backup = TextEditingController();
  final _target = TextEditingController();

  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _reason.dispose();
    _backup.dispose();
    _target.dispose();
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
          _type == RoutineType.accumulate ? _accumCycle : DutyCycle.weeklySunday,
      backupTitle: _type == RoutineType.accumulate && _backup.text.trim().isNotEmpty
          ? _backup.text.trim()
          : null,
      targetValue: _type == RoutineType.result && _target.text.trim().isNotEmpty
          ? _target.text.trim()
          : null,
      createdAt: DateTime.now(),
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
            const SizedBox(height: 8),
            const _InfoBox(
              text: '결과형은 매주 일요일 23:59까지 진행 결과를 인증합니다.\n'
                  '실행 여부를 판단할 수 있도록 목표를 구체적으로 적어주세요.',
            ),
          ],
          const SizedBox(height: 12),
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
