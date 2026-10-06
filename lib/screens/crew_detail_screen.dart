import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models/crew.dart';
import '../models/routine.dart';
import '../services/crew_api.dart';
import '../services/crew_sync_service.dart';
import '../theme.dart';
import 'crew_screen.dart';
import 'crew_task_form_screen.dart';
import 'crew_assignment_screen.dart';
import 'crew_posts_screen.dart';
import 'crew_sessions_screen.dart';
import 'crew_submission_screen.dart';

final _won = NumberFormat('#,###');
String _wonLabel(int v) => '${_won.format(v)}원';
String _dot(String key) => key.replaceAll('-', '.');
String _md(String key) {
  final d = DateTime.parse(key);
  return '${d.month}/${d.day}(${weekdayNames[d.weekday - 1]})';
}

/// 동호회 상세 — 현황 · 통계 · 정산 · 회원 · 과제
class CrewDetailScreen extends StatefulWidget {
  final int crewId;
  final AppState state;
  const CrewDetailScreen({super.key, required this.crewId, required this.state});

  @override
  State<CrewDetailScreen> createState() => _CrewDetailScreenState();
}

class _CrewDetailScreenState extends State<CrewDetailScreen> {
  CrewDetail? _d;
  String? _error;
  Map<String, String> _imgHeaders = const {};
  int _version = 0; // 하위 탭 새로고침 신호

  @override
  void initState() {
    super.initState();
    CrewApi.imageHeaders().then((h) {
      if (mounted) setState(() => _imgHeaders = h);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await CrewApi.detail(widget.crewId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = null;
        _version++;
      });
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// 과제·회원이 바뀌면 개인 루틴도 바로 맞춘다
  Future<void> _reloadAll() async {
    await _load();
    CrewSyncService.instance.syncTasks(force: true).catchError((_) {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() fn, {String? done}) async {
    try {
      await fn();
      if (done != null) _snack(done);
      await _reloadAll();
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _menu(String v) async {
    final d = _d!;
    switch (v) {
      case 'handover':
        await _handover(d);
      case 'settings':
        final body = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => CrewSettingsDialog(initial: d.crew));
        if (body != null) {
          await _run(() => CrewApi.updateCrew(d.crew.id, body), done: '저장했어요');
        }
      case 'leave':
        if (await _confirm('동호회에서 나갈까요?',
            '동호회 과제 루틴은 도장이 있으면 개인 루틴으로 남고, 없으면 정리돼요.')) {
          try {
            await CrewApi.leaveCrew(d.crew.id);
            await CrewSyncService.instance.syncTasks(force: true);
            if (mounted) Navigator.pop(context);
          } on CrewApiException catch (e) {
            _snack(e.message);
          }
        }
      case 'delete':
        if (await _confirm('동호회를 해체할까요?',
            '모든 회원의 동호회 과제가 종료돼요. 되돌릴 수 없어요.')) {
          try {
            await CrewApi.deleteCrew(d.crew.id);
            await CrewSyncService.instance.syncTasks(force: true);
            if (mounted) Navigator.pop(context);
          } on CrewApiException catch (e) {
            _snack(e.message);
          }
        }
    }
  }

  /// 반장 넘기기 — 앱을 쓰는 회원 중에서 고르면, 그 사람이 반장이 되고 나는 부반장이 된다
  Future<void> _handover(CrewDetail d) async {
    final candidates =
        d.members.where((m) => !m.isMe && !m.offline).toList();
    if (candidates.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('넘길 회원이 없어요'),
          content: const Text('반장은 앱(또는 웹앱)에 로그인해 동호회에 가입한 회원에게만 넘길 수 있어요.\n\n'
              '새 반장님이 Pro 키를 등록하고 초대코드로 먼저 가입하게 해 주세요. '
              '(앱 미설치 회원으로 등록된 사람에게는 넘길 수 없어요)'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인')),
          ],
        ),
      );
      return;
    }
    final target = await showModalBottomSheet<CrewMember>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('누구에게 반장을 넘길까요?',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('넘기면 나는 자동으로 부반장이 돼요'),
              ),
              const Divider(height: 1),
              ...candidates.map((m) => ListTile(
                    leading: CircleAvatar(
                      backgroundImage: m.avatarUrl != null
                          ? NetworkImage(m.avatarUrl!)
                          : null,
                      child: m.avatarUrl == null
                          ? Text(m.displayName.isEmpty
                              ? '?'
                              : m.displayName.characters.first)
                          : null,
                    ),
                    title: Text(m.displayName),
                    subtitle: Text(m.role.label),
                    onTap: () => Navigator.pop(ctx, m),
                  )),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    if (!await _confirm('${target.displayName} 님에게 반장을 넘길까요?',
        '${target.displayName} 님이 반장이 되고, 나는 부반장이 돼요.\n'
            '부반장도 과제 올리기·점검·통계·정산·미설치 회원 관리는 그대로 할 수 있어요.\n'
            '되돌리려면 새 반장님이 다시 넘겨 줘야 해요.')) {
      return;
    }
    await _run(
        () => CrewApi.updateMember(d.crew.id, target.id, {'role': 'leader'}),
        done: '${target.displayName} 님이 반장이 됐어요. 나는 부반장이에요 ✅');
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('확인')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('동호회')),
        body: Center(
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('다시 시도')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final role = d.me.role;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.crew.name,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                  '${_dot(d.crew.startDate)} ~ ${_dot(d.crew.endDate)} · 나는 ${role.label}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (role == CrewRole.leader)
                  const PopupMenuItem(value: 'settings', child: Text('동호회 설정')),
                if (role == CrewRole.leader)
                  const PopupMenuItem(
                      value: 'handover', child: Text('반장 넘기기')),
                if (role != CrewRole.leader)
                  const PopupMenuItem(value: 'leave', child: Text('동호회 나가기')),
                if (role == CrewRole.leader)
                  const PopupMenuItem(value: 'delete', child: Text('동호회 해체')),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '현황'),
              Tab(text: '게시판'),
              Tab(text: '통계'),
              Tab(text: '정산'),
              Tab(text: '회원'),
              Tab(text: '과제'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BoardTab(
                key: ValueKey('board$_version'),
                detail: d,
                state: widget.state,
                imgHeaders: _imgHeaders),
            CrewPostsTab(crewId: d.crew.id),
            _StatsTab(key: ValueKey('stats$_version'), detail: d),
            _SettlementTab(key: ValueKey('settle$_version'), detail: d),
            _MembersTab(detail: d, run: _run, confirm: _confirm),
            _TasksTab(detail: d, run: _run, confirm: _confirm, reload: _reloadAll),
          ],
        ),
      ),
    );
  }
}

