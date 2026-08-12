import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 앱을 열면 3초간 재생되는 인트로.
///
/// 바브바브가 오늘의 습관을 하나씩 해내고 도장이 쾅쾅 찍힌다 —
/// **달리기(건강) · 공부하기(자기계발) · 식단관리(다이어트)** 세 갈래를 보여줘서
/// "이 앱이 무슨 앱인지"를 첫 3초에 그림으로 전달한다(이탈 방어).
///
/// 배경은 라이트/다크와 무관하게 캐릭터 원화와 같은 딥 네이비로 고정한다.
/// 화면을 탭하면 즉시 건너뛴다.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  /// 인트로 총 길이
  static const duration = Duration(milliseconds: 3000);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// 인트로에 등장하는 습관 한 갈래
class _Habit {
  final IconData icon;
  final String title;
  final String tag;
  final Color color;
  final double at; // 등장 시점 (전체 진행률)
  const _Habit(this.icon, this.title, this.tag, this.color, this.at);
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _finished = false;

  static const _habits = [
    _Habit(Icons.directions_run_rounded, '달리기', '건강', AppTheme.seedBright, 0.30),
    _Habit(Icons.menu_book_rounded, '공부하기', '자기계발', AppTheme.stampAccent, 0.44),
    _Habit(Icons.restaurant_rounded, '식단관리', '다이어트', AppTheme.success, 0.58),
  ];

  /// 도장은 배지가 뜨고 조금 뒤에 찍힌다
  static const _stampDelay = 0.085;

