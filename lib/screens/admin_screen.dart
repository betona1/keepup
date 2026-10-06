import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/crew.dart';
import '../services/crew_api.dart';
import '../theme.dart';
import 'pro_screen.dart';

final _ymd = DateFormat('yyyy.MM.dd');

String _proLabel(AdminUserRow u) {
  if (u.admin) return '관리자 · 항상 Pro';
  if (!u.pro) {
    return u.expiresAt == null ? 'Pro 아님' : '${_ymd.format(u.expiresAt!)} 만료';
  }
  return u.expiresAt == null ? '평생' : '${_ymd.format(u.expiresAt!)}까지';
}

/// 메인 관리자 화면 (netkjy@gmail.com) — 현황 · Pro 키 · Pro 회원 · 동호회 전체
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('메인 관리자'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '현황'),
              Tab(text: 'Pro 키'),
              Tab(text: 'Pro 회원'),
              Tab(text: '동호회'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OverviewTab(), _KeysTab(), _MembersTab(), _CrewsTab()],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Widget _errorView(String msg, VoidCallback retry) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
            padding: const EdgeInsets.all(24),
            child: Text(msg, textAlign: TextAlign.center)),
        TextButton(onPressed: retry, child: const Text('다시 시도')),
      ]),
    );

// ═══ 현황 ════════════════════════════════════════════════════════════

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  AdminOverview? _o;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await CrewApi.adminOverview();
      if (mounted) {
        setState(() {
          _o = o;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null) {
      return _error != null
          ? _errorView(_error!, _load)
          : const Center(child: CircularProgressIndicator());
    }
    final tiles = [
      (Icons.people_alt_outlined, '전체 회원', '${o.users}명'),
      (Icons.workspace_premium_outlined, 'Pro 이용 중', '${o.proActive}명'),
      (Icons.key_outlined, 'Pro 키', '${o.keys}개 (사용 가능 ${o.keysAvailable})'),
      (Icons.groups_outlined, '동호회', '${o.crews}개'),
      (Icons.person_pin_outlined, '동호회 회원', '${o.crewMembers}명'),
      (Icons.assignment_outlined, '진행 중 과제', '${o.activeTasks}개'),
      (Icons.task_alt, '최근 7일 제출', '${o.submissions7d}건'),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: tiles
            .map((t) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(t.$1, color: AppTheme.stamp),
                        Text(t.$3,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                        Text(t.$2, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ═══ Pro 키 ══════════════════════════════════════════════════════════

class _KeysTab extends StatefulWidget {
  const _KeysTab();

  @override
  State<_KeysTab> createState() => _KeysTabState();
}

class _KeysTabState extends State<_KeysTab> {
  List<ProKey>? _keys;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final k = await CrewApi.listKeys();
      if (mounted) {
        setState(() {
          _keys = k;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _shareText(List<String> codes) =>
      '[습관챌린지 Pro 키]\n${codes.join('\n')}\n\n'
      '앱 → 동호회 탭 → Pro 키 등록에 입력하세요.';

  Future<void> _issue() async {
    final result = await showDialog<List<String>>(
        context: context, builder: (_) => const IssueKeyDialog());
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('키 ${result.length}개 발행 완료'),
        content: SelectableText(result.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.join('\n')));
              Navigator.pop(ctx);
              _snack(context, '복사했어요');
            },
            child: const Text('복사'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              SharePlus.instance.share(ShareParams(text: _shareText(result)));
            },
            child: const Text('공유'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(ProKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('키를 폐기할까요?'),
        content: Text('${k.code}\n더 이상 등록할 수 없게 돼요. 이미 등록한 회원의 Pro는 유지돼요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('폐기')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrewApi.revokeKey(k.id);
      await _load();
    } on CrewApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-issue',
        onPressed: _issue,
        icon: const Icon(Icons.add),
        label: const Text('키 발행'),
      ),
      body: keys == null
          ? (_error != null
              ? _errorView(_error!, _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (keys.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('아직 발행한 키가 없어요.\n오른쪽 아래 [키 발행]으로 만들어 보세요.',
                          textAlign: TextAlign.center),
                    ),
                  ...keys.map((k) => ProKeyTile(
                        k: k,
                        onShare: () => SharePlus.instance
                            .share(ShareParams(text: _shareText([k.code]))),
                        onRevoke: () => _revoke(k),
                      )),
                ],
              ),
            ),
    );
  }
}

// ═══ Pro 회원 ════════════════════════════════════════════════════════

class _MembersTab extends StatefulWidget {
  const _MembersTab();

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  List<AdminUserRow>? _members;
  List<AdminUserRow>? _search;
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await CrewApi.adminProMembers();
      if (mounted) {
        setState(() {
          _members = m;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _find() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _search = null);
      return;
    }
    try {
      final r = await CrewApi.adminSearchUsers(q);
      if (mounted) setState(() => _search = r);
    } on CrewApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  /// 회원 한 명 관리 — 기간 지급·연장 / 평생 / 해지
  Future<void> _manage(AdminUserRow u) async {
    if (u.admin) {
      _snack(context, '관리자 계정은 항상 Pro예요');
      return;
    }
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(u.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${u.email ?? '이메일 없음'} · ${u.providerLabel}\n현재: ${_proLabel(u)}'),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            for (final d in const [30, 90, 365])
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text('${d == 365 ? '1년' : '$d일'} 지급·연장'),
                subtitle: const Text('남은 기간이 있으면 그 뒤로 더해져요'),
                onTap: () => Navigator.pop(ctx, '$d'),
              ),
            ListTile(
              leading: const Icon(Icons.all_inclusive, color: AppTheme.stamp),
              title: const Text('평생 Pro로'),
              onTap: () => Navigator.pop(ctx, 'life'),
            ),
            if (u.pro)
              ListTile(
                leading:
                    Icon(Icons.block, color: Theme.of(ctx).colorScheme.error),
                title: const Text('Pro 해지 (지금 만료)'),
                subtitle: const Text('동호회 제출이 막혀요. 기록은 그대로 남아요'),
                onTap: () => Navigator.pop(ctx, 'revoke'),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    try {
      if (v == 'revoke') {
        await CrewApi.adminRevokePro(u.userId);
      } else {
        await CrewApi.adminGrantPro(u.userId,
            days: v == 'life' ? null : int.parse(v));
      }
      if (!mounted) return;
      _snack(
          context,
          v == 'revoke'
              ? '${u.name} 님 Pro를 해지했어요'
              : '${u.name} 님 Pro를 처리했어요 ✅');
      await _load();
      if (_search != null) await _find();
    } on CrewApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Widget _row(AdminUserRow u) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: () => _manage(u),
      leading: CircleAvatar(
        backgroundColor: u.pro
            ? AppTheme.stamp.withValues(alpha: 0.18)
            : cs.surfaceContainerHighest,
        child: Icon(u.admin ? Icons.shield : Icons.workspace_premium_outlined,
            color: u.pro ? AppTheme.stamp : cs.onSurfaceVariant),
      ),
      title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${u.email ?? '이메일 없음'} · ${u.providerLabel}'
          '${u.keysUsed > 0 ? ' · 키 ${u.keysUsed}회' : ''}'),
      trailing: Text(_proLabel(u),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: u.pro ? AppTheme.success : cs.error)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final search = _search;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            decoration: InputDecoration(
              hintText: '회원 찾기 (이름·이메일) — 키 없이 바로 Pro 지급',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward), onPressed: _find),
            ),
          ),
          if (search != null) ...[
            const SizedBox(height: 8),
            Text('검색 결과 ${search.length}명',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (search.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(12), child: Text('찾는 회원이 없어요')),
            ...search.map(_row),
            const Divider(height: 24),
          ],
          const SizedBox(height: 8),
          if (members == null)
            _error != null
                ? _errorView(_error!, _load)
                : const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
          else ...[
            Text(
                'Pro 회원 ${members.where((m) => m.pro).length}명'
                '${members.any((m) => !m.pro) ? ' (만료·해지 ${members.where((m) => !m.pro).length}명 포함 목록)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (members.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24), child: Text('아직 Pro 회원이 없어요')),
            ...members.map(_row),
          ],
        ],
      ),
    );
  }
}

// ═══ 동호회 전체 ═════════════════════════════════════════════════════

class _CrewsTab extends StatefulWidget {
  const _CrewsTab();

  @override
  State<_CrewsTab> createState() => _CrewsTabState();
}

class _CrewsTabState extends State<_CrewsTab> {
  List<AdminCrewRow>? _crews;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await CrewApi.adminCrews();
      if (mounted) {
        setState(() {
          _crews = c;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggle(AdminCrewRow c) async {
    final hide = !c.deleted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hide ? '「${c.name}」을 숨길까요?' : '「${c.name}」을 되살릴까요?'),
        content: Text(hide
            ? '운영 정책 위반 등으로 숨기면 회원 모두에게 보이지 않고 과제도 멈춰요. 기록은 남아서 되살릴 수 있어요.'
            : '회원들에게 다시 보이고 과제가 이어져요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(hide ? '숨기기' : '되살리기')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrewApi.adminSetCrewHidden(c.id, hide);
      await _load();
    } on CrewApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final crews = _crews;
    if (crews == null) {
      return _error != null
          ? _errorView(_error!, _load)
          : const Center(child: CircularProgressIndicator());
    }
    final live = crews.where((c) => !c.deleted).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text('운영 중 $live개 · 해체·숨김 ${crews.length - live}개',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('메뉴(⋮)로 숨기기·되살리기. 동호회 안 내용은 개인정보 보호를 위해 관리자도 보지 않아요.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (crews.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24), child: Text('아직 동호회가 없어요')),
          ...crews.map((c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Row(children: [
                    Flexible(
                      child: Text(c.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              decoration: c.deleted
                                  ? TextDecoration.lineThrough
                                  : null)),
                    ),
                    if (c.deleted)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('해체·숨김',
                            style: TextStyle(
                                fontSize: 10, color: cs.onErrorContainer)),
                      ),
                  ]),
                  subtitle: Text([
                    '반장 ${c.leader ?? '-'} · 회원 ${c.memberCount}명 · 과제 ${c.taskCount}개',
                    '${c.startDate.replaceAll('-', '.')} ~ ${c.endDate.replaceAll('-', '.')}',
                    c.lastSubmissionAt == null
                        ? '아직 제출 없음'
                        : '최근 제출 ${DateFormat('M/d HH:mm').format(c.lastSubmissionAt!)}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) => _toggle(c),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'toggle',
                          child: Text(c.deleted ? '되살리기' : '숨기기')),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
