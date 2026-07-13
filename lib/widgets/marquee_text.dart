import 'package:flutter/material.dart';

/// 전광판처럼 좌→우로 끝없이 흐르는 텍스트 (패키지 없이 구현)
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
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _measureAndRun();
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _measureAndRun();
    }
  }

  void _measureAndRun() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _textWidth = painter.width;
    final loop = _textWidth + widget.gap;
    _c
      ..stop()
      ..duration = Duration(
          milliseconds: ((loop / widget.speed) * 1000).clamp(3000, 60000).round())
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();
    final loop = _textWidth + widget.gap;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // 좌→우 진행: 오프셋이 증가하며 두 장의 텍스트가 이어 달린다
            final dx = (_c.value * loop) % loop;
            return SizedBox(
              height: (widget.style?.fontSize ?? 14) * 1.5,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
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
                        style: widget.style, maxLines: 1, softWrap: false),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
