import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/auto_upload_service.dart';
import '../services/cloud_sync_service.dart';

/// 클라우드 백업 시트 — 계정에 기록을 올리고 내린다.
///
/// 자동 동기화가 아니라 사용자가 직접 누르는 방식이다. 두 기기에서 번갈아 쓰다가
/// 조용히 덮어써지는 사고를 막기 위해, 내릴 때는 반드시 한 번 더 확인을 받는다.
class CloudSyncSheet extends StatefulWidget {
  final AppState state;
  const CloudSyncSheet({super.key, required this.state});

  @override
  State<CloudSyncSheet> createState() => _CloudSyncSheetState();
}

class _CloudSyncSheetState extends State<CloudSyncSheet> {
  CloudBackupInfo? _info;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  bool _error = false;

  // '가져오기 요청' 대기 상태 — 다른 기기의 승인(업로드)을 폴링으로 기다린다
  Timer? _waitTimer;
  bool _waiting = false;
  DateTime? _baselineUpdatedAt; // 요청 시점의 백업 시각 (달라지면 = 새로 올라옴)
  int _waitedSec = 0;
  static const _waitLimitSec = 5 * 60;

  // 자동 올리기 설정 (폰 전용 — 웹은 폰 백업을 덮으면 안 되므로 없음)
  bool _autoOn = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (!kIsWeb) {
      AutoUploadService.instance.enabled().then((v) {
        if (mounted) setState(() => _autoOn = v);
      });
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await CloudSyncService.info();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _error = error;
    });
  }

  Future<void> _upload() async {
    final routines = widget.state.routines;
    final certs = widget.state.certs;
    if (routines.isEmpty && certs.isEmpty) {
      _say('올릴 기록이 아직 없어요', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await CloudSyncService.upload(routines, certs);
      AutoUploadService.instance.markClean(); // 방금 올렸으니 자동 올리기 대기 해제
      _say('올렸어요 — 루틴 ${routines.length}개, 인증 ${certs.length}개 '
          '(${(bytes / 1024 / 1024).toStringAsFixed(1)}MB)');
      await _load();
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('클라우드에서 내리기'),
        content: const Text(
            '클라우드에 보관된 기록으로 지금 기기의 내용을 교체합니다.\n'
            '이 기기에만 있는 루틴·인증은 사라져요. 계속할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('내려받아 교체')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final (routines, certs) = await CloudSyncService.download();
      await widget.state.restoreAll(routines, certs, autoUpload: false);
      AutoUploadService.instance.markClean(); // 로컬 = 클라우드 상태
      _say('복원 완료 — 루틴 ${routines.length}개, 인증 ${certs.length}개 🎉');
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 다른 기기에 '기록 보내달라' 요청을 남기고, 승인(업로드)되면 자동으로 내려받는다.
  Future<void> _requestPull() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('다른 기기에서 가져오기'),
        content: const Text('기록이 있는 기기(폰)에서 앱을 열면 "보낼까요?" 안내가 떠요.\n'
            '[보내기]를 누르는 순간 이 기기로 자동으로 옮겨지고,\n'
            '이 기기의 기존 기록은 교체됩니다. 요청할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('요청 보내기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      _baselineUpdatedAt = _info?.updatedAt;
      await CloudSyncService.requestPull();
      setState(() {
        _waiting = true;
        _waitedSec = 0;
      });
      _waitTimer?.cancel();
      _waitTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _pollTick());
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollTick() async {
    if (!mounted || !_waiting) return;
    _waitedSec += 3;

    final meta = await CloudSyncService.info();
    if (!mounted || !_waiting) return;

    // 새 백업이 올라왔다 → 승인됨 — 자동으로 내려받아 교체
    if (meta != null && meta.exists && meta.updatedAt != _baselineUpdatedAt) {
      _stopWaiting();
      setState(() => _busy = true);
      try {
        final (routines, certs) = await CloudSyncService.download();
        await widget.state.restoreAll(routines, certs, autoUpload: false);
        AutoUploadService.instance.markClean(); // 로컬 = 클라우드 상태
        await CloudSyncService.clearPull();
        _say('가져왔어요 — 루틴 ${routines.length}개, 인증 ${certs.length}개 🎉');
        await _load();
      } catch (e) {
        _say('$e'.replaceFirst('Bad state: ', ''), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    // 요청이 사라졌는데 새 백업도 없다 → 상대가 거절했거나 만료
    final req = await CloudSyncService.pendingPull(ignoreMine: false);
    if (!mounted || !_waiting) return;
    if (req == null) {
      _stopWaiting();
      _say('요청이 거절됐거나 만료됐어요', error: true);
      return;
    }

    if (_waitedSec >= _waitLimitSec) {
      _stopWaiting();
      await CloudSyncService.clearPull();
      _say('아직 응답이 없어요 — 기록이 있는 기기에서 앱을 열었는지 확인해 주세요', error: true);
    } else if (mounted) {
      setState(() {}); // 경과 시간 갱신
    }
  }

  void _stopWaiting() {
    _waitTimer?.cancel();
    _waitTimer = null;
    if (mounted) setState(() => _waiting = false);
  }

  Future<void> _cancelWait() async {
    _stopWaiting();
    await CloudSyncService.clearPull();
    _say('요청을 취소했어요');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('클라우드 기록 삭제'),
        content: const Text('클라우드에 보관된 백업만 삭제합니다.\n'
            '이 기기의 기록은 그대로 남아요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await CloudSyncService.deleteRemote();
      _say('클라우드 백업을 삭제했어요');
      await _load();
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = _info;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('클라우드 백업',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '기록을 계정에 보관해 두면 폰을 바꾸거나 브라우저 데이터를 지워도 되살릴 수 있어요. '
              '기록은 나만 볼 수 있고, 게시판에 공개되지 않습니다.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // 보관 상태
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _loading
                  ? const Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('확인 중…'),
                    ])
                  : Row(
                      children: [
                        Icon(
                          info?.exists == true
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          size: 20,
                          color: info?.exists == true
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            info == null
                                ? '로그인 상태를 확인할 수 없어요'
                                : info.exists
                                    ? '보관됨 · ${info.sizeLabel}'
                                        '${info.updatedAt != null ? ' · ${DateFormat('M월 d일 HH:mm').format(info.updatedAt!)}' : ''}'
                                    : '아직 보관된 기록이 없어요',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
            ),

            // 자동 올리기 토글 — 폰 전용. 웹에서 켜면 브라우저의 옛 기록이
            // 폰 백업을 덮을 수 있어 웹에는 아예 노출하지 않는다.
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  value: _autoOn,
                  onChanged: (v) {
                    setState(() => _autoOn = v);
                    AutoUploadService.instance.setEnabled(v);
                  },
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  title: const Text('도장 찍으면 자동으로 올리기',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  subtitle: ValueListenableBuilder<DateTime?>(
                    valueListenable: AutoUploadService.instance.lastUploadedAt,
                    builder: (_, at, __) => Text(
                      _autoOn
                          ? '기록이 바뀌면 몇 초 뒤 백업을 자동 갱신해요 (로그인 상태일 때만)'
                              '${at != null ? '\n마지막 자동 올리기: ${DateFormat('M월 d일 HH:mm').format(at)}' : ''}'
                          : '꺼짐 — [지금 기록 올리기]로 직접 올려야 해요',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ],

            // 클라우드가 비어 있는데 내려받기만 눌러보는 경우가 많다.
            // "다른 기기 기록을 가져오려면 그 기기에서 먼저 올려야 한다"를 여기서 알려준다.
            if (!_loading && info != null && !info.exists) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.secondary.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.swap_horiz_rounded, size: 18, color: cs.secondary),
                      const SizedBox(width: 6),
                      Text(
                        kIsWeb ? '폰 앱의 기록을 가져오려면' : '다른 기기의 기록을 가져오려면',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: cs.secondary),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ...[
                      '아래 [다른 기기에서 가져오기]로 요청 보내기',
                      '기록이 있는 기기(폰)에서 앱 열기 (같은 계정 로그인)',
                      '그 기기에 뜨는 안내에서 [보내기] 누르기 → 자동으로 가져와져요',
                    ].asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.key + 1}. ',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: cs.secondary)),
                              Expanded(
                                child: Text(e.value,
                                    style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: cs.onSurfaceVariant)),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '올리는 기기에서 직접 누르는 것이 곧 본인 확인입니다. '
                      '같은 계정만 접근할 수 있어요.',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],

            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _error ? cs.error : cs.primary,
                ),
              ),
            ],

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _upload,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.backup_outlined, size: 18),
              label: Text(_busy ? '처리 중…' : '지금 기록 올리기'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (_busy || info?.exists != true) ? null : _download,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('클라우드에서 내려받기'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            // 다른 기기에 승인 요청 → 자동으로 받아오기 (대기 중엔 취소 카드로 전환)
            if (_waiting)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: cs.primary.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '요청을 보냈어요 (${_waitedSec ~/ 60}분 ${_waitedSec % 60}초)\n'
                            '기록이 있는 기기에서 앱을 열고 [보내기]를 누르면 자동으로 가져와요.',
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cancelWait,
                      child: const Text('요청 취소'),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : _requestPull,
                icon: const Icon(Icons.devices_other_outlined, size: 18),
                label: Text(kIsWeb ? '폰에서 가져오기 (승인 요청)' : '다른 기기에서 가져오기 (승인 요청)'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            if (info?.exists == true) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: Text('클라우드 기록 삭제',
                    style: TextStyle(fontSize: 12.5, color: cs.error)),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '올리면 이전 백업을 덮어씁니다. 사진이 많으면 시간이 걸릴 수 있어요 (최대 60MB).',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
