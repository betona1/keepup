import 'package:flutter/material.dart';

/// KeepUp 디자인 시스템
/// - 브랜드: 인디고(#4C6EF5, 웹과 동일) / 포인트: 인주색 도장(#E8503A)
/// - 서체: 네이버 나눔고딕 (번들)
class AppTheme {
  static const seed = Color(0xFF4C6EF5); // 브랜드 인디고
  static const stamp = Color(0xFFE8503A); // 도장 인주색 (인증/강조 전용)
  static const stampSoft = Color(0xFFFDEEEB); // 인주색 옅은 배경

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: seed,
      surface: const Color(0xFFF6F7FC), // 종이 느낌 배경
      surfaceContainerLowest: Colors.white,
      tertiary: stamp,
      tertiaryContainer: stampSoft,
      onTertiaryContainer: const Color(0xFFB33A29),
    );
    return _base(cs).copyWith(
      scaffoldBackgroundColor: cs.surface,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE7EAF3)),
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
      tertiary: const Color(0xFFFF8A75),
      tertiaryContainer: const Color(0xFF4A241E),
      onTertiaryContainer: const Color(0xFFFFB4A5),
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
            color: cs.onSurface,
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