// ═══ 현황판 ══════════════════════════════════════════════════════════

class _BoardTab extends StatefulWidget {
  final CrewDetail detail;
  final AppState state;
  final Map<String, String> imgHeaders;
  const _BoardTab(
      {super.key,
      required this.detail,
      required this.state,
      required this.imgHeaders});

  @override
  State<_BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<_BoardTab> {
  late String _date = widget.detail.today;
  CrewBoard? _board;
  String? _error;
  final _fmt = DateFormat('yyyy-MM-dd');

  bool get _manager => widget.detail.me.role.isManager;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await CrewApi.board(widget.detail.crew.id, date: _date);
      if (mounted) {
        setState(() {
          _board = b;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _shift(int days) {
    final d = DateTime.parse(_date).add(Duration(days: days));
    if (_fmt.format(d).compareTo(widget.detail.today) > 0) return;
    setState(() {
      _date = _fmt.format(d);
      _board = null;
    });
    _load();
  }

  /// 아직 안 낸 사람 목록을 카톡방에 공유 — 부반장의 독려·보고용
  void _sharePending() {
    final b = _board!;
    final lines = <String>['[${widget.detail.crew.name}] ${_md(b.date)} 과제 현황'];
    for (final t in b.tasks) {
      final todo = t.entries
          .where((e) =>
              e.status == SlotStatus.pending ||
              e.status == SlotStatus.missed ||
              e.status == SlotStatus.rejected)
          .map((e) => b.member(e.memberId)?.displayName ?? '?')
          .toList();
      lines.add('\n📌 ${t.task.title} (${t.doneCount}/${t.entries.length} 제출)');
      lines.add(todo.isEmpty
          ? '  🎉 전원 제출 완료!'
          : '  ⏰ 미제출: ${todo.join(', ')}');
      if (t.deadline.isAfter(DateTime.now())) {
        lines.add('  마감 ${DateFormat('M/d HH:mm').format(t.deadline)}');
      }
    }
    SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  Future<void> _manage(BoardTask t, BoardEntry e) async {
    final m = _board!.member(e.memberId);
    final memoCtrl = TextEditingController();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${m?.displayName} · ${t.task.title}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${_md(t.dutyKey)} 의무 · 현재 ${e.status.label}'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: memoCtrl,
                decoration: const InputDecoration(
                    hintText: '메모 (예: 카톡방 인증 확인, 병원 진료)',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: AppTheme.success),
              title: const Text('대리 제출 처리'),
              subtitle: const Text('카톡 등 앱 밖에서 인증한 경우'),
              onTap: () => Navigator.pop(ctx, 'submitted'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined, color: AppTheme.stamp),
              title: const Text('인정 처리'),
              subtitle: const Text('사정이 있어 미제출을 인정 (벌금 없음)'),
              onTap: () => Navigator.pop(ctx, 'excused'),
            ),
            if (e.submissionId != null)
              ListTile(
                leading: Icon(Icons.undo,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('기록 지우기'),
                subtitle: const Text('잘못 체크했거나 부적절한 제출'),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
          ],
        ),
      ),
    );
    final memo = memoCtrl.text.trim();
    memoCtrl.dispose();
    if (action == null) return;
    try {
      await CrewApi.mark(widget.detail.crew.id,
          taskId: t.task.id,
          memberId: e.memberId,
          dateKey: t.dutyKey,
          status: action,
          memo: memo);
      await _load();
    } on CrewApiException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err.message)));
      }
    }
  }

  Future<void> _openSubmission(BoardEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SubmissionDetailScreen(
              crewId: widget.detail.crew.id, submissionId: e.submissionId!)),
    );
    _load();
  }

  Future<void> _submitMine(BoardTask t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignmentSubmitScreen(
          state: widget.state,
          crewId: widget.detail.crew.id,
          taskId: t.task.id,
          // 회차는 서버가 정한다 — 이번 회차 마감이 지났으면 다음 회차로
          routine: widget.state.routineById(CrewTask.routineIdFor(t.task.id)),
        ),
      ),
    );
    _load();
  }

  void _openPhoto(String url, String caption) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.network(CrewApi.mediaUrl(url),
                  headers: widget.imgHeaders, fit: BoxFit.contain),
            ),
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(caption),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = _board;
    final isToday = _date == widget.detail.today;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(_date),
                      firstDate: DateTime.parse(widget.detail.crew.startDate)
                          .subtract(const Duration(days: 30)),
                      lastDate: DateTime.parse(widget.detail.today),
                    );
                    if (p != null) {
                      setState(() {
                        _date = _fmt.format(p);
                        _board = null;
                      });
                      _load();
                    }
                  },
                  child: Text(
                      isToday ? '오늘 · ${_md(_date)}' : _md(_date),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
              IconButton(
                  onPressed: isToday ? null : () => _shift(1),
                  icon: const Icon(Icons.chevron_right)),
              IconButton(
                tooltip: '미제출 현황 공유',
                onPressed: b == null ? null : _sharePending,
                icon: const Icon(Icons.ios_share),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          if (b == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (b != null && b.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                widget.detail.tasks.isEmpty
                    ? '아직 과제가 없어요.\n${_manager ? '과제 탭에서 공통 과제를 만들어 주세요.' : '반장이 과제를 만들면 여기에 보여요.'}'
                    : '이 날은 제출할 과제가 없어요 (휴일·기간 밖)',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          if (b != null)
            ...b.tasks.map((t) => _BoardTaskCard(
                  board: b,
                  t: t,
                  imgHeaders: widget.imgHeaders,
                  manager: _manager,
                  onManage: (e) => _manage(t, e),
                  onOpen: _openSubmission,
                  onSubmitMine: t.task.isAssignment &&
                          !widget.detail.me.offline &&
                          t.entries.any((e) => e.memberId == widget.detail.me.id)
                      ? () => _submitMine(t)
                      : null,
                  onPhoto: _openPhoto,
                )),
        ],
      ),
    );
  }
}

