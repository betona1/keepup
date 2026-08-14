import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models/routine.dart';
import '../theme.dart';

/// 루틴 변경 화면 — 부상·사정이 생겼을 때 더 가벼운 루틴/인증 방식으로
/// 바꿨다가, 회복하면 다시 원래 루틴으로 돌아올 수 있다 (기간 내 최대 2회).
/// 언제 무엇이 어떻게 바뀌었는지 이력이 아래에 날짜별로 남는다.
class ChangeRoutineScreen extends StatefulWidget {
  final AppState state;
  final Routine routine;
  const ChangeRoutineScreen(
      {super.key, required this.state, required this.routine});

  @override
  State<ChangeRoutineScreen> createState() => _ChangeRoutineScreenState();
}

class _ChangeRoutineScreenState extends State<ChangeRoutineScreen> {
  late final _titleCtrl = TextEditingController(text: widget.routine.title);
  late final _noteCtrl = TextEditingController();
  late final _timerCtrl =
      TextEditingController(text: '${widget.routine.timerMinutes}');
  late VerifyMethod _method = widget.routine.verifyMethod;
  bool _saving = false;

  // 변경 화면에서 고를 수 있는 인증 방식 (걸음수는 1차 출시 제외 정책 유지)
  static const _methods = [
    VerifyMethod.photo,
    VerifyMethod.timer,
    VerifyMethod.audio,
    VerifyMethod.video,
    VerifyMethod.link,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _timerCtrl.dispose();
    super.dispose();
  }

  int get _left => AppState.maxRoutineChanges - widget.routine.changeUsedCount;

  Future<void> _apply() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('루틴 이름을 입력해 주세요')));
      return;
    }
    final noChange =
        title == widget.routine.title && _method == widget.routine.verifyMethod;
    if (noChange) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('바뀐 내용이 없어요')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('루틴을 변경할까요?'),
        content: Text(
          '${widget.routine.title} (${widget.routine.verifyMethod.label})\n'
          '→ $title (${_method.label})\n\n'
          '변경 찬스 $_left회 중 1회를 사용합니다.\n'
          '이력이 남고, 지금까지 찍은 도장은 그대로 유지돼요.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경하기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final done = await widget.state.changeRoutine(
      widget.routine.id,
      newTitle: title,
      newMethod: _method,
      newTimerMinutes: _method == VerifyMethod.timer
          ? int.tryParse(_timerCtrl.text.trim())
          : null,
      note: _noteCtrl.text,
    );
    if (!mounted) return;
    if (done) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('루틴을 변경했어요 — $title ✅')));
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('변경 찬스를 모두 사용했어요')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.routine;
    final exhausted = _left <= 0;
    // 이력은 최신이 위로
    final log = r.changeLog.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('루틴 변경')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // 안내 카드
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '다치거나 사정이 생기면 잠시 가벼운 루틴으로 바꿔서 이어가세요. '
              '회복하면 다시 바꿔 도전할 수 있어요.\n'
              '기간 내 최대 ${AppState.maxRoutineChanges}회 · 남은 찬스 $_left회 · '
              '도장 기록은 그대로 유지됩니다.',
              style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 20),

          if (!exhausted) ...[
            Text('바꿀 루틴 이름', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                  hintText: '예: 스트레칭 10분 (허리 회복 중)'),
            ),
            const SizedBox(height: 18),
            Text('인증 방식', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._methods.map((m) {
              final selected = m == _method;
              return ListTile(
                onTap: () => setState(() => _method = m),
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? cs.primary : cs.outlineVariant,
                ),
                title: Text(m.label,
                    style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500)),
                subtitle: Text(m.description,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
            if (_method == VerifyMethod.timer) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _timerCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '타이머 목표 (분)', hintText: '15'),
              ),
            ],
            const SizedBox(height: 18),
            Text('변경 사유 (선택 — 이력에 함께 남아요)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration:
                  const InputDecoration(hintText: '예: 허리 부상으로 잠시 가볍게'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _apply,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.swap_horiz_rounded),
              label: Text(_saving ? '변경 중…' : '루틴 변경하기 (찬스 $_left회 남음)'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '변경 찬스 ${AppState.maxRoutineChanges}회를 모두 사용했어요.\n'
                '지금 루틴으로 완주까지 달려봐요 💪',
                style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
              ),
            ),

          // ── 변경 이력 ──
          const SizedBox(height: 28),
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('변경 이력', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          if (log.isEmpty)
            Text('아직 변경 이력이 없어요 — 처음 선언 그대로 진행 중!',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))
          else
            ...log.map((c) => _ChangeLogTile(change: c)),
        ],
      ),
    );
  }
}

/// 변경 이력 한 건 — "언제 · 무엇(방식) → 무엇(방식)" 을 한눈에
class _ChangeLogTile extends StatelessWidget {
  final RoutineChange change;
  const _ChangeLogTile({required this.change});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final when = DateFormat('yyyy.MM.dd (E) HH:mm', 'ko').format(change.at);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${change.beforeTitle}\n(${change.beforeMethod.label})',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 18, color: AppTheme.stamp),
              ),
              Expanded(
                child: Text(
                  '${change.afterTitle}\n(${change.afterMethod.label})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ],
          ),
          if (change.note != null) ...[
            const SizedBox(height: 6),
            Text('“${change.note}”',
                style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
