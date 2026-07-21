import 'package:flutter/material.dart';

/// KeepUp 디자인 시스템 — Stitch 'KeepUp' 팔레트 (2026-07-14 적용)
/// - 브랜드: 딥블루(#274ED5) / 포인트: 도장 인주색(#B32A19 계열)
/// - 서체: 네이버 나눔고딕 (번들, 변경 금지)
class AppTheme {
  static const seed = Color(0xFF274ED5); // 브랜드 딥블루 (Stitch primary)
  static const seedBright = Color(0xFF4669F0); // primary-container
  static const stamp = Color(0xFFB32A19); // 도장 인주색 (테두리·텍스트)
  static const stampAccent = Color(0xFFFC5E47); // 도장 강조(채움)
  static const stampSoft = Color(0xFFFFDAD4); // 도장 옅은 배경
  static const success = Color(0xFF098730); // 완료 그린 (Stitch tertiary)

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: seed,
      primaryContainer: seedBright,
      onPrimaryContainer: Colors.white,
      surface: const Color(0xFFF7F9FF), // Stitch surface
      surfaceContainerLowest: Colors.white,
      onSurface: const Color(0xFF181C20),
      onSurfaceVariant: const Color(0xFF444654),
      outlineVariant: const Color(0xFFC4C5D7),
      tertiary: success,
      tertiaryContainer: const Color(0xFFDCF5DF),
      onTertiaryContainer: const Color(0xFF01522A),
    );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: cs.surface,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE4E7F2)),
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
      tertiary: const Color(0xFF7ADB93),
      tertiaryContainer: const Color(0xFF0B4A22),
      onTertiaryContainer: const Color(0xFFBDF0C6),
    );
    return _base(cs).copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
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
            color: cs.primary, // Stitch 시안: 타이틀을 브랜드 블루로
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: cs.surfaceContainerLowest,
          indicatorColor: cs.primary.withValues(alpha: 0.12),
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
}

/// KeepUp 시그니처 — 기울어진 인주색 도장 링
class StampMark extends StatelessWidget {
  final double size;
  final String label;
  final bool filledCheck;
  const StampMark({
    super.key,
    this.size = 48,
    this.label = 'UP!',
    this.filledCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.14, // 약 -8도
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filledCheck ? AppTheme.stampSoft : Colors.transparent,
          border: Border.all(color: AppTheme.stamp, width: size * 0.08),
        ),
        alignment: Alignment.center,
        child: filledCheck
            ? Icon(Icons.check_rounded,
                color: AppTheme.stamp, size: size * 0.55)
            : Text(
                label,
                style: TextStyle(
                  color: AppTheme.stamp,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.26,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// 루틴 행의 도장 버튼 — 미인증: 회색 STAMP 링 / 인증: 인주색 UP! 도장 (Stitch 시안)
class StampButton extends StatelessWidget {
  final bool certified;
  final double size;
  const StampButton({super.key, required this.certified, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (certified) {
      return Transform.rotate(
        angle: -0.14,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.stampSoft,
            border: Border.all(color: AppTheme.stamp, width: size * 0.075),
          ),
          alignment: Alignment.center,
          child: Text('UP!',
              style: TextStyle(
                color: AppTheme.stamp,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.27,
              )),
        ),
      );
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

/// 앱 상단 로고 — 도장 마크 + 'Log Challenge' 워드마크
class AppLogo extends StatelessWidget {
  final double height;
  const AppLogo({super.key, this.height = 30});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 미니 도장 링
        Transform.rotate(
          angle: -0.14,
          child: Container(
            width: height,
            height: height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.stamp, width: height * 0.1),
            ),
            alignment: Alignment.center,
            child: Text('UP',
                style: TextStyle(
                  color: AppTheme.stamp,
                  fontWeight: FontWeight.w800,
                  fontSize: height * 0.32,
                  height: 1,
                )),
          ),
        ),
        const SizedBox(width: 9),
        // 워드마크: Log(도장색) + Challenge(브랜드 블루)
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
