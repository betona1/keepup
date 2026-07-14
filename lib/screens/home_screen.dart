import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/account_service.dart';
import '../services/quote_service.dart';
import '../theme.dart';
import 'certify_screen.dart';
import 'history_screen.dart' show showCertDetail;
import 'web_login_screen.dart';

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

        final duty = state.dutyRoutinesForDay(today);
        final resting = state.routines
            .where((r) => !r.canCertifyOn(today) && !r.isEnded(today))
            .toList();
        final done = duty
            .where((r) => state.isCertified(r.id, r.dutyKeyDate(today)))
            .length;
        final photos = state.recentPhotoCerts();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            _GreetingHeader(today: today),
            const SizedBox(height: 14),
            if (state.routines.isEmpty)
              _EmptyState()
            else ...[
              _StreakCard(streak: state.dayStreak()),
              const SizedBox(height: 12),
              if (duty.isNotEmpty) ...[
                _DailyGoalBar(done: done, total: duty.length),
                const SizedBox(height: 12),
              ],
              const _QuoteCard(),
              const SizedBox(height: 20),
              Text('오늘의 루틴',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...duty.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child:
                        _RoutineCard(state: state, routine: r, day: today),
                  )),
              if (duty.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('오늘 인증할 루틴이 없어요. 쉬어가는 날! 🍃',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
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
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('인증 갤러리',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _GalleryStrip(state: state, certs: photos),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// 인사 + 날짜 + 웹 계정 프로필 (Stitch 대시보드 헤더)
class _GreetingHeader extends StatelessWidget {
  final DateTime today;
  const _GreetingHeader({required this.today});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return '고요한 새벽이에요 🌙';
    if (h < 12) return '좋은 아침이에요 ☀️';
    if (h < 18) return '힘차게 가는 오후! 💪';
    return '오늘 하루 마무리 잘해요 🌆';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                DateFormat('M월 d일 EEEE', 'ko').format(today),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 22),
              ),
            ],
          ),
        ),
        const ProfileAvatar(),
      ],
    );
  }
}

/// 웹 계정 아바타 — 로그인하면 프로필, 안 하면 기본 아이콘 (탭: 로그인/계정)
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({super.key});

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  WebAccount? _account;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await AccountService.instance.me();
    if (mounted) {
      setState(() {
        _account = a;
        _loaded = true;
      });
    }
  }

  Future<void> _onTap() async {
    if (_account == null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const WebLoginScreen()),
      );
      if (ok == true) await _refresh();
      return;
    }
    // 로그인 상태 → 계정 시트
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _avatarCircle(36),
              title: Text(_account!.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'keywordream 계정${_account!.role == 'admin' ? ' · 관리자' : ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('로그아웃'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await AccountService.instance.logout();
                await _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarCircle(double size) {
    final cs = Theme.of(context).colorScheme;
    final url = _account?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar(size, cs)),
      );
    }
    if (_account != null) {
      return Container(
        width: size,
        height: size,
        decoration:
            BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(_account!.name.characters.first,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      );
    }
    return _defaultAvatar(size, cs);
  }

  Widget _defaultAvatar(double size, ColorScheme cs) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(Icons.person_outline,
            size: size * 0.6, color: cs.onSurfaceVariant),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return _defaultAvatar(40, Theme.of(context).colorScheme);
    return InkWell(
      onTap: _onTap,
      customBorder: const CircleBorder(),
      child: _avatarCircle(40),
    );
  }
}

/// 연속 도장 카드 (Stitch: Current Best Streak)
class _StreakCard extends StatelessWidget {
  final int streak;
  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('연속 도장',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                  const SizedBox(height: 4),
                  Text('$streak일',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontSize: 28)),
                ],
              ),
            ),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.military_tech_outlined,
                  color: cs.primary, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오늘의 목표 진행바 (Stitch: Daily Goal — 인주색 바)
class _DailyGoalBar extends StatelessWidget {
  final int done;
  final int total;
  const _DailyGoalBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('오늘의 목표',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('${(pct * 100).round()}%',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 9,
            backgroundColor: AppTheme.stampSoft,
            color: AppTheme.stampAccent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          done == total
              ? '오늘 도장 다 찍었어요! 🎉'
              : '오늘 $total개 중 $done개 완료 — 계속 가요!',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
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
              colors: [Color(0xFF4669F0), Color(0xFF274ED5)],
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
                      color: AppTheme.stampAccent,
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

  IconData get _methodIcon => switch (routine.verifyMethod) {
        VerifyMethod.photo => Icons.photo_camera_outlined,
        VerifyMethod.timer => Icons.timer_outlined,
        VerifyMethod.audio => Icons.mic_none_rounded,
        VerifyMethod.video => Icons.videocam_outlined,
        VerifyMethod.steps => Icons.directions_walk_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 결과형은 현재 주기 마감일 기준으로 인증·마감 계산
    final effDay = routine.dutyKeyDate(day);
    final certified = state.isCertified(routine.id, effDay);
    final deadline = routine.deadlineOf(effDay);
    final remaining = deadline.difference(DateTime.now());
    final urgent = !certified && !remaining.isNegative && remaining.inHours < 3;
    final doneDays = state.certifiedDayCount(routine.id);
    final totalDays = routine.totalDutyDays();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: certified
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CertifyScreen(
                        state: state, routine: routine, day: effDay),
                  ),
                ),
        onLongPress: () => _showManageSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              // 좌측: 검증 방식 아이콘 필 (Stitch 스타일)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_methodIcon, color: cs.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 15.5,
                                color: certified
                                    ? cs.onSurfaceVariant
                                    : cs.onSurface,
                              ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$doneDays / $totalDays일'
                      '${routine.hasWindow ? ' · 🌅 ${routine.windowLabel}' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    _DeadlineChip(
                      certified: certified,
                      remaining: remaining,
                      urgent: urgent,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 우측: 도장 버튼 (Stitch: STAMP / UP!)
              StampButton(certified: certified),
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
              leading: const Icon(Icons.event_repeat),
              title: const Text('완료 목표일 변경'),
              subtitle: Text(
                  '현재: ${routine.endDate.year}.${routine.endDate.month.toString().padLeft(2, '0')}.${routine.endDate.day.toString().padLeft(2, '0')}'),
              onTap: () async {
                Navigator.pop(context);
                final minEnd =
                    routine.startDate.add(const Duration(days: 29));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: routine.endDate.isBefore(minEnd)
                      ? minEnd
                      : routine.endDate,
                  firstDate: minEnd,
                  lastDate:
                      routine.startDate.add(const Duration(days: 1460)),
                  helpText: '완료 목표일 변경 (최소 30일 시즌)',
                );
                if (picked != null) {
                  await state.updateEndDate(routine.id, picked);
                }
              },
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
    if (d.inDays > 0) return '${d.inDays}일 ${d.inHours % 24}시간';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }
}

/// 최근 인증 사진 가로 스트립 (Stitch: Certification Gallery)
class _GalleryStrip extends StatelessWidget {
  final AppState state;
  final List<Certification> certs;
  const _GalleryStrip({required this.state, required this.certs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: certs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = certs[i];
          final file = File(c.photoPath);
          if (!file.existsSync()) return const SizedBox.shrink();
          return InkWell(
            onTap: () =>
                showCertDetail(context, c, state.routineById(c.routineId)),
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(file,
                      width: 150, height: 110, fit: BoxFit.cover),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      DateFormat('MM.dd HH:mm').format(c.timestamp),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
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
    );
  }
}
