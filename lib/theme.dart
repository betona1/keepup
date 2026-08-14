import 'package:flutter/material.dart';

/// Log Challenge 디자인 시스템 — **바브바브(VAVEVAVE) 캐릭터 팔레트** (2026-08-07 적용)
///
/// 색은 캐릭터 원화에서 그대로 가져왔다.
/// - 네온 블루: 이마 문양·홀로그램의 빛 → 브랜드/주요 액션
/// - 바이올렛: 눈동자·뿔털의 라벤더 → **도장**(성취) 색
/// - 딥 네이비: 캐릭터가 서 있는 배경 → 다크 테마 바탕
/// - 서체: 네이버 나눔고딕 (번들, 변경 금지)
class AppTheme {
  // ── 캐릭터에서 뽑은 색 ──
  static const seed = Color(0xFF2B6DF6); // 네온 블루 (라이트에서 대비 확보한 톤)
  static const seedBright = Color(0xFF4FA9FF); // 홀로그램 하이라이트
  static const neon = Color(0xFF7ED3FF); // 이마 문양의 밝은 시안

  static const stamp = Color(0xFF7C5CFF); // 도장 = 눈동자·뿔털의 바이올렛
  static const stampAccent = Color(0xFFA88BFF); // 도장 강조(채움)
  static const stampSoft = Color(0xFFEDE7FF); // 도장 옅은 배경 (라이트)
  static const stampSoftDark = Color(0xFF251F45); // 도장 옅은 배경 (다크)

  static const success = Color(0xFF17B7A6); // 완료 청록 (캐릭터 톤에 맞춘 성공색)

  // 캐릭터 배경 네이비 계열
  static const navyDeep = Color(0xFF0B0F1A);
  static const navy = Color(0xFF121926);
  static const navySoft = Color(0xFF1A2436);

  /// 캐릭터 얼굴 에셋 경로 — 도장·로고·아이콘이 모두 이 하나를 쓴다
  static const faceAsset = 'assets/character/vave_face.png';

  /// 4·5단계 얼굴 변형 4장씩 — 날마다 다른 모습의 바브바브가 나타난다.
  static const _face4Variants = [
    'assets/character/vave_face4.png',
    'assets/character/vave_face4b.png',
    'assets/character/vave_face4c.png',
    'assets/character/vave_face4d.png',
  ];
  static const _face5Variants = [
    'assets/character/vave_face5.png',
    'assets/character/vave_face5b.png',
    'assets/character/vave_face5c.png',
    'assets/character/vave_face5d.png',
  ];

  /// 도장 레벨(1~5)별 얼굴 — 도장을 모을수록 바브바브가 성장한다.
  /// 1 후드 / 2 탐구 / 3 마스터 / 4 초사이언(골드) / 5 코스믹 마스터(우주).
  /// 4·5단계는 원화가 4장씩 있어 [variant]로 골라 쓴다 (기본 0).
  static String faceAssetFor(int level, {int variant = 0}) => switch (level) {
        >= 5 => _face5Variants[variant % 4],
        4 => _face4Variants[variant % 4],
        3 => 'assets/character/vave_face3.png',
        2 => 'assets/character/vave_face2.png',
        _ => faceAsset,
      };

  /// 오늘의 얼굴 변형 번호 — 4·5단계 바브바브는 날마다 포즈가 바뀐다.
  static int dailyVariant([DateTime? when]) {
    final d = when ?? DateTime.now();
    return d.difference(DateTime(d.year)).inDays % 4;
  }

  /// 레벨별 도장 링 색
  /// (1 바이올렛 / 2 바이올렛→블루 / 3 골드 / 4 초사이언 플레임 / 5 코스믹 오로라)
  static List<Color> stampRingColors(int level) => switch (level) {
        >= 5 => const [Color(0xFF9E7BFF), Color(0xFF3FA9FF), Color(0xFF7CF7FF)],
        4 => const [Color(0xFFFFF2A6), Color(0xFFFFC24D), Color(0xFFFF7A1A)],
        3 => const [Color(0xFFFFC24D), Color(0xFFFF8A3D)],
        2 => const [Color(0xFF7C5CFF), Color(0xFF37B4FF)],
        _ => const [stamp, stamp],
      };