  // 반짝임 — 위치를 고정값으로 둬서 프레임마다 흔들리지 않게 한다
  static const _sparkles = [
    Offset(-0.72, -0.62),
    Offset(0.66, -0.70),
    Offset(-0.88, 0.06),
    Offset(0.90, -0.04),
    Offset(-0.40, 0.52),
    Offset(0.34, 0.60),
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: SplashScreen.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [a]~[b] 구간을 0~1로 정규화 (구간 밖은 0 또는 1)
  double _seg(double t, double a, double b, {Curve curve = Curves.easeOut}) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return curve.transform((t - a) / (b - a));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _finish, // 탭하면 바로 건너뛰기
      behavior: HitTestBehavior.opaque,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // 인트로는 어두운 화면이므로 상태바·내비게이션바도 어둡게 맞춘다
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: AppTheme.navyDeep,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          // 캐릭터 일러스트가 깔고 있는 배경과 같은 톤 — 이미지 경계가 보이지 않게
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 0.95,
              colors: [AppTheme.navy, AppTheme.navyDeep],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                // 마지막 12%는 전체가 서서히 사라지며 앱 화면으로 넘어간다
                final exit = 1 - _seg(t, 0.88, 1.0, curve: Curves.easeIn);
                return Opacity(
                  opacity: exit,
                  child: LayoutBuilder(
                    builder: (context, box) => _stage(t, box.biggest),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage(double t, Size size) {
    // 캐릭터 + 습관 배지 3개 + 워드마크가 한 화면에 들어가도록 크기를 잡는다
    final charH = math.min(size.height * 0.32, 300.0);
    final charW = charH * (900 / 1171);
    final stageW = math.min(charW * 1.9, size.width - 24);

    // ① 등장: 아래에서 튀어오르며 커진다
    final enter = _seg(t, 0.02, 0.28, curve: Curves.easeOutBack);
    // ② 열심히 하는 중: 위아래로 통통 (등장 후 계속)
    final workT = ((t - 0.20) / 0.64).clamp(0.0, 1.0);
    final hop = t < 0.20 ? 0.0 : math.sin(workT * math.pi * 5) * 0.5 + 0.5;
    final hopY = -hop * charH * 0.05;
    final tilt =
        t < 0.20 ? 0.0 : math.sin(workT * math.pi * 5 + math.pi / 3) * 0.04;

    final badgeW = math.min((size.width - 56) / 3, 118.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        _glow(t, size),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 캐릭터 ──
            SizedBox(
              width: stageW,
              height: charH * 1.12,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: Offset(0, (1 - enter) * charH * 0.55 + hopY),
                    child: Transform.rotate(
                      angle: tilt,
                      child: Opacity(
                        opacity: _seg(t, 0.02, 0.16),
                        child: Transform.scale(
                          scale: 0.72 + enter * 0.28,
                          child: Image.asset(
                            AppTheme.fullAsset,
                            height: charH,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < _sparkles.length; i++)
                    _sparkle(t, i, stageW, charH),
                ],
              ),
            ),

            SizedBox(height: charH * 0.10),

            // ── 오늘의 습관 3종 — 하나씩 뜨고 도장이 찍힌다 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _habits.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  _badge(t, _habits[i], badgeW),
                ],
              ],
            ),

            SizedBox(height: charH * 0.13),

            // ── 워드마크 ──
            Opacity(
              opacity: _seg(t, 0.70, 0.86),
              child: Transform.translate(
                offset: Offset(0, (1 - _seg(t, 0.70, 0.86)) * 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontFamily: 'NanumGothic',
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          TextSpan(
                              text: 'Log',
                              style: TextStyle(color: AppTheme.stampAccent)),
                          TextSpan(
                              text: 'Challenge',
                              style: TextStyle(color: AppTheme.seedBright)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '오늘도 하나, 도장 쾅!',
                      style: TextStyle(
                        fontFamily: 'NanumGothic',
                        color: Color(0xFF9FB4D8),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 습관 배지 하나 — 팝업으로 뜬 뒤, 오른쪽 위에 도장이 '쾅' 찍힌다
  Widget _badge(double t, _Habit h, double width) {
    final pop = _seg(t, h.at, h.at + 0.10, curve: Curves.easeOutBack);
    final stampAt = h.at + _stampDelay;
    final press = _seg(t, stampAt, stampAt + 0.09, curve: Curves.easeOutCubic);
    final done = press > 0;

    return Opacity(
      opacity: _seg(t, h.at, h.at + 0.06),
      child: Transform.scale(
        scale: 0.62 + pop * 0.38,
        child: SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity, // Stack 안에서도 배지 폭을 꽉 채운다
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.navySoft.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: h.color.withValues(alpha: done ? 0.85 : 0.35),
                    width: done ? 1.6 : 1,
                  ),
                  boxShadow: done
                      ? [
                          BoxShadow(
                            color: h.color.withValues(alpha: 0.28),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(h.icon, size: 26, color: h.color),
                    const SizedBox(height: 6),
                    Text(
                      h.title,
                      style: const TextStyle(
                        fontFamily: 'NanumGothic',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE7ECF7),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      h.tag,
                      style: const TextStyle(
                        fontFamily: 'NanumGothic',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8DA1C2),
                      ),
                    ),
                  ],
                ),
              ),
              // 완료 도장 — 크게 나타나 눌러 찍히듯 자리를 잡는다
              if (done)
                Positioned(
                  right: -8,
                  top: -10,
                  child: Transform.rotate(
                    angle: (1 - press) * 0.6 - 0.10,
                    child: Transform.scale(
                      scale: 2.0 - 1.0 * press,
                      child: const StampMark(size: 36, filledCheck: true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 배경 네온 글로우 — 캐릭터 뒤에서 서서히 퍼진다
  Widget _glow(double t, Size size) {
    final g = _seg(t, 0.0, 0.45);
    final side = math.max(size.width, size.height);
    return Transform.translate(
      offset: Offset(0, -size.height * 0.12),
      child: Container(
        width: side * (0.5 + g * 0.3),
        height: side * (0.5 + g * 0.3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppTheme.seedBright.withValues(alpha: 0.34 * g),
              AppTheme.stamp.withValues(alpha: 0.16 * g),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }

  /// 반짝임 — 캐릭터 주변에서 톡톡 터진다
  Widget _sparkle(double t, int i, double stageW, double charH) {
    final start = 0.24 + i * 0.05;
    final life = _seg(t, start, start + 0.24, curve: Curves.easeOut);
    if (life <= 0 || life >= 1) return const SizedBox.shrink();
    final fade = math.sin(life * math.pi); // 나타났다 사라지는 곡선
    final pos = _sparkles[i];
    final s = 5.0 + (i % 3) * 3.0;

    return Transform.translate(
      offset: Offset(
        pos.dx * (stageW / 2 - s),
        pos.dy * (charH * 0.5) - life * 12,
      ),
      child: Opacity(
        opacity: fade,
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i.isEven ? AppTheme.neon : AppTheme.stampAccent,
            boxShadow: [
              BoxShadow(
                color: (i.isEven ? AppTheme.neon : AppTheme.stampAccent)
                    .withValues(alpha: 0.7),
                blurRadius: s * 1.6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
