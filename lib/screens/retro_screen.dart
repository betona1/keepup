import 'dart:io';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models/retro_stats.dart';
import '../models/routine.dart';
import '../services/retro_service.dart';
import '../widgets/retro_card.dart';

/// 시즌 회고 카드 화면 — 카드를 보여주고 이미지로 공유한다.
/// (기획서 3.4: 시즌 종료 시 회고 카드 자동 생성 / 진행 중에도 중간 회고)
class RetroScreen extends StatefulWidget {
  final AppState state;
  final Routine routine;
  const RetroScreen({super.key, required this.state, required this.routine});

  @override
  State<RetroScreen> createState() => _RetroScreenState();
}

class _RetroScreenState extends State<RetroScreen> {
  final _cardKey = GlobalKey();
  late RetroStats _stats;
  bool _ready = false; // 사진 로딩 완료 — 캡처에 빈 칸이 남지 않도록
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _stats = widget.state.retroStatsFor(widget.routine.id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) _precache();
  }

  /// 카드 안 사진을 미리 디코드해 둔다 (캡처 시점에 비어 있으면 안 되므로)
  Future<void> _precache() async {
    for (final c in _stats.photoCerts) {
      final file = File(c.photoPath);
      if (!file.existsSync()) continue;
      try {
        await precacheImage(FileImage(file), context);
      } catch (_) {
        // 깨진 사진은 카드에서 회색 칸으로 그려진다
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await RetroService.share(_cardKey, _stats);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('공유 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_stats.ended ? '시즌 회고 카드' : '중간 회고 카드'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: RetroCard(stats: _stats),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_ready && !_sharing) ? _share : null,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(_sharing ? '카드 만드는 중…' : '이미지로 공유하기'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '카드가 이미지로 저장되어 카톡·인스타 등으로 바로 보낼 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 회고 카드 열기 — 여러 화면에서 공용으로 쓴다
void openRetroCard(BuildContext context, AppState state, Routine routine) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RetroScreen(state: state, routine: routine),
    ),
  );
}