  /// 레벨 배지 라벨 (2단계부터 카드에 표시)
  static String levelBadge(int level) => switch (level) {
        >= 5 => '🌌 5단계',
        4 => '🔥 4단계',
        3 => '👑 3단계',
        _ => '⭐ 2단계',
      };

  /// 레벨별 글로우 강도 — 올라갈수록 더 화려하게 빛난다
  static double glowAlpha(int level) => switch (level) {
        >= 5 => 0.60,
        4 => 0.50,
        3 => 0.45,
        _ => 0.22,
      };

  /// 캐릭터 전신 에셋 — 스플래시 인트로용
  static const fullAsset = 'assets/character/vave_full.png';

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: seed,
      primaryContainer: seedBright,
      onPrimaryContainer: Colors.white,
      secondary: stamp,
      surface: const Color(0xFFF4F8FF), // 차가운 화이트블루
      surfaceContainerLowest: Colors.white,
      onSurface: const Color(0xFF131826),
      onSurfaceVariant: const Color(0xFF465166),
      outlineVariant: const Color(0xFFCBD7EE),
      tertiary: success,
      tertiaryContainer: const Color(0xFFD3F5F0),
      onTertiaryContainer: const Color(0xFF00443C),
    );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: cs.surface,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E9F8)),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }

  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF6FB6FF),
      primaryContainer: const Color(0xFF1B3E7A),
      onPrimaryContainer: Colors.white,
      secondary: stampAccent,
      surface: navyDeep, // 캐릭터가 서 있던 그 배경
      surfaceContainerLowest: navy,
      surfaceContainerHighest: navySoft,
      onSurface: const Color(0xFFE7ECF7),
      onSurfaceVariant: const Color(0xFF9FAEC8),
      outlineVariant: const Color(0xFF2A3549),
      tertiary: const Color(0xFF5FD8C8),
      tertiaryContainer: const Color(0xFF06413A),
      onTertiaryContainer: const Color(0xFFB6F1E8),
    );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: cs.surface,
      cardTheme: CardThemeData(
        color: navy,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF232F45)),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }

  static ThemeData _base(ColorScheme cs) => ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        fontFamily: 'NanumGothic',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800, height: 1.25),
          titleLarge: TextStyle(fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          labelLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'NanumGothic',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: cs.primary,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: cs.surfaceContainerLowest,
          indicatorColor: cs.primary.withValues(alpha: 0.14),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'NanumGothic',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'NanumGothic',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  /// 테마에 맞는 도장 옅은 배경색
  static Color softStampBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? stampSoftDark
          : stampSoft;
}

/// 바브바브 얼굴 — 원형으로 잘린 캐릭터 이미지 하나. 도장·로고가 공유한다.
///
/// 원본 컷아웃은 턱 아래가 부드럽게 사라지도록 여백을 두고 있어서,
/// 그대로 쓰면 작은 도장 안에서 얼굴이 작아 보인다. [zoom]으로 살짝 당겨 채운다.
class VaveFace extends StatelessWidget {
  final double size;
  final double zoom;
  final int level; // 도장 레벨 (1~5) — 모을수록 바브바브가 성장
  final int variant; // 4·5단계 원화 변형 (0~3)
  const VaveFace({
    super.key,
    required this.size,
    this.zoom = 1.3,
    this.level = 1,
    this.variant = 0,
  });