class _BoardTaskCard extends StatelessWidget {
  final CrewBoard board;
  final BoardTask t;
  final Map<String, String> imgHeaders;
  final bool manager;
  final void Function(BoardEntry) onManage;
  final void Function(BoardEntry) onOpen;
  final VoidCallback? onSubmitMine;
  final void Function(String url, String caption) onPhoto;
  const _BoardTaskCard({
    required this.board,
    required this.t,
    required this.imgHeaders,
    required this.manager,
    required this.onManage,
    required this.onOpen,
    required this.onSubmitMine,
    required this.onPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = t.entries.length;
    final done = t.doneCount;
    final passed = t.deadline.isBefore(DateTime.now());
    final left = t.deadline.difference(DateTime.now());
    final deadlineLabel = passed
        ? '마감됨'
        : left.inHours >= 24
            ? '${_md(t.dutyKey)} ${DateFormat('HH:mm').format(t.deadline)} 마감'
            : '마감까지 ${left.inHours}시간 ${left.inMinutes % 60}분';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.task.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                Text('$done/$total',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: AppTheme.stamp)),
              ],
            ),
            const SizedBox(height: 2),
            if (t.sessionTitle != null)
              Text(t.sessionTitle!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                t.task.isAssignment
                    ? '${t.task.kind.label} · $deadlineLabel'
                    : '${t.task.dutyCycle.label} · ${t.task.verifyMethod.label} · $deadlineLabel',
                style: TextStyle(
                    fontSize: 12,
                    color: !passed && left.inHours < 3
                        ? cs.error
                        : cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: AppTheme.stamp,
              ),
            ),
            if (onSubmitMine != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: onSubmitMine,
                  icon: const Icon(Icons.edit_document),
                  label: Text(t.entries
                          .firstWhere((e) => board.member(e.memberId)?.isMe ?? false,
                              orElse: () => t.entries.first)
                          .submissionId ==
                      null
                      ? '내 과제 제출하기'
                      : '내 제출 보기 · 다시 내기'),
                ),
              ),
            const SizedBox(height: 4),
            ...t.entries.map((e) {
              final m = board.member(e.memberId);
              final caption = [
                if (e.memo != null) e.memo!,
                if (e.progressValue != null) '진행: ${e.progressValue}',
                if (e.fileCount > 0) '📎 첨부 ${e.fileCount}개',
                if (e.reviewNote != null) '💬 ${e.reviewNote}',
              ].join('\n');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                // 제출이 있으면 누구나 내용을 열어 본다 (운영진은 그 안에서 점검).
                // 대리 제출·인정·지우기는 운영진이 길게 눌러서.
                onTap: e.submissionId != null
                    ? () => onOpen(e)
                    : manager
                        ? () => onManage(e)
                        : null,
                onLongPress: manager ? () => onManage(e) : null,
                leading: e.photoUrl != null
                    ? GestureDetector(
                        onTap: () => onPhoto(e.photoUrl!, caption),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            CrewApi.mediaUrl(e.photoUrl!),
                            headers: imgHeaders,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            cacheWidth: 132,
                            errorBuilder: (_, __, ___) => const SizedBox(
                                width: 44,
                                height: 44,
                                child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                      )
                    : CircleAvatar(
                        radius: 22,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: Text(
                            (m?.displayName.isNotEmpty ?? false)
                                ? m!.displayName.characters.first
                                : '?',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(m?.displayName ?? '?',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (m != null && m.role != CrewRole.member)
                      _Tag(m.role.label, AppTheme.stamp),
                    if (m?.offline ?? false) _Tag('미설치', Colors.blueGrey),
                    if (e.isBackup) _Tag('백업', Colors.orange),
                  ],
                ),
                subtitle: caption.isEmpty && !e.byManager
                    ? null
                    : Text(
                        [
                          if (caption.isNotEmpty) caption,
                          if (e.byManager) '운영진 체크',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                trailing: _StatusChip(e.status),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}

class _StatusChip extends StatelessWidget {
  final SlotStatus s;
  const _StatusChip(this.s);

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (s) {
      SlotStatus.submitted => (AppTheme.seed, Colors.white),
      SlotStatus.approved => (AppTheme.success, Colors.white),
      SlotStatus.rejected => (Colors.orange.shade700, Colors.white),
      SlotStatus.excused => (AppTheme.stamp, Colors.white),
      SlotStatus.missed => (Theme.of(context).colorScheme.error, Colors.white),
      SlotStatus.pending => (
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ═══ 통계 ════════════════════════════════════════════════════════════

class _StatsTab extends StatefulWidget {
  final CrewDetail detail;
  const _StatsTab({super.key, required this.detail});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  CrewStats? _s;
  String? _error;
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await CrewApi.stats(widget.detail.crew.id, from: _from, to: _to);
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickRange() async {
    final s = _s;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.parse(widget.detail.crew.startDate)
          .subtract(const Duration(days: 365)),
      lastDate: DateTime.parse(widget.detail.today),
      initialDateRange: s == null
          ? null
          : DateTimeRange(
              start: DateTime.parse(s.from), end: DateTime.parse(s.to)),
    );
    if (range == null) return;
    final f = DateFormat('yyyy-MM-dd');
    setState(() {
      _from = f.format(range.start);
      _to = f.format(range.end);
      _s = null;
    });
    _load();
  }

  /// 보고서 — 부반장이 카톡방에 그대로 붙여넣을 수 있는 형태
  void _shareReport() {
    final s = _s!;
    final lines = <String>[
      '[${widget.detail.crew.name}] 과제 통계 보고',
      '기간: ${_dot(s.from)} ~ ${_dot(s.to)} · 전체 달성률 ${s.overallRate}%',
      '',
    ];
    for (final m in s.members) {
      lines.add('${m.member.displayName}${m.member.role != CrewRole.member ? '(${m.member.role.label})' : ''}'
          ' ${m.rate}% — 제출 ${m.done} · 인정 ${m.excused} · 미제출 ${m.missed}');
      if (m.missed > 0) {
        final dates = m.missedList.map((x) => _md(x.dateKey)).toSet().take(10);
        lines.add('   미제출: ${dates.join(', ')}${m.missedList.length > 10 ? ' 외' : ''}');
      }
    }
    SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    if (s == null) {
      return Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator());
    }
    final ranked = [...s.members]..sort((a, b) => a.rate.compareTo(b.rate));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text('${_dot(s.from)} ~ ${_dot(s.to)}'),
                ),
              ),
              IconButton(
                  tooltip: '보고서 공유',
                  onPressed: _shareReport,
                  icon: const Icon(Icons.ios_share)),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('${s.overallRate}%',
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.stamp)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        '동호회 전체 달성률\n미제출 ${s.members.fold(0, (a, m) => a + m.missed)}회 · 회원 ${s.members.length}명',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('마감이 지난 의무일 기준 · 달성률 낮은 순',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          ...ranked.map((m) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  shape: const Border(),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${m.member.displayName}${m.member.isMe ? ' (나)' : ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      if (m.member.offline) _Tag('미설치', Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text('${m.rate}%',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: m.missed > 0 ? cs.error : AppTheme.success)),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: m.rate / 100,
                            minHeight: 6,
                            color: m.missed > 0 ? cs.error : AppTheme.success,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '의무 ${m.due} · 제출 ${m.done} · 인정 ${m.excused} · 미제출 ${m.missed}',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  children: [
                    if (m.missedList.isEmpty)
                      const ListTile(dense: true, title: Text('미제출 없음 🎉'))
                    else
                      ...m.missedList.reversed.take(30).map((x) => ListTile(
                            dense: true,
                            leading: Icon(Icons.close, color: cs.error, size: 18),
                            title: Text(_md(x.dateKey)),
                            subtitle: Text(s.taskTitles[x.taskId] ?? ''),
                          )),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══ 정산 ════════════════════════════════════════════════════════════

class _SettlementTab extends StatefulWidget {
  final CrewDetail detail;
  const _SettlementTab({super.key, required this.detail});

  @override
  State<_SettlementTab> createState() => _SettlementTabState();
}

class _SettlementTabState extends State<_SettlementTab> {
  CrewSettlement? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await CrewApi.settlement(widget.detail.crew.id);
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addPayment(SettlementLine l) async {
    var kind = l.fineBalance > 0 ? 'fine_paid' : 'prize_paid';
    final amount = TextEditingController(
        text: '${kind == 'fine_paid' ? l.fineBalance : (l.prize - l.prizePaid).clamp(0, 1 << 31)}');
    final memo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${l.member.displayName} 정산 기록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fine_paid', label: Text('벌금 납부')),
                  ButtonSegment(value: 'prize_paid', label: Text('상금 지급')),
                  ButtonSegment(value: 'adjust', label: Text('조정')),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setD(() => kind = v.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                    labelText: '금액(원)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: memo,
                decoration: const InputDecoration(
                    labelText: '메모 (예: 계좌이체 10/6)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 6),
              const Text('조정은 벌금에서 깎아 줄 금액이에요 (납부로 처리)',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('기록')),
          ],
        ),
      ),
    );
    final value = int.tryParse(amount.text.trim()) ?? 0;
    final memoText = memo.text.trim();
    amount.dispose();
    memo.dispose();
    if (ok != true || value == 0) return;
    try {
      await CrewApi.addPayment(widget.detail.crew.id,
          memberId: l.member.id, kind: kind, amount: value, memo: memoText);
      await _load();
    } on CrewApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _share() {
    final s = _s!;
    final lines = <String>[
      '[${widget.detail.crew.name}] 정산 (${_dot(s.from)} ~ ${_dot(s.to)})',
      '미제출 1회 ${_wonLabel(s.fineAmount)}${s.fineCap > 0 ? ' · 1인 상한 ${_wonLabel(s.fineCap)}' : ''}',
      '벌금 합계 ${_wonLabel(s.pool)} → 완주자 ${s.winnerCount}명 · 1인 ${_wonLabel(s.share)}',
      '',
      for (final l in s.lines)
        '${l.member.displayName}: ${l.exempt ? '정산 제외' : l.winner ? '🏆 완주 · 상금 ${_wonLabel(l.prize)}${l.prizePaid > 0 ? ' (지급 ${_wonLabel(l.prizePaid)})' : ''}' : '미제출 ${l.missed}회 · 벌금 ${_wonLabel(l.fine)}${l.fineBalance > 0 ? ' (미납 ${_wonLabel(l.fineBalance)})' : ' (완납)'}'}',
    ];
    SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _s;
    if (s == null) {
      return Center(
          child: _error != null
              ? Text(_error!)
              : const CircularProgressIndicator());
    }
    final names = {for (final m in widget.detail.members) m.id: m.displayName};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('정산 요약',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      if (s.canManage)
                        IconButton(
                            tooltip: '정산표 공유',
                            onPressed: _share,
                            icon: const Icon(Icons.ios_share)),
                    ],
                  ),
                  Text('${_dot(s.from)} ~ ${_dot(s.to)}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text('미제출 1회 ${_wonLabel(s.fineAmount)}'
                      '${s.fineCap > 0 ? ' · 1인 상한 ${_wonLabel(s.fineCap)}' : ''}'
                      '${s.leaderExempt ? ' · 반장 제외' : ''}'),
                  Text('벌금 합계 ${_wonLabel(s.pool)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('완주자 ${s.winnerCount}명 · 1인 상금 ${_wonLabel(s.share)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: AppTheme.stamp)),
                  if (s.fineAmount == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('벌금이 0원으로 설정돼 있어요. 반장이 동호회 설정에서 바꿀 수 있어요.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!s.canManage)
            Text('정산 전체는 반장·부반장만 볼 수 있어요. 내 정산만 보여요.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ...s.lines.map((l) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: s.canManage && !l.exempt ? () => _addPayment(l) : null,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(l.member.displayName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      if (l.member.offline) _Tag('미설치', Colors.blueGrey),
                      if (l.winner) _Tag('완주', AppTheme.success),
                    ],
                  ),
                  subtitle: Text(l.exempt
                      ? '반장 — 정산 제외'
                      : l.winner
                          ? '상금 ${_wonLabel(l.prize)} · 지급 ${_wonLabel(l.prizePaid)}'
                          : '미제출 ${l.missed}회 · 벌금 ${_wonLabel(l.fine)} · 납부 ${_wonLabel(l.finePaid)}'),
                  trailing: l.exempt
                      ? null
                      : l.winner
                          ? Text(
                              l.prize - l.prizePaid > 0
                                  ? '지급할 ${_wonLabel(l.prize - l.prizePaid)}'
                                  : '지급 완료',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.stamp))
                          : Text(
                              l.fineBalance > 0
                                  ? '미납 ${_wonLabel(l.fineBalance)}'
                                  : '완납',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: l.fineBalance > 0
                                      ? cs.error
                                      : AppTheme.success)),
                ),
              )),
          if (s.canManage && s.payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('정산 장부',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ...s.payments.reversed.map((p) => ListTile(
                  dense: true,
                  title: Text(
                      '${names[p.memberId] ?? '(나간 회원)'} · ${p.kindLabel} ${_wonLabel(p.amount)}'),
                  subtitle: Text(
                      '${DateFormat('M/d HH:mm').format(p.createdAt)}${p.memo != null ? ' · ${p.memo}' : ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await CrewApi.deletePayment(widget.detail.crew.id, p.id);
                        await _load();
                      } on CrewApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ═══ 회원 ════════════════════════════════════════════════════════════

class _MembersTab extends StatelessWidget {
  final CrewDetail detail;
  final Future<void> Function(Future<void> Function(), {String? done}) run;
  final Future<bool> Function(String, String) confirm;
  const _MembersTab(
      {required this.detail, required this.run, required this.confirm});

  CrewRole get _myRole => detail.me.role;
  int get _crewId => detail.crew.id;

  Future<String?> _ask(BuildContext context, String title,
      {String? initial, String? hint}) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 20,
            decoration:
                InputDecoration(hintText: hint, border: const OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인')),
        ],
      ),
    );
    final v = c.text.trim();
    c.dispose();
    return ok == true && v.isNotEmpty ? v : null;
  }

  Future<void> _addOffline(BuildContext context) async {
    final name = await _ask(context, '앱 미설치 회원 추가', hint: '이름 (예: 김철수)');
    if (name == null || !context.mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: '과제 의무 시작일 (이 날부터 집계)',
      initialDate: now,
      firstDate: DateTime.parse(detail.crew.startDate),
      lastDate: now.add(const Duration(days: 365)),
    );
    await run(
        () => CrewApi.addOfflineMember(_crewId,
            name: name,
            joinedAt:
                picked == null ? null : DateFormat('yyyy-MM-dd').format(picked)),
        done: '$name 님을 추가했어요. 현황판에서 대신 체크할 수 있어요');
  }

  Future<void> _memberMenu(BuildContext context, CrewMember m) async {
    final leader = _myRole == CrewRole.leader;
    final sub = _myRole == CrewRole.subleader;
    final canEdit = leader || m.isMe || (sub && m.offline);
    final items = <(String, IconData, String)>[
      if (canEdit) ('rename', Icons.edit_outlined, '이름 바꾸기'),
      if (leader || (sub && m.offline))
        ('joined', Icons.event, '의무 시작일 변경 (현재 ${_dot(m.joinedAt)})'),
      if (leader && !m.isMe && !m.offline && m.role == CrewRole.member)
        ('sub', Icons.shield_outlined, '부반장으로 임명'),
      if (leader && !m.isMe && m.role == CrewRole.subleader)
        ('member', Icons.person_outline, '부반장 해제'),
      if (leader && !m.isMe && !m.offline)
        ('leader', Icons.military_tech_outlined, '반장 넘기기'),
      if (!m.isMe &&
          m.role != CrewRole.leader &&
          (leader || (sub && m.offline)))
        ('remove', Icons.person_remove_outlined, '동호회에서 내보내기'),
    ];
    if (items.isEmpty) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(m.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${m.role.label}${m.offline ? ' · 앱 미설치' : ''}${m.note != null ? ' · ${m.note}' : ''}'),
            ),
            const Divider(height: 1),
            ...items.map((i) => ListTile(
                  leading: Icon(i.$2),
                  title: Text(i.$3),
                  onTap: () => Navigator.pop(ctx, i.$1),
                )),
          ],
        ),
      ),
    );
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'rename':
        final name = await _ask(context, '이름 바꾸기', initial: m.displayName);
        if (name != null) {
          await run(() => CrewApi.updateMember(_crewId, m.id, {'displayName': name}));
        }
      case 'joined':
        final p = await showDatePicker(
          context: context,
          initialDate: DateTime.parse(m.joinedAt),
          firstDate: DateTime.parse(detail.crew.startDate)
              .subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (p != null) {
          await run(() => CrewApi.updateMember(_crewId, m.id,
              {'joinedAt': DateFormat('yyyy-MM-dd').format(p)}));
        }
      case 'sub':
        await run(() => CrewApi.updateMember(_crewId, m.id, {'role': 'subleader'}),
            done: '${m.displayName} 님을 부반장으로 임명했어요');
      case 'member':
        await run(() => CrewApi.updateMember(_crewId, m.id, {'role': 'member'}));
      case 'leader':
        if (await confirm('반장을 넘길까요?',
            '${m.displayName} 님이 반장이 되고, 나는 부반장이 돼요.')) {
          await run(() => CrewApi.updateMember(_crewId, m.id, {'role': 'leader'}),
              done: '반장을 넘겼어요');
        }
      case 'remove':
        if (await confirm('${m.displayName} 님을 내보낼까요?',
            '지난 제출 기록은 남지만 현황·통계에서 빠져요.')) {
          await run(() => CrewApi.removeMember(_crewId, m.id));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final invite = detail.crew.inviteCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (invite != null)
          Card(
            color: AppTheme.stamp.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('초대코드', style: TextStyle(fontSize: 12)),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(invite,
                            style: const TextStyle(
                                fontSize: 28,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.stamp)),
                      ),
                      IconButton(
                        tooltip: '복사',
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: invite));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('복사했어요')));
                        },
                      ),
                      IconButton(
                        tooltip: '공유',
                        icon: const Icon(Icons.ios_share),
                        onPressed: () => SharePlus.instance.share(ShareParams(
                            text: '[${detail.crew.name}] 동호회 초대\n'
                                '습관챌린지 앱 → 동호회 탭 → 초대코드 가입\n'
                                '초대코드: $invite\n'
                                '(동호회는 Pro 회원 전용이에요. Pro 키는 반장에게 받아 주세요)\n'
                                'https://play.google.com/store/apps/details?id=com.keywordream.keepup')),
                      ),
                    ],
                  ),
                  if (_myRole == CrewRole.leader)
                    TextButton(
                      onPressed: () async {
                        if (await confirm('초대코드를 새로 만들까요?',
                            '기존 코드로는 더 이상 가입할 수 없어요.')) {
                          await run(() async {
                            await CrewApi.regenerateInvite(_crewId);
                          });
                        }
                      },
                      child: const Text('코드 새로 만들기'),
                    ),
                ],
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text('회원 ${detail.members.length}명',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            if (_myRole.isManager)
              TextButton.icon(
                onPressed: () => _addOffline(context),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('미설치 회원 추가'),
              ),
          ],
        ),
        if (_myRole.isManager)
          Text('앱이 없는 회원도 추가하면, 현황판에서 대신 제출·인정을 체크하고 정산까지 관리할 수 있어요.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...detail.members.map((m) => ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _memberMenu(context, m),
              leading: CircleAvatar(
                backgroundImage:
                    m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
                backgroundColor: m.role.isManager
                    ? AppTheme.stamp.withValues(alpha: 0.2)
                    : cs.surfaceContainerHighest,
                child: m.avatarUrl == null
                    ? Text(m.displayName.isEmpty
                        ? '?'
                        : m.displayName.characters.first)
                    : null,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text('${m.displayName}${m.isMe ? ' (나)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (m.role != CrewRole.member)
                    _Tag(m.role.label, AppTheme.stamp),
                  if (m.offline) _Tag('미설치', Colors.blueGrey),
                ],
              ),
              subtitle: Text(
                  '${_dot(m.joinedAt)}부터${m.note != null ? ' · ${m.note}' : ''}'),
              trailing: const Icon(Icons.more_vert),
            )),
      ],
    );
  }
}

