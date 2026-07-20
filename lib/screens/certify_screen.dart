import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/watermark_service.dart';
import '../services/share_service.dart';
import '../services/steps_service.dart';
import '../theme.dart';

class CertifyScreen extends StatefulWidget {
  final AppState state;
  final Routine routine;
  final DateTime day;
  final bool recovery; // 누락 인증 복구 모드 (지난 날짜 소급 인증)
  const CertifyScreen({
    super.key,
    required this.state,
    required this.routine,
    required this.day,
    this.recovery = false,
  });

  @override
  State<CertifyScreen> createState() => _CertifyScreenState();
}

class _CertifyScreenState extends State<CertifyScreen> {
  final _picker = ImagePicker();
  final _memo = TextEditingController();
  final _progress = TextEditingController();
  final _linkCtrl = TextEditingController(); // URL 인증
  String? _pickedPath;
  bool _isBackup = false;
  bool _saving = false;

  // 타이머 인증 (+ 명상 모드 배경 음악)
  Timer? _ticker;
  int _elapsedSec = 0;
  bool _running = false;
  final _bgm = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  bool get _timerDone =>
      _elapsedSec >= widget.routine.timerMinutes * 60;

  Future<void> _bgmPlay() async {
    final src = widget.routine.mediaSource;
    if (src == null || widget.routine.mediaIsYoutube) return;
    try {
      if (widget.routine.mediaIsUrl) {
        await _bgm.play(UrlSource(src));
      } else if (File(src).existsSync()) {
        await _bgm.play(DeviceFileSource(src));
      }
    } catch (_) {/* 미디어 재생 실패는 조용히 무시 (타이머는 계속) */}
  }

  // 녹음 인증
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _audioPath;
  bool _recording = false;
  bool _playing = false;

  // 동영상 인증
  String? _videoPath;
  VideoPlayerController? _videoCtrl;

  // 걸음수 인증
  int? _todaySteps;
  bool _stepsLoading = false;
  bool _stepsDenied = false;
  bool get _stepsDone =>
      _todaySteps != null && _todaySteps! >= widget.routine.targetSteps;

  Future<void> _loadSteps() async {
    setState(() {
      _stepsLoading = true;
      _stepsDenied = false;
    });
    final steps = await StepsService.instance.todaySteps();
    if (!mounted) return;
    setState(() {
      _stepsLoading = false;
      if (steps == null) {
        _stepsDenied = true;
      } else {
        _todaySteps = steps;
      }
    });
  }