  @override
  Widget build(BuildContext context) {
    // 2·3단계 원화는 얼굴 여백이 달라 살짝만 당기고,
    // 4·5단계 컷아웃은 이미 얼굴이 꽉 차 있어 거의 당기지 않는다
    final z = level >= 4
        ? 1.04
        : level >= 2
            ? (zoom * 0.85).clamp(1.0, 3.0)
            : zoom;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Transform.scale(
          scale: z,
          alignment: const Alignment(0, -0.12), // 눈이 가운데 오도록 살짝 위로
          child: Image.asset(
            AppTheme.faceAssetFor(level, variant: variant),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Log Challenge 시그니처 도장 — 바이올렛 링 안에 바브바브 얼굴.
/// [filledCheck]가 true면 완료 표시(오른쪽 아래 체크 배지)까지 붙는다.
class StampMark extends StatelessWidget {
  final double size;
  final String label; // (호환용) 얼굴 도장에서는 표시하지 않는다
  final bool filledCheck;
  final int level; // 도장 레벨 (1~5) — 링 색과 얼굴이 함께 진화
  final int variant; // 4·5단계 얼굴 변형 (0~3)
  const StampMark({
    super.key,
    this.size = 48,
    this.label = 'UP!',
    this.filledCheck = false,
    this.level = 1,
    this.variant = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.stampRingColors(level);
    final ring = Transform.rotate(
      angle: -0.14, // 약 -8도 — 손으로 찍은 듯한 기울기
      // 레벨 링: 그라데이션 테두리 (바깥 원에 그라데이션, 안쪽 원이 배경)
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.075),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: AppTheme.glowAlpha(level)),
              blurRadius: size * (level >= 3 ? 0.30 : 0.18),
              offset: Offset(0, size * 0.05),
            ),
            // 5단계: 반대편에서 바이올렛 빛이 한 번 더 — 오로라처럼 이중 발광
            if (level >= 5)
              BoxShadow(
                color: colors.first.withValues(alpha: 0.45),
                blurRadius: size * 0.34,
                offset: Offset(0, -size * 0.04),
              ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.softStampBg(context),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: VaveFace(size: size, level: level, variant: variant),
        ),
      ),
    );

    if (!filledCheck) return ring;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ring,
          Positioned(
            right: -size * 0.04,
            bottom: -size * 0.02,
            child: Container(
              width: size * 0.40,
              height: size * 0.40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.stamp,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    width: size * 0.03),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.check_rounded,
                  color: Colors.white, size: size * 0.24),
            ),
          ),
        ],
      ),
    );
  }
}

/// 루틴 행의 도장 버튼 — 미인증: 회색 '도장' 링 / 인증: 바브바브 얼굴 도장
class StampButton extends StatelessWidget {
  final bool certified;
  final double size;
  final int level;
  final int variant; // 4·5단계 얼굴 변형 (0~3)
  const StampButton({
    super.key,
    required this.certified,
    this.size = 52,
    this.level = 1,
    this.variant = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (certified) {
      return StampMark(size: size, level: level, variant: variant);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant, width: size * 0.055),
      ),
      alignment: Alignment.center,
      child: Text('도장',
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            fontWeight: FontWeight.w800,
            fontSize: size * 0.24,
          )),
    );
  }
}

/// 앱 상단 로고 — 바브바브 얼굴 도장 + 'Log Challenge' 워드마크
class AppLogo extends StatelessWidget {
  final double height;
  const AppLogo({super.key, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: -0.14,
          child: Container(
            width: height,
            height: height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.softStampBg(context),
              border: Border.all(color: AppTheme.stamp, width: height * 0.075),
            ),
            clipBehavior: Clip.antiAlias,
            child: VaveFace(size: height),
          ),
        ),
        const SizedBox(width: 9),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'NanumGothic',
              fontWeight: FontWeight.w800,
              fontSize: height * 0.66,
              letterSpacing: -0.3,
            ),
            children: [
              TextSpan(text: 'Log', style: TextStyle(color: AppTheme.stamp)),
              TextSpan(text: 'Challenge', style: TextStyle(color: cs.primary)),
            ],
          ),
        ),
      ],
    );
  }
}