// ═══ 과제 ════════════════════════════════════════════════════════════

class _TasksTab extends StatelessWidget {
  final CrewDetail detail;
  final Future<void> Function(Future<void> Function(), {String? done}) run;
  final Future<bool> Function(String, String) confirm;
  final Future<void> Function() reload;
  const _TasksTab(
      {required this.detail,
      required this.run,
      required this.confirm,
      required this.reload});

  Future<void> _openForm(BuildContext context, [CrewTask? t]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => CrewTaskFormScreen(crew: detail.crew, initial: t)),
    );
    if (saved == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = detail.me.role;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (detail.crew.description?.isNotEmpty ?? false)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(detail.crew.description!),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text('공통 과제 ${detail.tasks.length}개',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            if (role.isManager)
              FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('과제 만들기'),
              ),
          ],
        ),
        Text('과제는 회원 모두의 앱에 루틴으로 들어가고, 도장을 찍으면 자동으로 제출돼요. '
            '마감 알람도 개인 루틴과 똑같이 울려요.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...detail.tasks.map((t) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(t.title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  '${t.kind.label} · ${t.scheduleLabel}',
                  t.isAssignment
                      ? '제출 양식: ${t.form.map((f) => f.type.label).join('·')}'
                      : '${t.verifyMethod.label}${t.verifyMethod == VerifyMethod.timer ? ' ${t.timerMinutes}분' : ''}'
                          '${t.requireNote ? ' · 소감 필수' : ''}',
                  '${_dot(t.startDate)} ~ ${_dot(t.endDate)}',
                  if (t.targetValue != null) '목표: ${t.targetValue}',
                  if (t.backupTitle != null) '백업: ${t.backupTitle}',
                  if (t.reason.isNotEmpty) '"${t.reason}"',
                ].join('\n')),
                isThreeLine: true,
                trailing: role.isManager
                    ? PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') await _openForm(context, t);
                          if (v == 'sessions' && context.mounted) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CrewSessionsScreen(
                                      crewId: detail.crew.id, task: t)),
                            );
                          }
                          if (v == 'archive' &&
                              await confirm('과제를 종료할까요?',
                                  '오늘부터 의무에서 빠지고, 지난 제출 기록과 통계는 남아요.')) {
                            await run(() => CrewApi.archiveTask(detail.crew.id, t.id),
                                done: '과제를 종료했어요');
                          }
                        },
                        itemBuilder: (_) => [
                          if (t.isAssignment)
                            const PopupMenuItem(
                                value: 'sessions', child: Text('회차별 과제 내용')),
                          const PopupMenuItem(value: 'edit', child: Text('수정')),
                          if (role == CrewRole.leader)
                            const PopupMenuItem(
                                value: 'archive', child: Text('종료')),
                        ],
                      )
                    : null,
              ),
            )),
      ],
    );
  }
}
