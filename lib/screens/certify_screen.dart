import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/watermark_service.dart';
import '../services/share_service.dart';

class CertifyScreen extends StatefulWidget {
  final AppState state;
  final Routine routine;
  final DateTime day;
  const CertifyScreen({
    super.key,
    required this.state,
    required this.routine,
    required this.day,
  });

  @override
  State<CertifyScreen> createState() => _CertifyScreenState();
}

class _CertifyScreenState extends State<CertifyScreen> {
  final _picker = ImagePicker();
  final _memo = TextEditingController();
  final _progress = TextEditingController();
  String? _pickedPath;
  bool _isBackup = false;
  bool _saving = false;

  @override
  void dispose() {
    _memo.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2000,
    );
    if (x != null) setState(() => _pickedPath = x.path);
  }

  Future<void> _submit() async {
    if (_pickedPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증 사진을 먼저 선택해 주세요')),
      );
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();

    // 사진에 날짜·시각 워터마크 자동 삽입
    final stampedPath = await WatermarkService.stamp(_pickedPath!, now);

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
              const Text('인증 완료! ✅',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
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
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
      appBar: AppBar(title: Text("'${r.title}' 인증")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PhotoArea(path: _pickedPath),
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
            decoration: const InputDecoration(
              labelText: '메모 (선택)',
              hintText: '오늘 실행 소감이나 기록',
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
            label: Text(_saving ? '저장 중...' : '인증하기'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  final String? path;
  const _PhotoArea({this.path});

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
                    Text('인증 사진', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : Image.file(File(path!), fit: BoxFit.cover),
      ),
    );
  }
}
