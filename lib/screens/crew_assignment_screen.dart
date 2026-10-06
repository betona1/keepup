import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../models/crew.dart';
import '../models/routine.dart';
import '../services/crew_api.dart';
import '../services/media_store.dart';
import '../services/watermark_service.dart';
import '../theme.dart';

/// 과제 점검형 제출 — 반장·부반장이 꾸민 양식(글·문항·사진·자료·녹음·링크·수치)을 채워 낸다.
/// 제출하면 개인 도장도 함께 찍히고, 운영진이 '확인' 또는 '보완 요청'으로 점검한다.
class AssignmentSubmitScreen extends StatefulWidget {
  final AppState state;
  final int crewId;
  final int taskId;
  final Routine? routine; // 연동된 개인 루틴 (도장 기록용)
  final String? dateKey; // 지정하지 않으면 지금 회차
  const AssignmentSubmitScreen({
    super.key,
    required this.state,
    required this.crewId,
    required this.taskId,
    this.routine,
    this.dateKey,
  });

  @override
  State<AssignmentSubmitScreen> createState() => _AssignmentSubmitScreenState();
}

class _PickedFile {
  final String name;
  final Uint8List bytes;
  final String mime;
  final String? localPath; // 워터마크 사진의 기기 저장 경로 (개인 도장 사진으로 사용)
  const _PickedFile(this.name, this.bytes, this.mime, {this.localPath});
}

class _AssignmentSubmitScreenState extends State<AssignmentSubmitScreen> {
  CrewSlot? _slot;
  String? _error;
  bool _saving = false;
  final _ctrls = <String, TextEditingController>{};
  final _files = <String, List<_PickedFile>>{};
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  String? _recordingItem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final slot = await CrewApi.slot(widget.crewId, widget.taskId,
          dateKey: widget.dateKey);
      if (!mounted) return;
      // 이전에 낸 답안이 있으면 채워 둔다 (보완 요청 후 고쳐 내기 쉽게)
      for (final item in slot.session.form) {
        if (item.type.isFile) continue;
        final prev = slot.mine?.answers[item.id];
        _ctrls.putIfAbsent(item.id, () => TextEditingController()).text =
            prev == null ? '' : '$prev';
      }
      setState(() {
        _slot = slot;
        _error = null;
      });
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _addFile(FormItem item, _PickedFile f) {
    final list = _files.putIfAbsent(item.id, () => []);
    if (list.length >= (item.maxFiles ?? 3)) {
      _snack('「${item.label}」은 최대 ${item.maxFiles ?? 3}개까지 올릴 수 있어요');
      return;
    }
    setState(() => list.add(f));
  }

  Future<void> _pickPhoto(FormItem item, ImageSource source) async {
    final x = await _picker.pickImage(
        source: source, imageQuality: 92, maxWidth: 2000);
    if (x == null) return;
    final raw = await x.readAsBytes();
    // 인증 사진과 똑같이 날짜·시각 워터마크를 찍는다
    final path = await WatermarkService.stamp(raw, DateTime.now());
    final bytes = await MediaStore.readBytes(path) ?? raw;
    _addFile(item, _PickedFile('photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes, 'image/jpeg',
        localPath: path));
  }