  VerifyMethod get _method => widget.routine.verifyMethod;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _memo.dispose();
    _progress.dispose();
    _linkCtrl.dispose();
    _ticker?.cancel();
    _bgm.dispose();
    _recorder.dispose();
    _player.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── 동영상 ──
  Future<void> _pickVideo(ImageSource source) async {
    final x = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (x == null) return;
    // 캐시 정리에 안전하도록 앱 문서 폴더로 복사
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/vid_${DateTime.now().millisecondsSinceEpoch}${x.path.substring(x.path.lastIndexOf('.'))}';
    await File(x.path).copy(dest);
    await _videoCtrl?.dispose();
    final ctrl = VideoPlayerController.file(File(dest));
    await ctrl.initialize();
    setState(() {
      _videoPath = dest;
      _videoCtrl = ctrl;
    });
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2000,
    );
    if (x != null) setState(() => _pickedPath = x.path);
  }

  // ── 타이머 ──
  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      _bgm.pause();
      setState(() => _running = false);
    } else {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _elapsedSec++;
          if (_timerDone && _running) {
            _ticker?.cancel();
            _running = false;
            _bgm.stop();
          }
        });
      });
      _bgmPlay();
      setState(() => _running = true);
    }
  }

  void _resetTimer() {
    _ticker?.cancel();
    _bgm.stop();
    setState(() {
      _running = false;
      _elapsedSec = 0;
    });
  }

  // ── 녹음 ──
  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() {
        _recording = false;
        _audioPath = path;
      });
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('마이크 권한을 허용해 주세요')),
        );
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    setState(() {
      _recording = true;
      _audioPath = null;
    });
  }

  Future<void> _togglePlay() async {
    if (_audioPath == null) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(_audioPath!));
      setState(() => _playing = true);
    }
  }

  bool get _canSubmit => switch (_method) {
        VerifyMethod.photo => _pickedPath != null,
        VerifyMethod.timer => _timerDone,
        VerifyMethod.audio => _audioPath != null && !_recording,
        VerifyMethod.video => _videoPath != null,
        VerifyMethod.steps => _stepsDone,
        VerifyMethod.link => _isValidLink(_linkCtrl.text),
      };

  static bool _isValidLink(String s) {
    final t = s.trim();
    final u = Uri.tryParse(t);
    return t.startsWith('http') && u != null && u.hasAuthority;
  }

  String get _blockReason => switch (_method) {
        VerifyMethod.photo => '인증 사진을 먼저 선택해 주세요',
        VerifyMethod.timer =>
          '타이머로 ${widget.routine.timerMinutes}분을 채우면 인증할 수 있어요',
        VerifyMethod.audio => '녹음을 완료하면 인증할 수 있어요',
        VerifyMethod.video => '인증 동영상을 먼저 촬영/선택해 주세요',
        VerifyMethod.steps =>
          '목표 ${widget.routine.targetSteps}보를 채우고 걸음수를 불러와 주세요',
        VerifyMethod.link => '인증할 웹주소(http…)를 정확히 입력해 주세요',
      };

  Future<void> _submit() async {
    // 복구 모드는 지난 날짜 소급 인증이라 시간대 제한을 건너뛴다
    if (!widget.recovery &&
        !widget.routine.isWithinWindow(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '이 루틴은 ${widget.routine.windowLabel} 사이에만 인증할 수 있어요')));
      return;
    }
    if (!_canSubmit) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_blockReason)));
      return;
    }
    if (widget.routine.requireNote && _memo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오늘의 소감/느낀점을 적어주세요 (이 루틴은 필수예요)')),
      );
      return;
    }
    setState(() => _saving = true);
    // 복구 모드면 그날 정오를 인증 시각으로 (워터마크·기록이 해당 날짜로 남음)
    final now = widget.recovery
        ? DateTime(widget.day.year, widget.day.month, widget.day.day, 12)
        : DateTime.now();

    // 사진이 있으면 날짜·시각 워터마크 자동 삽입 (타이머/녹음은 사진 선택)
    String stampedPath = '';
    if (_pickedPath != null) {
      stampedPath = await WatermarkService.stamp(_pickedPath!, now);
    }

    final cert = Certification(
      id: now.microsecondsSinceEpoch.toString(),
      routineId: widget.routine.id,
      dateKey: dateKeyOf(widget.day),
      photoPath: stampedPath,
      memo: _memo.text.trim(),
      progressValue: widget.routine.type == RoutineType.result
          ? _progress.text.trim()
          : null,
      timestamp: now,
      isBackup: _isBackup,
      verifyMethod: _method.name,
      durationSec: _method == VerifyMethod.timer ? _elapsedSec : null,
      audioPath: _method == VerifyMethod.audio ? _audioPath : null,
      videoPath: _method == VerifyMethod.video ? _videoPath : null,
      steps: _method == VerifyMethod.steps ? _todaySteps : null,
      linkUrl:
          _method == VerifyMethod.link ? _linkCtrl.text.trim() : null,
    );
    await widget.state.addCertification(cert);

    if (!mounted) return;
    setState(() => _saving = false);
    await _offerShare(cert);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _offerShare(Certification cert) async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const StampMark(size: 40, filledCheck: true),
                  const SizedBox(width: 10),
                  const Text('도장 찍었습니다!',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('카카오톡 오픈채팅방 등에 공유할까요?\n(공유 시트에서 방을 직접 골라 전송하면 됩니다)',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await ShareService.shareCertification(
                      cert: cert, routine: widget.routine);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('공유하기'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
                child: const Text('나중에'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.routine;
    final isResult = r.type == RoutineType.result;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.recovery
              ? "${DateFormat('M월 d일').format(widget.day)} 인증 복구"
              : "'${r.title}' 인증")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 인증 시간대 안내 배너
          if (r.hasWindow) ...[
            Builder(builder: (context) {
              final within = r.isWithinWindow(DateTime.now());
              final cs = Theme.of(context).colorScheme;
              return Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: within
                      ? cs.primary.withValues(alpha: 0.08)
                      : cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(within ? Icons.wb_twilight : Icons.lock_clock,
                        size: 18,
                        color: within ? cs.primary : cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        within
                            ? '지금 인증 가능! (${r.windowLabel})'
                            : '이 루틴은 ${r.windowLabel} 사이에만 인증할 수 있어요',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              within ? cs.primary : cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          // ── 검증 방식별 메인 영역 ──
          if (_method == VerifyMethod.timer) ...[
            _TimerBox(
              elapsedSec: _elapsedSec,
              targetMin: r.timerMinutes,
              running: _running,
              done: _timerDone,
              onToggle: _toggleTimer,
              onReset: _resetTimer,
              mediaSource: r.mediaSource,
              mediaIsYoutube: r.mediaIsYoutube,
            ),
            const SizedBox(height: 16),
            Text('인증 사진 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          if (_method == VerifyMethod.audio) ...[
            _RecorderBox(
              recording: _recording,
              hasAudio: _audioPath != null,
              playing: _playing,
              onToggleRecord: _toggleRecord,
              onTogglePlay: _togglePlay,
            ),
            const SizedBox(height: 16),
            Text('인증 사진 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          if (_method == VerifyMethod.steps) ...[
            _StepsBox(
              steps: _todaySteps,
              target: widget.routine.targetSteps,
              loading: _stepsLoading,
              denied: _stepsDenied,
              done: _stepsDone,
              onLoad: _loadSteps,
            ),
            const SizedBox(height: 16),
            Text('인증 사진 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          if (_method == VerifyMethod.link) ...[
            _LinkBox(
              controller: _linkCtrl,
              valid: _isValidLink(_linkCtrl.text),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('인증 사진 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          if (_method == VerifyMethod.video) ...[
            _VideoBox(controller: _videoCtrl),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickVideo(ImageSource.camera),
                    icon: const Icon(Icons.videocam),
                    label: const Text('영상 촬영'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickVideo(ImageSource.gallery),
                    icon: const Icon(Icons.video_library),
                    label: const Text('갤러리'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('인증 사진 (선택)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          _PhotoArea(path: _pickedPath, optional: _method != VerifyMethod.photo),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('촬영'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('갤러리'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('사진에 날짜·시각이 자동으로 표기됩니다.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (isResult)
            TextField(
              controller: _progress,
              decoration: InputDecoration(
                labelText: '진행 결과 / 수치',
                hintText: r.targetValue != null
                    ? '목표: ${r.targetValue}'
                    : '예: 3/5권 완료, 누적 24km',
              ),
            ),
          if (isResult) const SizedBox(height: 12),
          TextField(
            controller: _memo,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.routine.requireNote
                  ? '오늘의 소감 / 느낀점 (필수)'
                  : '오늘의 소감 / 느낀점 (선택)',
              hintText: '오늘 실행하며 느낀 점, 배운 점을 남겨보세요',
            ),
          ),
          if (r.type == RoutineType.accumulate && r.backupTitle != null) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isBackup,
              onChanged: (v) => setState(() => _isBackup = v),
              title: const Text('백업 루틴으로 인증'),
              subtitle: Text(r.backupTitle!),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle),
            label: Text(_saving ? '저장 중...' : '도장 찍기'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

/// 타이머 인증 박스 — 명상 모드: 호흡 가이드 애니메이션 + 배경 음악/유튜브
class _TimerBox extends StatefulWidget {
  final int elapsedSec;
  final int targetMin;
  final bool running;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final String? mediaSource;
  final bool mediaIsYoutube;
  const _TimerBox({
    required this.elapsedSec,
    required this.targetMin,
    required this.running,
    required this.done,
    required this.onToggle,
    required this.onReset,
    this.mediaSource,
    this.mediaIsYoutube = false,
  });

  @override
  State<_TimerBox> createState() => _TimerBoxState();
}

class _TimerBoxState extends State<_TimerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath; // 4초 들숨 + 4초 날숨

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    if (widget.running) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_TimerBox old) {
    super.didUpdateWidget(old);
    if (widget.running && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!widget.running && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  String _fmt(int sec) =>
      '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress =
        (widget.elapsedSec / (widget.targetMin * 60)).clamp(0.0, 1.0);
    final hasMedia = widget.mediaSource != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: widget.done ? AppTheme.stamp : cs.outlineVariant,
            width: widget.done ? 1.6 : 1),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_breath.value);
              final scale = 0.9 + t * 0.28; // 숨쉬는 원
              return SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 호흡 가이드 원 (명상 모드)
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary.withValues(
                              alpha: widget.running ? 0.10 : 0.05),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: widget.done ? AppTheme.stamp : cs.primary,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_fmt(widget.elapsedSec),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: widget.done
                                  ? AppTheme.stamp
                                  : cs.onSurface,
                            )),
                        Text(
                          widget.running
                              ? (_breath.status == AnimationStatus.forward
                                  ? '들이쉬고…'
                                  : '내쉬고…')
                              : '목표 ${widget.targetMin}분',
                          style: TextStyle(
                              fontSize: 12,
                              color: widget.running
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontWeight: widget.running
                                  ? FontWeight.w700
                                  : FontWeight.w400),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // 배경 미디어 안내/컨트롤
          if (hasMedia && widget.mediaIsYoutube)
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(widget.mediaSource!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('유튜브 열고 명상 시작'),
            ),
          if (hasMedia && !widget.mediaIsYoutube)
            Text(
              widget.running ? '🎵 배경 음악 재생 중' : '🎵 시작하면 음악이 함께 재생돼요',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (hasMedia) const SizedBox(height: 10),
          if (widget.done)
            const Text('목표 달성! 이제 도장을 찍을 수 있어요 🎉',
                style: TextStyle(
                    color: AppTheme.stamp, fontWeight: FontWeight.w700)),
          if (!widget.done)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: widget.onToggle,
                  icon: Icon(
                      widget.running ? Icons.pause : Icons.play_arrow),
                  label: Text(widget.running
                      ? '일시정지'
                      : (widget.elapsedSec > 0 ? '계속' : '시작')),
                ),
                const SizedBox(width: 10),
                if (widget.elapsedSec > 0 && !widget.running)
                  OutlinedButton(
                      onPressed: widget.onReset, child: const Text('리셋')),
              ],
            ),
        ],
      ),
    );
  }
}

/// URL 인증 박스 — 결과 웹주소(스토어 등록·업로드·공유 링크) 입력
class _LinkBox extends StatelessWidget {
  final TextEditingController controller;
  final bool valid;
  final VoidCallback onChanged;
  const _LinkBox(
      {required this.controller,
      required this.valid,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: valid ? AppTheme.stamp : cs.outlineVariant,
            width: valid ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('결과 웹주소',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('스토어 등록 페이지, 업로드한 글, 공유 링크 등 결과가 담긴 URL을 붙여넣으세요.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'https://…',
              suffixIcon: valid
                  ? const Icon(Icons.check_circle,
                      color: AppTheme.stamp)
                  : (controller.text.trim().isEmpty
                      ? null
                      : Icon(Icons.error_outline, color: cs.error)),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

/// 걸음수 인증 박스 — Health Connect에서 오늘 걸음수를 읽어 목표 대비 확인
class _StepsBox extends StatelessWidget {
  final int? steps;
  final int target;
  final bool loading;
  final bool denied;
  final bool done;
  final VoidCallback onLoad;
  const _StepsBox({
    required this.steps,
    required this.target,
    required this.loading,
    required this.denied,
    required this.done,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress =
        steps == null ? 0.0 : (steps! / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: done ? AppTheme.stamp : cs.outlineVariant,
            width: done ? 1.6 : 1),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: done ? AppTheme.stamp : cs.primary,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                children: [
                  Icon(Icons.directions_walk_rounded,
                      size: 26,
                      color: done ? AppTheme.stamp : cs.primary),
                  Text(
                    steps == null ? '--' : '$steps',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: done ? AppTheme.stamp : cs.onSurface,
                    ),
                  ),
                  Text('목표 $target보',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (done)
            const Text('목표 달성! 이제 도장을 찍을 수 있어요 🎉',
                style: TextStyle(
                    color: AppTheme.stamp, fontWeight: FontWeight.w700)),
          if (denied)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '헬스커넥트 권한이 필요해요. 삼성헬스가 걸음수를 기록 중인지도 확인해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
          if (!done)
            FilledButton.icon(
              onPressed: loading ? null : onLoad,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(loading
                  ? '불러오는 중...'
                  : steps == null
                      ? '오늘 걸음수 불러오기'
                      : '걸음수 새로고침'),
            ),
        ],
      ),
    );
  }
}

/// 동영상 인증 박스 — 선택한 영상 미리보기 + 재생
class _VideoBox extends StatefulWidget {
  final VideoPlayerController? controller;
  const _VideoBox({this.controller});

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = widget.controller;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: ctrl == null || !ctrl.value.isInitialized
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_outlined,
                        size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text('인증 동영상 (최대 5분)',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.size.width,
                      height: ctrl.value.size.height,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () {
                      setState(() {
                        ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                      });
                    },
                    icon: Icon(ctrl.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 녹음 인증 박스
class _RecorderBox extends StatelessWidget {
  final bool recording;
  final bool hasAudio;
  final bool playing;
  final VoidCallback onToggleRecord;
  final VoidCallback onTogglePlay;
  const _RecorderBox({
    required this.recording,
    required this.hasAudio,
    required this.playing,
    required this.onToggleRecord,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: recording
                ? AppTheme.stamp
                : (hasAudio ? cs.primary : cs.outlineVariant),
            width: recording || hasAudio ? 1.6 : 1),
      ),
      child: Column(
        children: [
          Icon(
            recording ? Icons.graphic_eq_rounded : Icons.mic_rounded,
            size: 56,
            color: recording ? AppTheme.stamp : cs.primary,
          ),
          const SizedBox(height: 8),
          Text(
            recording
                ? '녹음 중... 끝나면 정지를 누르세요'
                : hasAudio
                    ? '녹음 완료! 들어보고 도장을 찍으세요'
                    : '발음 연습·낭독을 녹음으로 남겨요',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onToggleRecord,
                style: recording
                    ? FilledButton.styleFrom(
                        backgroundColor: AppTheme.stamp)
                    : null,
                icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
                label: Text(recording ? '정지' : (hasAudio ? '다시 녹음' : '녹음 시작')),
              ),
              if (hasAudio && !recording) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onTogglePlay,
                  icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                  label: Text(playing ? '정지' : '들어보기'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  final String? path;
  final bool optional;
  const _PhotoArea({this.path, this.optional = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: path == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo,
                        size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(optional ? '인증 사진 (선택)' : '인증 사진',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : Image.file(File(path!), fit: BoxFit.cover),
      ),
    );
  }
}
