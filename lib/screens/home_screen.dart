import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/quote_service.dart';
import '../theme.dart';
import 'certify_screen.dart';

class HomeBody extends StatelessWidget {
  final AppState state;
  const HomeBody({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        if (state.routines.isEmpty) {
          return _EmptyState();
        }

        final duty = state.dutyRoutinesForDay(today);
        final resting = state.routines
            .where((r) => !r.isDutyDay(today) && !r.isEnded(today))
            .toList();
        final done =
            duty.where((r) => state.isCertified(r.id, today)).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _TodayHeader(today: today, done: done, total: duty.length),
            const SizedBox(height: 14),
            const _QuoteCard(),
            const SizedBox(height: 20),
            ...duty.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RoutineCard(state: state, routine: r, day: today),
                )),
            if (resting.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('오늘은 쉬는 날',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ...resting.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RestingTile(routine: r),
                  )),
            ],
          ],
        );
      },
    );
  }
}

/// 날짜 + 오늘 진행 요약 헤더
class _TodayHeader extends StatelessWidget {
  final DateTime today;
  final int done;
  final int total;
  const _TodayHeader(
      {required this.today, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allDone = total > 0 && done == total;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('M월 d일 EEEE', 'ko').format(today),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                allDone
                    ? '오늘 도장 다 찍었어요! 🎉'
                    : '오늘 인증할 습관 $done / $total',
                style: TextStyle(
                  color: allDone ? AppTheme.stamp : cs.onSurfaceVariant,
                  fontWeight: allDone ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        if (allDone) const StampMark(size: 46, filledCheck: true),
      ],
    );
  }
}

/// 오늘의 습관 명언 (내장 + 웹 관리자 등록분)
class _QuoteCard extends StatelessWidget {
  const _QuoteCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Quote>(
      future: QuoteService.instance.today(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final q = snap.data!;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5C7CFA), Color(0xFF3B5BDB)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“ ${q.text} ”',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF8A75),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    q.author,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final AppState state;
  final Routine routine;
  final DateTime day;
  const _RoutineCard(
      {required this.state, required this.routine, required this.day});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final certified = state.isCertified(routine.id, day);
    final deadline = routine.deadlineOf(day);
    final remaining = deadline.difference(DateTime.now());
    final urgent = !certified && !remaining.isNegative && remaining.inHours < 3;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: certified
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CertifyScreen(
                        state: state, routine: routine, day: day),
                  ),
                ),
        onLongPress: () => _showManageSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 좌측: 인증 전 = 카메라 원형 버튼 / 인증 후 = 인주색 도장
              certified
                  ? const StampMark(size: 50, filledCheck: true)
                  : Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(alpha: 0.10),
                      ),
                      child: Icon(Icons.photo_camera_outlined,
                          color: cs.primary, size: 24),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                color: certified
                                    ? cs.onSurfaceVariant
                                    : cs.onSurface,
                              ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _TypeBadge(type: routine.type),
                        const SizedBox(width: 6),
                        _DeadlineChip(
                          certified: certified,
                          remaining: remaining,
                          urgent: urgent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    // 성취 완성도 % + D-day
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value:
                                  state.progressPercent(routine.id) / 100,
                              minHeight: 5,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: AppTheme.stamp,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.progressPercent(routine.id)}% · D-${routine.daysLeft(DateTime.now()).clamp(0, 999)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!certified)
                Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _showManageSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(routine.title),
              subtitle: Text(
                  '${routine.type.label} · ${routine.dutyCycle.label}'
                  '${routine.reason.isNotEmpty ? '\n"${routine.reason}"' : ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('루틴 삭제'),
              onTap: () async {
                Navigator.pop(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('삭제할까요?'),
                    content: const Text('이 루틴과 인증 기록이 함께 삭제됩니다.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('삭제')),
                    ],
                  ),
                );
                if (ok == true) await state.deleteRoutine(routine.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 마감 카운트다운 칩
class _DeadlineChip extends StatelessWidget {
  final bool certified;
  final Duration remaining;
  final bool urgent;
  const _DeadlineChip(
      {required this.certified,
      required this.remaining,
      required this.urgent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    late final String label;
    late final Color bg;
    late final Color fg;
    if (certified) {
      label = '오늘 인증 완료';
      bg = AppTheme.stampSoft;
      fg = AppTheme.stamp;
    } else if (remaining.isNegative) {
      label = '마감 지남 · 미인증';
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    } else if (urgent) {
      label = '⏰ ${_fmt(remaining)} 남음';
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    } else {
      label = '마감까지 ${_fmt(remaining)}';
      bg = cs.primary.withValues(alpha: 0.08);
      fg = cs.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }
}

class _RestingTile extends StatelessWidget {
  final Routine routine;
  const _RestingTile({required this.routine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        leading: Icon(Icons.bedtime_outlined, color: cs.onSurfaceVariant),
        title: Text(routine.title),
        subtitle: Text(routine.dutyCycle.label),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final RoutineType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAccum = type == RoutineType.accumulate;
    final color =
        isAccum ? cs.primary.withValues(alpha: 0.10) : const Color(0xFFFFF3E6);
    final onColor = isAccum ? cs.primary : const Color(0xFFB05E00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(type.label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: onColor)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StampMark(size: 88),
            const SizedBox(height: 24),
            Text('아직 선언한 습관이 없어요',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('오른쪽 아래 + 버튼으로 첫 습관을 선언해 보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.6)),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.stampSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '작심삼일? 3일이 아니라 63일, 그리고 평생.',
                style: TextStyle(
                  color: AppTheme.stamp,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
