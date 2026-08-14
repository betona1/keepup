import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/account_service.dart';
import '../services/media_store.dart';
import '../services/quote_service.dart';
import '../theme.dart';
import '../widgets/cert_photo.dart';
import '../widgets/cloud_sync_sheet.dart';
import '../widgets/marquee_text.dart';
import '../widgets/routine_icon.dart';
import 'certify_screen.dart';
import 'history_screen.dart' show showCertDetail;
import 'retro_screen.dart';

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

        final canCertify = state.dutyRoutinesForDay(today);
        // 오늘의 목표 = 오늘이 실제 의무/마감일인 루틴 (적립형 매일/주6일 + 결과형 마감일)
        final todayDuty =
            canCertify.where((r) => r.isDutyDay(today)).toList();
        // 진행 중인 목표 = 결과형인데 아직 마감 전 (기간 내 미리 인증 가능, 오늘 목표엔 미포함)
        final ongoing =
            canCertify.where((r) => !r.isDutyDay(today)).toList();
        final resting = state.routines
            .where((r) => !r.canCertifyOn(today) && !r.isEnded(today))
            .toList();
        // 결과형 목표 — 잊지 않도록 상단에 전광판처럼 흐른다
        final resultGoals = state.routines
            .where((r) => r.isResultCycle && !r.isEnded(today))
            .toList();
        final done = todayDuty
            .where((r) => state.isCertified(r.id, r.dutyKeyDate(today)))
            .length;
        final photos = state.recentPhotoCerts(); // 전체 — 갤러리가 아래로 쭉 이어진다
        final ended = state.endedRoutines(today);
        // 4단계부터 홈 전체에 레벨 오라가 깔린다 (4 골드 / 5 코스믹)
        final auraLevel = state.maxStampLevel();

        final list = ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            _GreetingHeader(today: today, state: state),
            const SizedBox(height: 14),
            if (state.routines.isEmpty)
              _EmptyState()
            else ...[
              // 끝난 시즌은 오늘의 루틴에서 사라지므로, 회고 카드로 마무리를 남긴다
              ...ended.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RetroBanner(state: state, routine: r),
                  )),
              _StreakCard(streak: state.dayStreak()),
              const SizedBox(height: 12),
              if (todayDuty.isNotEmpty) ...[
                _DailyGoalBar(done: done, total: todayDuty.length),
                const SizedBox(height: 12),
              ],
              if (resultGoals.isNotEmpty) ...[
                _ResultGoalMarquee(goals: resultGoals, today: today),
                const SizedBox(height: 12),
              ],
              const _QuoteCard(),
              const SizedBox(height: 20),
              Text('오늘의 루틴',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...todayDuty.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child:
                        _RoutineCard(state: state, routine: r, day: today),
                  )),
              if (todayDuty.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('오늘 꼭 할 루틴은 없어요. 쉬어가거나 미리 해둬도 좋아요 🍃',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              // 진행 중인 목표 — 결과형(주1회/15일/1회성), 마감 전 미리 인증 가능
              if (ongoing.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('진행 중인 목표',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 6),
                    Text('· 마감 전 언제든 인증',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 10),
                ...ongoing.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RoutineCard(
                          state: state, routine: r, day: today),
                    )),
              ],
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
                Text('인증 갤러리 (${photos.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _GalleryGrid(state: state, certs: photos),
              ],
            ],
          ],
        );

        if (auraLevel < 4) return list;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LevelAuraPainter(
                    level: auraLevel,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
            ),
            list,
          ],
        );
      },
    );
  }
}

/// 레벨 카드 테두리 — 2·3단계는 정적 그라데이션, 4단계는 3색 플레임,
/// 5단계는 오로라 그라데이션이 테두리를 따라 천천히 도는 애니메이션 (최고 단계의 품격).
class _LevelCardFrame extends StatefulWidget {
  final int level;
  final Widget child;
  const _LevelCardFrame({required this.level, required this.child});

  @override
  State<_LevelCardFrame> createState() => _LevelCardFrameState();
}

