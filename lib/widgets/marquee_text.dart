import 'package:flutter/material.dart';

/// 전광판처럼 좌→우로 끝없이 흐르는 텍스트 (패키지 없이 구현)
///
/// 폭은 TextPainter로 미리 재지 않고 **실제로 그려진 텍스트의 폭**을 프레임마다
/// 확인해 쓴다 — 웹에서는 폰트(나눔고딕)가 늦게 로드되어 미리 잰 폭이 틀어지고,
/// 두 장의 반복 텍스트가 겹쳐 글씨가 깨져 보였다. 렌더 폭 기준이면 폰트가
/// 언제 로드되든 스스로 맞춰진다.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double speed; // 초당 픽셀
  final double gap; // 반복 사이 간격
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.speed = 36,
    this.gap = 48,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _probe = GlobalKey(); // 실제 렌더된 텍스트 폭을 읽는 기준
  double _textWidth = 0; // 0 = 아직 측정 전 (한 장만 그려 겹침 방지)

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _textWidth = 0; // 다시 측정 (다음 프레임에 _syncWidth가 채운다)
      _c.stop();
    }
  }

  /// 매 프레임 끝에 실제 렌더 폭과 비교해 달라졌으면 애니메이션을 다시 맞춘다.
  /// (폰트 지연 로드·텍스트 배율 변경도 여기서 자연히 따라잡는다)
  void _syncWidth(Duration _) {
    if (!mounted) return;
    final box = _probe.currentContext?.findRenderObject() as RenderBox?;
    final w = (box?.hasSize ?? false) ? box!.size.width : null;
    if (w == null || w <= 0 || (w - _textWidth).abs() < 0.5) return;
    setState(() {
      _textWidth = w;
      final loop = _textWidth + widget.gap;
      _c
        ..duration = Duration(
            milliseconds:
                ((loop / widget.speed) * 1000).clamp(3000, 60000).round())
        ..repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback(_syncWidth);
    final ready = _textWidth > 0;
    final loop = _textWidth + widget.gap;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // 좌→우 진행: 오프셋이 증가하며 두 장의 텍스트가 이어 달린다
          final dx = ready ? (_c.value * loop) % loop : 0.0;
          return SizedBox(
            height: (widget.style?.fontSize ?? 14) * 1.5,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 측정 전에는 뒤따르는 장을 그리지 않아 겹침(깨짐)이 없다
                if (ready)
                  Positioned(
                    left: dx - loop,
                    top: 0,
                    child: Text(widget.text,
                        style: widget.style, maxLines: 1, softWrap: false),
                  ),
                Positioned(
                  left: dx,
                  top: 0,
                  child: Text(widget.text,
                      key: _probe,
                      style: widget.style,
                      maxLines: 1,
                      softWrap: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
