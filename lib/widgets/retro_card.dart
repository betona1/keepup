import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/retro_stats.dart';
import '../models/routine.dart';
import '../theme.dart';

/// 시즌 회고 카드 — 이미지로 캡처해 공유하는 결과물.
/// 공유물이므로 앱 테마(라이트/다크)와 무관하게 항상 같은 모습으로 그린다.
class RetroCard extends StatelessWidget {
  static const double width = 340;

  final RetroStats stats;
  const RetroCard({super.key, required this.stats});

  static const _ink = Color(0xFF181C20);
  static const _sub = Color(0xFF6B6F7E);
  static const _line = Color(0xFFE4E7F2);

  @override
  Widget build(BuildContext context) {
    final r = stats.routine;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(r),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _gauge(),
                const SizedBox(height: 18),
                _statRow(),
                if (r.reason.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _reason(r.reason),
                ],
                const SizedBox(height: 18),
                _StampGrid(stats: stats),
                if (stats.photoCerts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _photos(),
                ],
                const SizedBox(height: 18),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 브랜드 블루 그라데이션 헤더 — 루틴명 + 기간
  Widget _header(Routine r) {
    final f = DateFormat('yyyy.MM.dd');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4669F0), Color(0xFF274ED5)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'KEEPUP 회고',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      stats.ended ? '시즌 종료' : '진행 중',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${f.format(r.startDate)} ~ ${f.format(r.endDate)}'
                  '  ·  ${stats.seasonDays}일',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.type.label} · ${r.dutyCycle.label}'
                  ' · ${r.verifyMethod.label}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _badgeStamp(),
        ],
      ),
    );
  }

  /// 달성 등급 도장 — 기울어진 인주색 링
  Widget _badgeStamp() {
    return Transform.rotate(
      angle: -0.16,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: AppTheme.stampAccent, width: 3),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${stats.percent}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              stats.badge,
              style: const TextStyle(
                color: AppTheme.stampAccent,
                fontSize: 7.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 달성률 원형 게이지 + 도장 수
  Widget _gauge() {
    return Row(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: CustomPaint(
            painter: _RingPainter(stats.percent / 100),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${stats.percent}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.stamp,
                      height: 1.0,
                    ),
                  ),
                  const Text(
                    '달성률 %',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontFamily: 'NanumGothic',
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                  children: [
                    TextSpan(
                      text: '${stats.certifiedDays}',
                      style: const TextStyle(fontSize: 32, height: 1.1),
                    ),
                    TextSpan(
                      text: ' / ${stats.totalDutyDays}일',
                      style: const TextStyle(fontSize: 14, color: _sub),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '찍은 도장',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _sub),
              ),
              if (stats.tallyLabel != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.stampSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stats.tallyLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.stamp,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statRow() {
    return Row(
      children: [
        _stat('최장 연속', '${stats.longestStreak}일'),
        const SizedBox(width: 8),
        _stat('놓친 날', '${stats.missedDays}일'),
        const SizedBox(width: 8),
        _stat('인증 횟수', '${stats.totalCerts}회'),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: _sub)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.seed,
                ),
              ),
            ],
          ),
        ),
      );

  /// 선언한 이유 — 시즌 시작의 마음
  Widget _reason(String reason) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FF),
          borderRadius: BorderRadius.circular(12),
          border: const Border(
            left: BorderSide(color: AppTheme.stampAccent, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '내가 이걸 시작한 이유',
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800, color: _sub),
            ),
            const SizedBox(height: 3),
            Text(
              '“$reason”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _ink,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _photos() {
    return Row(
      children: [
        for (var i = 0; i < stats.photoCerts.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(stats.photoCerts[i].photoPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: const Color(0xFFEFF1F8)),
                ),
              ),
            ),
          ),
        ],
        // 사진이 4장보다 적으면 남은 칸을 비워 균형을 맞춘다
        for (var i = stats.photoCerts.length; i < 4; i++) ...[
          const SizedBox(width: 6),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    );
  }

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: _line, height: 1),
        const SizedBox(height: 12),
        Text(
          stats.headline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: _ink,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const StampMark(size: 20, label: 'UP!'),
            const SizedBox(width: 7),
            Text(
              'KeepUp · keepup.keywordream.com',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: _sub.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 달성률 링 — 배경 트랙 + 인주색 진행 호
class _RingPainter extends CustomPainter {
  final double value; // 0.0 ~ 1.0
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.stampSoft;
    canvas.drawCircle(center, radius, track);

    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [AppTheme.stampAccent, AppTheme.stamp],
      ).createShader(rect);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// 시즌 전체 도장 그리드 — 세로 7칸(월~일), 가로로 주가 흐른다.
/// 1년 시즌(53주)도 한 화면에 들어오도록 칸 크기를 폭에 맞춘다.
class _StampGrid extends StatelessWidget {
  final RetroStats stats;
  const _StampGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final weeks = stats.weeks;
        if (weeks == 0) return const SizedBox.shrink();
        const gap = 2.0;
        final cell =
            ((c.maxWidth - gap * (weeks - 1)) / weeks).clamp(3.0, 13.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '도장 기록',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: RetroCard._sub),
                ),
                const Spacer(),
                _legend(AppTheme.stamp, '인증'),
                const SizedBox(width: 8),
                _legend(const Color(0xFFFFCDD2), '놓침'),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 7; row++)
                    Padding(
                      padding: EdgeInsets.only(bottom: row == 6 ? 0 : gap),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var w = 0; w < weeks; w++) ...[
                            if (w > 0) const SizedBox(width: gap),
                            _cell(stats.dayMarks[w * 7 + row], cell),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(fontSize: 9, color: RetroCard._sub)),
        ],
      );

  Widget _cell(int mark, double size) {
    final (color, border) = switch (mark) {
      DayMark.stamped => (AppTheme.stamp, null),
      DayMark.missed => (const Color(0xFFFFCDD2), null),
      DayMark.upcoming => (Colors.transparent, const Color(0xFFDCE0EE)),
      DayMark.rest => (const Color(0xFFF0F2F8), null),
      _ => (Colors.transparent, null), // 시즌 밖
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: border == null ? null : Border.all(color: border, width: 0.8),
      ),
    );
  }
}
