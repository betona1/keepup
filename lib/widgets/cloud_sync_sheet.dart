import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
      await widget.state.restoreAll(routines, certs);
      _say('복원 완료 — 루틴 ${routines.length}개, 인증 ${certs.length}개 🎉');
    } catch (e) {
      _say('$e'.replaceFirst('Bad state: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
