import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/crew.dart';
import '../services/crew_api.dart';
import '../theme.dart';
import '../widgets/report_sheet.dart';

String _when(DateTime t) {
  final now = DateTime.now();
  if (now.difference(t).inMinutes < 1) return '방금';
  if (now.difference(t).inHours < 1) return '${now.difference(t).inMinutes}분 전';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return DateFormat('HH:mm').format(t);
  }
  return DateFormat(t.year == now.year ? 'M/d' : 'yy.M.d').format(t);
}

/// 동호회 게시판 탭 — 공지(운영진, 상단 고정)와 회원 글
class CrewPostsTab extends StatefulWidget {
  final int crewId;
  const CrewPostsTab({super.key, required this.crewId});

  @override
  State<CrewPostsTab> createState() => _CrewPostsTabState();
}

class _CrewPostsTabState extends State<CrewPostsTab> {
  List<CrewPostSummary>? _posts;
  bool _canNotice = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (posts, canNotice, _) = await CrewApi.posts(widget.crewId);
      if (mounted) {
        setState(() {
          _posts = posts;
          _canNotice = canNotice;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _write() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              PostEditScreen(crewId: widget.crewId, canNotice: _canNotice)),
    );
    if (saved == true) _load();
  }

  Future<void> _open(CrewPostSummary p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PostDetailScreen(
              crewId: widget.crewId, postId: p.id, canNotice: _canNotice)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final posts = _posts;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'crew-post-write',
        onPressed: _write,
        icon: const Icon(Icons.edit),
        label: Text(_canNotice ? '공지·글쓰기' : '글쓰기'),
      ),
      body: posts == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: posts.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                            '아직 글이 없어요.\n${_canNotice ? '공지로 이번 주 과제를 안내해 보세요.' : '궁금한 점이나 소식을 나눠 보세요.'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = posts[i];
                        return ListTile(
                          onTap: () => _open(p),
                          tileColor: p.notice
                              ? AppTheme.stamp.withValues(alpha: 0.06)
                              : null,
                          leading: p.notice
                              ? const Icon(Icons.campaign_rounded,
                                  color: AppTheme.stamp)
                              : null,
                          title: Text(p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: p.notice
                                      ? FontWeight.w900
                                      : FontWeight.w700)),
                          subtitle: Text(
                              '${p.author}${p.authorRole != CrewRole.member ? '(${p.authorRole.label})' : ''} · ${_when(p.createdAt)}'
                              '${p.preview.isNotEmpty ? '\n${p.preview.replaceAll('\n', ' ')}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          trailing: p.commentCount > 0
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.chat_bubble_outline,
                                        size: 16),
                                    const SizedBox(width: 3),
                                    Text('${p.commentCount}'),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
    );
  }
}

/// 글쓰기·수정
class PostEditScreen extends StatefulWidget {
  final int crewId;
  final bool canNotice;
  final CrewPostDetail? initial;
  const PostEditScreen(
      {super.key, required this.crewId, required this.canNotice, this.initial});

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _body = TextEditingController(text: widget.initial?.body);
  late bool _notice = widget.initial?.notice ?? widget.canNotice;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제목과 내용을 적어 주세요')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.initial == null) {
        await CrewApi.writePost(widget.crewId,
            title: title, body: body, notice: _notice);
      } else {
        await CrewApi.editPost(widget.crewId, widget.initial!.id,
            title: title, body: body, notice: _notice);
      }
      if (mounted) Navigator.pop(context, true);
    } on CrewApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '글쓰기' : '글 수정'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '올리는 중…' : '올리기')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canNotice)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notice,
              onChanged: (v) => setState(() => _notice = v),
              secondary: const Icon(Icons.campaign_rounded, color: AppTheme.stamp),
              title: const Text('공지로 올리기'),
              subtitle: const Text('게시판 맨 위에 고정돼요'),
            ),
          TextField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(
                labelText: '제목', border: OutlineInputBorder()),
          ),
          TextField(
            controller: _body,
            maxLength: 10000,
            minLines: 8,
            maxLines: 30,
            decoration: const InputDecoration(
                labelText: '내용',
                alignLabelWithHint: true,
                border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}

/// 글 상세 + 댓글
class PostDetailScreen extends StatefulWidget {
  final int crewId;
  final int postId;
  final bool canNotice;
  const PostDetailScreen(
      {super.key,
      required this.crewId,
      required this.postId,
      required this.canNotice});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  CrewPostDetail? _p;
  String? _error;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await CrewApi.post(widget.crewId, widget.postId);
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _send() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await CrewApi.comment(widget.crewId, widget.postId, body);
      _comment.clear();
      await _load();
    } on CrewApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirm(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('삭제')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.notice == true ? '공지' : '게시글'),
        actions: [
          if (p?.canEdit == true)
            IconButton(
              tooltip: '수정',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PostEditScreen(
                          crewId: widget.crewId,
                          canNotice: widget.canNotice,
                          initial: p)),
                );
                if (saved == true) _load();
              },
            ),
          // 남의 글은 신고할 수 있다 (Play UGC 정책)
          if (p != null && !p.canEdit)
            IconButton(
              tooltip: '신고',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showReportSheet(context,
                  crewId: widget.crewId,
                  targetType: 'post',
                  targetId: widget.postId),
            ),
          if (p?.canDelete == true)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await _confirm('이 글을 삭제할까요?')) return;
                try {
                  await CrewApi.deletePost(widget.crewId, widget.postId);
                  if (context.mounted) Navigator.pop(context);
                } on CrewApiException catch (e) {
                  _snack(e.message);
                }
              },
            ),
        ],
      ),
      body: p == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Text(p.title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                          '${p.author}${p.authorRole != CrewRole.member ? '(${p.authorRole.label})' : ''} · '
                          '${DateFormat('yyyy.M.d HH:mm').format(p.createdAt)}',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const Divider(height: 24),
                      SelectableText(p.body,
                          style: const TextStyle(fontSize: 15, height: 1.6)),
                      const Divider(height: 32),
                      Text('댓글 ${p.comments.length}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      ...p.comments.map((c) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                '${c.author}${c.authorRole != CrewRole.member ? '(${c.authorRole.label})' : ''} · ${_when(c.createdAt)}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            subtitle: Text(c.body,
                                style: TextStyle(
                                    fontSize: 14, color: cs.onSurface)),
                            onLongPress: () => showReportSheet(context,
                                crewId: widget.crewId,
                                targetType: 'comment',
                                targetId: c.id),
                            trailing: c.canDelete
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () async {
                                      if (!await _confirm('댓글을 삭제할까요?')) {
                                        return;
                                      }
                                      try {
                                        await CrewApi.deleteComment(
                                            widget.crewId, c.id);
                                        await _load();
                                      } on CrewApiException catch (e) {
                                        _snack(e.message);
                                      }
                                    },
                                  )
                                : IconButton(
                                    tooltip: '신고',
                                    icon: const Icon(Icons.flag_outlined, size: 18),
                                    onPressed: () => showReportSheet(context,
                                        crewId: widget.crewId,
                                        targetType: 'comment',
                                        targetId: c.id),
                                  ),
                          )),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                                hintText: '댓글 달기',
                                counterText: '',
                                border: OutlineInputBorder(),
                                isDense: true),
                          ),
                        ),
                        IconButton(
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
