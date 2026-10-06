import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/crew.dart';
import '../services/crew_api.dart';
import '../theme.dart';
import '../widgets/report_sheet.dart';

/// 제출 상세 — 답안·첨부를 보고, 반장·부반장은 '확인' 또는 '보완 요청'으로 점검한다.
/// 회원끼리도 서로의 과제를 열어 볼 수 있다 (함께 배우기).
class SubmissionDetailScreen extends StatefulWidget {
  final int crewId;
  final int submissionId;
  const SubmissionDetailScreen(
      {super.key, required this.crewId, required this.submissionId});

  @override
  State<SubmissionDetailScreen> createState() => _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends State<SubmissionDetailScreen> {
  SubmissionDetail? _d;
  String? _error;
  Map<String, String> _headers = const {};
  final _player = AudioPlayer();
  int? _playingFile;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    CrewApi.imageHeaders().then((h) {
      if (mounted) setState(() => _headers = h);
    });
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingFile = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await CrewApi.submissionDetail(widget.crewId, widget.submissionId);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _review(String status) async {
    String? note;
    if (status != 'clear') {
      final ctrl = TextEditingController(text: _d?.submission.reviewNote);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(status == 'approved' ? '확인 처리' : '보완 요청'),
          content: TextField(
            controller: ctrl,
            autofocus: status == 'rejected',
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: status == 'approved'
                  ? '칭찬 한마디 (선택)'
                  : '무엇을 보완하면 될지 적어 주세요 (필수)',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(status == 'approved' ? '확인' : '보완 요청')),
          ],
        ),
      );
      note = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
      if (status == 'rejected' && note.isEmpty) {
        _snack('보완할 내용을 적어 주세요');
        return;
      }
    }
    try {
      await CrewApi.review(widget.crewId, widget.submissionId,
          status: status, note: note);
      _changed = true;
      await _load();
      _snack(switch (status) {
        'approved' => '확인 처리했어요 ✅',
        'rejected' => '보완 요청을 보냈어요. 회원이 마감 전까지 다시 낼 수 있어요',
        _ => '점검을 취소했어요',
      });
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  /// 자료 열기 — 웹은 같은 주소로 내려받고, 앱은 받아서 공유 시트(열기·저장)로 넘긴다
  Future<void> _openFile(SubmissionFile f) async {
    if (kIsWeb) {
      await launchUrl(Uri.base.resolve(f.url));
      return;
    }
    try {
      final bytes = await CrewApi.download(f.url);
      await SharePlus.instance.share(ShareParams(files: [
        XFile.fromData(bytes, name: f.name, mimeType: f.contentType)
      ], fileNameOverrides: [
        f.name
      ]));
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _toggleAudio(SubmissionFile f) async {
    if (_playingFile == f.id) {
      await _player.stop();
      setState(() => _playingFile = null);
      return;
    }
    try {
      if (kIsWeb) {
        await _player.play(UrlSource(Uri.base.resolve(f.url).toString()));
      } else {
        final bytes = await CrewApi.download(f.url);
        await _player.play(BytesSource(bytes, mimeType: f.contentType));
      }
      setState(() => _playingFile = f.id);
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  void _openPhoto(String url) => showDialog(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            child: Image.network(CrewApi.mediaUrl(url),
                headers: _headers, fit: BoxFit.contain),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(d?.member?.displayName ?? '제출 내용'),
          actions: [
            if (d != null && !(d.member?.isMe ?? false))
              IconButton(
                tooltip: '신고',
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => showReportSheet(context,
                    crewId: widget.crewId,
                    targetType: 'submission',
                    targetId: widget.submissionId),
              ),
          ],
        ),
        body: d == null
            ? Center(
                child: _error != null
                    ? Text(_error!)
                    : const CircularProgressIndicator())
            : _body(d),
      ),
    );
  }

  Widget _body(SubmissionDetail d) {
    final cs = Theme.of(context).colorScheme;
    final s = d.submission;
    final date = DateTime.parse(s.dateKey);
    final form = d.session.form;
    final known = form.map((i) => i.id).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        Text(d.task.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text(
            '${d.session.title ?? '${date.month}/${date.day} 회차'} · '
            '${DateFormat('M/d HH:mm').format(s.submittedAt)} 제출',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        _ReviewBanner(sub: s),
        if (s.status == 'excused')
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined, color: AppTheme.stamp),
              title: const Text('운영진 인정 처리'),
              subtitle: s.memo == null ? null : Text(s.memo!),
            ),
          ),
        // 인증형 제출 (사진·소감)
        if (s.photoUrl != null)
          GestureDetector(
            onTap: () => _openPhoto(s.photoUrl!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(CrewApi.mediaUrl(s.photoUrl!),
                  headers: _headers, height: 240, fit: BoxFit.cover),
            ),
          ),
        if (s.status == 'submitted' && s.memo != null && s.answers.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.memo!)),
        // 과제 점검형 답안 — 양식 순서대로
        ...form.map((item) => _answer(item, s)),
        // 양식이 바뀌어 지금 양식에 없는 답안도 버리지 않고 보여 준다
        ...s.answers.entries
            .where((e) => !known.contains(e.key))
            .map((e) => ListTile(title: Text(e.key), subtitle: Text('${e.value}'))),
        if (d.canReview && s.status == 'submitted') ...[
          const Divider(height: 32),
          const Text('점검',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _review('approved'),
                  icon: const Icon(Icons.check),
                  label: const Text('확인'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _review('rejected'),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('보완 요청'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ],
          ),
          if (s.reviewStatus != null)
            TextButton(
                onPressed: () => _review('clear'),
                child: const Text('점검 취소 (검토 대기로 되돌리기)')),
        ],
      ],
    );
  }

  Widget _answer(FormItem item, CrewSubmission s) {
    final cs = Theme.of(context).colorScheme;
    final title = Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(item.label,
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    if (item.type.isFile) {
      final files = s.files.where((f) => f.itemId == item.id).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (files.isEmpty)
            Text('(첨부 없음)', style: TextStyle(color: cs.onSurfaceVariant)),
          if (item.type == FormItemType.photo)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: files
                  .map((f) => GestureDetector(
                        onTap: () => _openPhoto(f.url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(CrewApi.mediaUrl(f.url),
                              headers: _headers,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                              cacheWidth: 330),
                        ),
                      ))
                  .toList(),
            )
          else
            ...files.map((f) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(item.type == FormItemType.audio
                        ? (_playingFile == f.id
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline)
                        : Icons.description_outlined),
                    title: Text(f.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(f.sizeLabel),
                    trailing: IconButton(
                      tooltip: '열기·저장',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => _openFile(f),
                    ),
                    onTap: item.type == FormItemType.audio
                        ? () => _toggleAudio(f)
                        : () => _openFile(f),
                  ),
                )),
        ],
      );
    }
    final v = s.answers[item.id];
    final text = v == null
        ? '(비어 있음)'
        : item.type == FormItemType.number
            ? '$v${item.unit ?? ''}'
            : '$v';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        if (item.type == FormItemType.link && v != null)
          InkWell(
            onTap: () => launchUrl(Uri.parse('$v'),
                mode: LaunchMode.externalApplication),
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.seed,
                    decoration: TextDecoration.underline)),
          )
        else
          SelectableText(text,
              style: TextStyle(
                  color: v == null ? cs.onSurfaceVariant : null, height: 1.5)),
      ],
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  final CrewSubmission sub;
  const _ReviewBanner({required this.sub});

  @override
  Widget build(BuildContext context) {
    if (sub.status != 'submitted') return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final (String label, Color color) = switch (sub.reviewStatus) {
      'approved' => ('확인 완료', AppTheme.success),
      'rejected' => ('보완 요청', cs.error),
      _ => ('점검 대기', AppTheme.stamp),
    };
    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(Icons.fact_check_outlined, color: color),
        title: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        subtitle: sub.reviewNote == null ? null : Text('💬 ${sub.reviewNote}'),
      ),
    );
  }
}
