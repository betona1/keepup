import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../models/retro_stats.dart';
import '../models/routine.dart';
import '../services/media_store.dart';
import '../services/retro_service.dart';
import '../services/web_board_service.dart';
import '../widgets/board_share_dialog.dart';
import '../widgets/login_sheet.dart';
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
  bool _posting = false; // 웹 게시판 업로드 중

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
    // 웹은 사진이 브라우저 저장소에 있어 먼저 읽어 와야 카드에 담긴다
    await MediaStore.preload(_stats.photoCerts.map((c) => c.photoPath));
    if (!mounted) return;
    for (final c in _stats.photoCerts) {
      final provider = MediaStore.providerFor(c.photoPath);
      if (provider == null) continue;
      try {
        await precacheImage(provider, context);
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

  /// 웹 성과 게시판(log.keywordream.com/stories)에 이 회고를 올린다.
  /// 로그인 확인 → 제목·소감 작성 → 회고 카드 이미지와 함께 업로드.
  Future<void> _shareToWeb() async {
    if (!await ensureWebLogin(context)) return;
    if (!mounted) return;

    final r = _stats.routine;
    final draft = await promptBoardPost(
      context,
      title: _stats.ended
          ? '${r.title} — ${_stats.certifiedDays}일 도장 완주!'
          : '${r.title} — ${_stats.certifiedDays}일째 도장 찍는 중',
      body: '달성률 ${_stats.percent}% · 도장 ${_stats.certifiedDays}/'
          '${_stats.totalDutyDays}일 · 최장 연속 ${_stats.longestStreak}일'
          '${_stats.tallyLabel != null ? '\n${_stats.tallyLabel}' : ''}'
          '\n\n',
    );
    if (draft == null || !mounted) return;

    setState(() => _posting = true);
    try {
      final png = await RetroService.capture(_cardKey, pixelRatio: 2.5);
      // 서버 업로드 한도(5MB)를 넘는 카드는 JPEG로 재압축해 올린다
      final (bytes, mime, name) = RetroService.fitForUpload(png);
      final id = await WebBoardService.share(
        stats: _stats,
        title: draft.$1,
        body: draft.$2,
        imageBytes: bytes,
        imageMime: mime,
        imageName: name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('성과 게시판에 올렸어요 🎉'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '보러가기',
            onPressed: () => launchUrl(
              Uri.parse(WebBoardService.postUrl(id)),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
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
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
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
            // 성과 게시판 공개 — 로그인은 이때만 필요.
            // 브라우저에서도 같은 오리진 쿠키로 올릴 수 있어 웹앱에서도 노출한다.
            ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_ready && !_posting) ? _shareToWeb : null,
                  icon: _posting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.emoji_events_outlined, size: 18),
                  label: Text(_posting ? '게시판에 올리는 중…' : '성과 게시판에 공개하기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
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