  Future<void> _pickFile(FormItem item, {bool audio = false}) async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: (item.maxFiles ?? 3) > 1,
      type: audio ? FileType.audio : FileType.any,
    );
    if (res == null) return;
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.lengthInBytes > 20 * 1024 * 1024) {
        _snack('${f.name}: 20MB가 넘는 파일은 올릴 수 없어요');
        continue;
      }
      _addFile(item, _PickedFile(f.name, bytes, _mimeOf(f.name, audio: audio)));
    }
  }

  Future<void> _toggleRecord(FormItem item) async {
    if (_recordingItem == item.id) {
      final path = await _recorder.stop();
      setState(() => _recordingItem = null);
      if (path == null) return;
      final bytes = await MediaStore.readBytes(path);
      if (bytes == null) return;
      _addFile(item, _PickedFile(
          'rec_${DateTime.now().millisecondsSinceEpoch}.m4a', bytes, 'audio/mp4'));
      return;
    }
    if (_recordingItem != null) return;
    if (!await _recorder.hasPermission()) {
      _snack('마이크 권한을 허용해 주세요');
      return;
    }
    final dir = await getTemporaryDirectory();
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: '${dir.path}/crew_rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
    setState(() => _recordingItem = item.id);
  }

  static String _mimeOf(String name, {bool audio = false}) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'hwp' => 'application/x-hwp',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt' => 'text/plain',
      'zip' => 'application/zip',
      'm4a' || 'mp4' || 'aac' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'webm' => 'audio/webm',
      _ => audio ? 'audio/mpeg' : 'application/octet-stream',
    };
  }

  /// 화면에서 먼저 확인 — 서버도 같은 규칙으로 다시 검사한다
  String? _validate(List<FormItem> form) {
    for (final item in form) {
      if (item.type.isFile) {
        if (item.required && (_files[item.id]?.isEmpty ?? true)) {
          return '「${item.label}」을 첨부해 주세요';
        }
        continue;
      }
      final v = _ctrls[item.id]?.text.trim() ?? '';
      if (v.isEmpty) {
        if (item.required) return '「${item.label}」을 채워 주세요';
        continue;
      }
      if ((item.type == FormItemType.text ||
              item.type == FormItemType.question) &&
          v.characters.length < (item.minChars ?? 1)) {
        return '「${item.label}」은 ${item.minChars}자 이상 써 주세요 (지금 ${v.characters.length}자)';
      }
      if (item.type == FormItemType.link && !RegExp(r'^https?://\S+$').hasMatch(v)) {
        return '「${item.label}」에 http로 시작하는 주소를 넣어 주세요';
      }
      if (item.type == FormItemType.number && double.tryParse(v) == null) {
        return '「${item.label}」에는 숫자만 넣어 주세요';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final slot = _slot!;
    final form = slot.session.form;
    final problem = _validate(form);
    if (problem != null) {
      _snack(problem);
      return;
    }
    setState(() => _saving = true);
    final answers = <String, Object>{};
    for (final item in form) {
      if (item.type.isFile) continue;
      final v = _ctrls[item.id]?.text.trim() ?? '';
      if (v.isEmpty) continue;
      answers[item.id] = item.type == FormItemType.number ? num.parse(v) : v;
    }
    final uploads = [
      for (final e in _files.entries)
        for (final f in e.value)
          UploadFile(itemId: e.key, name: f.name, bytes: f.bytes, mime: f.mime),
    ];
    try {
      await CrewApi.submitAssignment(
        crewId: widget.crewId,
        taskId: widget.taskId,
        dateKey: slot.session.dateKey,
        answers: answers,
        files: uploads,
        form: form,
      );
      // 개인 도장 — 첫 사진과 첫 글을 기록에 남긴다
      final r = widget.routine;
      if (r != null) {
        final firstPhoto = form
            .where((i) => i.type == FormItemType.photo)
            .expand((i) => _files[i.id] ?? const <_PickedFile>[])
            .map((f) => f.localPath)
            .whereType<String>()
            .firstOrNull;
        final firstText = form
            .where((i) =>
                i.type == FormItemType.text || i.type == FormItemType.question)
            .map((i) => _ctrls[i.id]?.text.trim() ?? '')
            .firstWhere((t) => t.isNotEmpty, orElse: () => '');
        final now = DateTime.now();
        await widget.state.recordCrewAssignmentStamp(Certification(
          id: now.microsecondsSinceEpoch.toString(),
          routineId: r.id,
          dateKey: slot.session.dateKey,
          photoPath: firstPhoto ?? '',
          memo: firstText.length > 300 ? '${firstText.substring(0, 300)}…' : firstText,
          timestamp: now,
          // 사진 없는 제출을 '사진 유실'로 오인하지 않도록 별도 표기
          verifyMethod: firstPhoto != null ? 'photo' : 'assignment',
        ));
      }
      if (!mounted) return;
      _snack(slot.mine == null
          ? '과제를 제출했어요 ✅ 운영진이 점검하면 결과가 표시돼요'
          : '다시 제출했어요 ✅');
      Navigator.pop(context, true);
    } on CrewApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    if (slot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.routine?.title ?? '과제 제출')),
        body: Center(
          child: _error != null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center)),
                  TextButton(onPressed: _load, child: const Text('다시 시도')),
                ])
              : const CircularProgressIndicator(),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final t = slot.task;
    final s = slot.session;
    final mine = slot.mine;
    final left = slot.deadline.difference(DateTime.now());
    final blocked = slot.blockReason != null;
    final d = DateTime.parse(s.dateKey);
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title ?? '${d.month}/${d.day}(${weekdayNames[d.weekday - 1]}) 회차',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    left.isNegative
                        ? '마감됨 · ${DateFormat('M/d HH:mm').format(slot.deadline)}'
                        : '${DateFormat('M/d(E) HH:mm', 'ko').format(slot.deadline)} 마감 · '
                            '${left.inDays > 0 ? '${left.inDays}일 ' : ''}${left.inHours % 24}시간 ${left.inMinutes % 60}분 남음',
                    style: TextStyle(
                        color: !left.isNegative && left.inHours < 3
                            ? cs.error
                            : cs.onSurfaceVariant),
                  ),
                  if (t.reason.isNotEmpty || (s.guide?.isNotEmpty ?? false)) ...[
                    const Divider(height: 20),
                    if (t.reason.isNotEmpty) Text(t.reason),
                    if (s.guide?.isNotEmpty ?? false) ...[
                      if (t.reason.isNotEmpty) const SizedBox(height: 8),
                      Text(s.guide!,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (mine != null) _MyStatusCard(mine: mine),
          if (blocked)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(CrewApi.messageFor(slot.blockReason!),
                    style: TextStyle(color: cs.onErrorContainer)),
              ),
            ),
          const SizedBox(height: 8),
          ...s.form.map((item) => _itemField(item, enabled: !blocked)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: blocked || _saving ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(_saving
                ? '올리는 중…'
                : mine == null
                    ? '과제 제출'
                    : '다시 제출 (점검 결과는 초기화돼요)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          if (mine != null && mine.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('다시 제출하면 이전에 올린 첨부(${mine.files.length}개)는 새로 고른 것으로 바뀌어요.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _label(FormItem item) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Row(
          children: [
            Flexible(
              child: Text(item.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(width: 6),
            Text(item.required ? '필수' : '선택',
                style: TextStyle(
                    fontSize: 11,
                    color: item.required ? AppTheme.stamp : Colors.grey)),
          ],
        ),
      );

  Widget _itemField(FormItem item, {required bool enabled}) {
    final ctrl = _ctrls.putIfAbsent(item.id, () => TextEditingController());
    switch (item.type) {
      case FormItemType.text:
      case FormItemType.question:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(item),
            TextField(
              controller: ctrl,
              enabled: enabled,
              minLines: item.type == FormItemType.text ? 4 : 2,
              maxLines: 12,
              maxLength: 10000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: (item.minChars ?? 1) > 1
                    ? '${item.minChars}자 이상'
                    : item.type == FormItemType.question
                        ? '답을 적어 주세요'
                        : null,
                counterText: '${ctrl.text.characters.length}자'
                    '${(item.minChars ?? 1) > 1 ? ' / 최소 ${item.minChars}자' : ''}',
              ),
            ),
          ],
        );
      case FormItemType.link:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(item),
            TextField(
              controller: ctrl,
              enabled: enabled,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'https://',
                  prefixIcon: Icon(Icons.link)),
            ),
          ],
        );
      case FormItemType.number:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(item),
            TextField(
              controller: ctrl,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  suffixText: item.unit),
            ),
          ],
        );
      case FormItemType.photo:
      case FormItemType.file:
      case FormItemType.audio:
        final list = _files[item.id] ?? const <_PickedFile>[];
        final prev = _slot?.mine?.files.where((f) => f.itemId == item.id).toList() ??
            const <SubmissionFile>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(item),
            if (list.isEmpty && prev.isNotEmpty)
              Text('이전 제출: ${prev.map((f) => f.name).join(', ')}',
                  style: const TextStyle(fontSize: 12)),
            ...list.asMap().entries.map((e) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: item.type == FormItemType.photo
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(e.value.bytes,
                                width: 44, height: 44, fit: BoxFit.cover))
                        : Icon(item.type == FormItemType.audio
                            ? Icons.graphic_eq
                            : Icons.description_outlined),
                    title: Text(e.value.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${(e.value.bytes.lengthInBytes / 1024).toStringAsFixed(0)}KB'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => list.removeAt(e.key)),
                    ),
                  ),
                )),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (item.type == FormItemType.photo) ...[
                  if (!kIsWeb)
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () => _pickPhoto(item, ImageSource.camera)
                          : null,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('촬영'),
                    ),
                  OutlinedButton.icon(
                    onPressed: enabled
                        ? () => _pickPhoto(item, ImageSource.gallery)
                        : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('사진 선택'),
                  ),
                ],
                if (item.type == FormItemType.file)
                  OutlinedButton.icon(
                    onPressed: enabled ? () => _pickFile(item) : null,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('자료 첨부 (PDF·문서·이미지 등)'),
                  ),
                if (item.type == FormItemType.audio) ...[
                  if (!kIsWeb)
                    FilledButton.tonalIcon(
                      onPressed: enabled ? () => _toggleRecord(item) : null,
                      icon: Icon(_recordingItem == item.id
                          ? Icons.stop_circle_outlined
                          : Icons.mic),
                      label: Text(
                          _recordingItem == item.id ? '녹음 끝내기' : '녹음하기'),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        enabled ? () => _pickFile(item, audio: true) : null,
                    icon: const Icon(Icons.audio_file_outlined),
                    label: const Text('녹음 파일 선택'),
                  ),
                ],
              ],
            ),
            Text('최대 ${item.maxFiles ?? 3}개 · ${item.type == FormItemType.photo ? '사진 5MB' : '파일 20MB'}까지',
                style: const TextStyle(fontSize: 11)),
          ],
        );
    }
  }
}

class _MyStatusCard extends StatelessWidget {
  final CrewSubmission mine;
  const _MyStatusCard({required this.mine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (String title, Color color, IconData icon) = switch (mine.reviewStatus) {
      'approved' => ('운영진 확인 완료', AppTheme.success, Icons.verified),
      'rejected' => ('보완 요청을 받았어요 — 고쳐서 다시 내 주세요', cs.error, Icons.edit_note),
      _ => mine.status == 'excused'
          ? ('운영진이 인정 처리했어요', AppTheme.stamp, Icons.verified_outlined)
          : ('제출 완료 · 점검 대기 중', AppTheme.stamp, Icons.hourglass_top),
    };
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style:
                        TextStyle(fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('제출 ${DateFormat('M/d HH:mm').format(mine.submittedAt)}',
                style: const TextStyle(fontSize: 12)),
            if (mine.reviewNote?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text('💬 ${mine.reviewNote}'),
            ],
          ],
        ),
      ),
    );
  }
}