class _LevelCardFrameState extends State<_LevelCardFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.level >= 5) {
      _ctrl = AnimationController(
          vsync: this, duration: const Duration(seconds: 6))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  BoxDecoration _decoration(List<Color> colors, double t) => BoxDecoration(
        borderRadius: BorderRadius.circular(21.5),
        gradient: widget.level >= 5
            // 오로라가 테두리를 따라 흐른다
            ? SweepGradient(
                colors: [...colors, colors.first],
                transform: GradientRotation(t * 2 * math.pi),
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(
                alpha: widget.level >= 4 ? 0.40 : (widget.level >= 3 ? 0.32 : 0.18)),
            blurRadius: widget.level >= 4 ? 20 : (widget.level >= 3 ? 16 : 10),
            offset: const Offset(0, 4),
          ),
          if (widget.level >= 5)
            BoxShadow(
              color: colors.first.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, -2),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.stampRingColors(widget.level);
    final pad = EdgeInsets.all(widget.level >= 5 ? 2.4 : widget.level >= 4 ? 2.0 : 1.6);
    final ctrl = _ctrl;
    if (ctrl == null) {
      return Container(
        decoration: _decoration(colors, 0),
        padding: pad,
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) => Container(
        decoration: _decoration(colors, ctrl.value),
        padding: pad,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// 4·5단계 홈 배경 오라 — 화면 곳곳에 은은한 빛 무리가 깔린다.
/// 4단계: 초사이언 골드 기운 / 5단계: 코스믹 오로라 + 별가루 (최고로 화려하게)
class _LevelAuraPainter extends CustomPainter {
  final int level;
  final bool dark;
  const _LevelAuraPainter({required this.level, required this.dark});

  // 별가루 위치 (화면 비율 좌표, 매 프레임 같은 자리 — 깜빡임 없음)
  static const _stars = [
    (0.08, 0.10, 1.6), (0.22, 0.04, 1.0), (0.38, 0.13, 1.3),
    (0.55, 0.06, 1.0), (0.72, 0.11, 1.8), (0.88, 0.05, 1.1),
    (0.94, 0.20, 1.4), (0.12, 0.30, 1.0), (0.83, 0.34, 1.2),
    (0.05, 0.52, 1.5), (0.93, 0.55, 1.0), (0.15, 0.72, 1.2),
    (0.87, 0.76, 1.6), (0.45, 0.88, 1.0), (0.70, 0.93, 1.3),
    (0.25, 0.95, 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final strength = dark ? 1.0 : 0.55; // 라이트 모드에선 은은하게
    List<(Alignment, Color, double)> blobs;
    if (level >= 5) {
      blobs = [
        (Alignment.topRight, const Color(0xFF7C5CFF), 0.20),
        (Alignment.topLeft, const Color(0xFF3FA9FF), 0.14),
        (Alignment.centerRight, const Color(0xFF7CF7FF), 0.10),
        (Alignment.bottomLeft, const Color(0xFF9E7BFF), 0.14),
      ];
    } else {
      blobs = [
        (Alignment.topRight, const Color(0xFFFFC24D), 0.16),
        (Alignment.topLeft, const Color(0xFFFF9A3D), 0.10),
        (Alignment.bottomRight, const Color(0xFFFFE066), 0.09),
      ];
    }

    for (final (align, color, alpha) in blobs) {
      final center = Offset(
        size.width * (align.x + 1) / 2,
        size.height * (align.y + 1) / 2,
      );
      final radius = size.width * 0.75;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha * strength),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    // 5단계 전용 별가루 — 우주에 온 듯한 마무리
    if (level >= 5) {
      final starPaint = Paint()
        ..color = (dark ? Colors.white : const Color(0xFF7C5CFF))
            .withValues(alpha: dark ? 0.55 : 0.30);
      final glowPaint = Paint()
        ..color = const Color(0xFF7CF7FF).withValues(alpha: dark ? 0.30 : 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final (fx, fy, r) in _stars) {
        final o = Offset(size.width * fx, size.height * fy);
        canvas.drawCircle(o, r * 2.4, glowPaint);
        canvas.drawCircle(o, r, starPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_LevelAuraPainter old) =>
      old.level != level || old.dark != dark;
}

/// 인사 + 날짜 + 웹 계정 프로필 (Stitch 대시보드 헤더)
class _GreetingHeader extends StatelessWidget {
  final DateTime today;
  final AppState state;
  const _GreetingHeader({required this.today, required this.state});

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
        // 로그인 상태 표시 + 게시판 공개·클라우드 백업의 진입점.
        // 브라우저에서도 보여준다 (웹은 로그인 방법이 '페이지 이동' 하나뿐이라 시트를 건너뛴다).
        ProfileAvatar(
          onOpenCloudSync: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => CloudSyncSheet(state: state),
          ),
        ),
      ],
    );
  }
}

/// 웹 계정 아바타 — 로그인하면 프로필, 안 하면 기본 아이콘 (탭: 로그인/계정)
class ProfileAvatar extends StatefulWidget {
  /// 계정 시트에서 '클라우드 백업'을 눌렀을 때 (없으면 항목을 눌러도 동작하지 않음)
  final VoidCallback? onOpenCloudSync;
  const ProfileAvatar({super.key, this.onOpenCloudSync});

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
      // 브라우저는 Custom Tab·구글 원탭을 쓸 수 없어 로그인 페이지로 이동한다
      if (kIsWeb) {
        AccountService.instance.loginViaPage();
        return;
      }
      await _showLoginChooser();
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
            // 기록은 기기에 저장되므로, 로그인한 사람에게 '계정에 보관' 경로를 여기서 알려준다
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('클라우드 백업'),
              subtitle: const Text('기록을 계정에 보관 · 다른 기기에서 복원'),
              onTap: () {
                Navigator.pop(sheetCtx);
                widget.onOpenCloudSync?.call();
              },
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

  /// 로그인 방법 선택 시트 — 기기 구글계정 원탭 / 브라우저(카카오·네이버·이메일)
  Future<void> _showLoginChooser() async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('로그인',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('성과 게시판에 자랑할 때만 로그인해요. 앱은 로그인 없이도 완전 동작해요.',
                    style: TextStyle(
                        fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: const Text('G',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Color(0xFF4285F4))),
              ),
              title: const Text('Google 계정으로 로그인'),
              subtitle: const Text('이 기기 계정으로 바로 · 비밀번호 불필요'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
            ListTile(
              leading: Icon(Icons.public, color: cs.primary),
              title: const Text('카카오 · 네이버 · 이메일'),
              subtitle: const Text('브라우저로 로그인'),
              onTap: () => Navigator.pop(ctx, 'web'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final ok = choice == 'google'
        ? await AccountService.instance.loginWithGoogleNative()
        : await AccountService.instance.login();
    if (ok) {
      await _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 취소됐거나 실패했어요. 다시 시도해 주세요.')),
      );
    }
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

/// 시즌 종료 배너 — 완주한 루틴의 회고 카드로 안내
class _RetroBanner extends StatelessWidget {
  final AppState state;
  final Routine routine;
  const _RetroBanner({required this.state, required this.routine});

  @override
  Widget build(BuildContext context) {
    final percent = state.progressPercent(routine.id);
    final done = state.certifiedDayCount(routine.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openRetroCard(context, state, routine),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4669F0), Color(0xFF274ED5)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const StampMark(size: 44, filledCheck: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🎉 시즌이 끝났어요!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${routine.title} · 도장 $done개 · 달성률 $percent%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '회고 카드를 확인하고 자랑해 보세요',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
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

/// 결과형 목표 전광판 — "1주일에 1개 앱 만들기" 처럼 선언한 목표가 흘러가
/// 잊지 않도록 상단에 항상 떠 있다. (기획서: 결과형 등록분 리마인더)
class _ResultGoalMarquee extends StatelessWidget {
  final List<Routine> goals;
  final DateTime today;
  const _ResultGoalMarquee({required this.goals, required this.today});

  @override
  Widget build(BuildContext context) {
    // 각 목표를 "🎯 제목 · D-n" 형태로, 임박할수록 눈에 띄게
    final parts = goals.map((r) {
      final due = r.dutyKeyDate(today);
      final dLeft = due.difference(today).inDays;
      final dTag = dLeft <= 0 ? '오늘 마감' : 'D-$dLeft';
      return '🎯 ${r.title} · $dTag';
    }).join('        ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.stampSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.stamp.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 17, color: AppTheme.stamp),
          const SizedBox(width: 8),
          Expanded(
            child: MarqueeText(
              text: parts,
              speed: 30,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.stamp,
              ),
            ),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 결과형은 현재 주기 마감일 기준으로 인증·마감 계산
    final effDay = routine.dutyKeyDate(day);
    final certified = state.isCertified(routine.id, effDay);
    // 결과형(목표형)은 한 주기에 여러 번 인증 가능 — 인증돼도 카드가 잠기지 않음
    final locked = certified && !routine.isResultCycle;
    final deadline = routine.deadlineOf(effDay);
    final remaining = deadline.difference(DateTime.now());
    final urgent = !certified && !remaining.isNegative && remaining.inHours < 3;
    final doneDays = state.certifiedDayCount(routine.id);
    final totalDays = routine.totalDutyDays();
    // 이번 주기 인증 횟수 (결과형 여러 번 인증 표시용)
    final cycleCount = routine.isResultCycle
        ? state
            .certsForRoutine(routine.id)
            .where((c) => c.dateKey == dateKeyOf(effDay))
            .length
        : 0;
    // 도장 레벨 — 1주 2단계 · 3주 3단계 · 6주 4단계 · 10주 5단계. 카드가 함께 화려해진다.
    final level = state.levelFor(routine.id);
    final ringColors = AppTheme.stampRingColors(level);
    // 4·5단계는 원화 4장을 돌려 쓴다 — 날마다 바브바브 포즈가 바뀐다
    final variant = AppTheme.dailyVariant();

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 인증 완료 카드도 탭할 수 있다 — 저장된 인증을 열어
        // 공유(놓쳤어도 다시!)·다시 인증·삭제가 가능하다.
        onTap: locked
            ? () {
                final todayCerts = state
                    .certsForRoutine(routine.id)
                    .where((c) => c.dateKey == dateKeyOf(effDay))
                    .toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
                if (todayCerts.isEmpty) return;
                showCertDetail(context, todayCerts.first, routine,
                    state: state);
              }
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
              // 좌측: 아이콘 타일 — 탭하면 인증사진/갤러리 사진으로 꾸미기
              GestureDetector(
                onTap: () => showRoutineIconPicker(context, state, routine),
                child: RoutineIconTile(
                    routine: routine, level: level, variant: variant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            routine.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontSize: 15.5,
                                  color: certified
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 2단계부터 레벨 배지 (도장 링과 같은 그라데이션, 4단계부터 발광)
                        if (level >= 2) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: ringColors),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: level >= 4
                                  ? [
                                      BoxShadow(
                                        color: ringColors.last
                                            .withValues(alpha: 0.55),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              AppTheme.levelBadge(level),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: level == 4
                                    ? const Color(0xFF4A2E00)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$doneDays / $totalDays일'
                      '${cycleCount > 0 ? ' · 이번 주기 $cycleCount회 인증' : ''}'
                      '${routine.hasWindow ? ' · 🌅 ${routine.windowLabel}' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    // 결과형은 인증돼도 "또 인증할 수 있어요" 안내
                    (certified && routine.isResultCycle)
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('✅ 이번 주기 인증됨 · 또 인증 가능',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.success)),
                          )
                        : _DeadlineChip(
                            certified: certified,
                            remaining: remaining,
                            urgent: urgent,
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 우측: 도장 버튼 (Stitch: STAMP / UP!). 결과형은 인증돼도 +로 추가 인증 유도
              (certified && routine.isResultCycle)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StampButton(
                            certified: true, level: level, variant: variant),
                        const SizedBox(height: 2),
                        Icon(Icons.add_circle,
                            size: 18, color: cs.primary),
                      ],
                    )
                  : StampButton(
                      certified: certified, level: level, variant: variant),
            ],
          ),
        ),
      ),
    );

    // 2단계부터 카드 테두리가 레벨 색 그라데이션으로 빛난다
    // (4단계 플레임 3색 / 5단계는 오로라가 테두리를 따라 흐르는 애니메이션)
    if (level < 2) return card;
    return _LevelCardFrame(level: level, child: card);
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
              leading: const Icon(Icons.event_available),
              title: const Text('시작일 변경'),
              subtitle: Text(
                  '현재: ${routine.startDate.year}.${routine.startDate.month.toString().padLeft(2, '0')}.${routine.startDate.day.toString().padLeft(2, '0')}'),
              onTap: () async {
                Navigator.pop(context);
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: routine.startDate,
                  firstDate: today.subtract(const Duration(days: 365)),
                  lastDate: today,
                  helpText: '시작일 변경 (지난 날짜로 소급 가능)',
                );
                if (picked != null) {
                  await state.updateStartDate(routine.id, picked);
                }
              },
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

/// 인증 사진 갤러리 — 한 줄 3장씩 아래로 쭉 이어지는 세로 그리드.
/// 홈 전체가 스크롤(ListView)이므로 그리드 자체는 스크롤하지 않는다.
class _GalleryGrid extends StatelessWidget {
  final AppState state;
  final List<Certification> certs;
  const _GalleryGrid({required this.state, required this.certs});

  @override
  Widget build(BuildContext context) {
    final visible =
        certs.where((c) => MediaStore.existsSync(c.photoPath)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 한 줄에 3장
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1, // 정사각
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final c = visible[i];
        return InkWell(
          onTap: () =>
              showCertDetail(context, c, state.routineById(c.routineId)),
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                // 썸네일 해상도로만 디코드 — 사진이 많아도 가볍게
                child: CertPhoto(
                    path: c.photoPath, fit: BoxFit.cover, cacheWidth: 360),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    DateFormat('MM.dd').format(c.timestamp),
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
