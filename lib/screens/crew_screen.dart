import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models/crew.dart';
import '../services/account_service.dart';
import '../services/crew_api.dart';
import '../services/crew_sync_service.dart';
import '../theme.dart';
import '../widgets/login_sheet.dart';
import 'crew_detail_screen.dart';
import 'pro_screen.dart';

/// 하단 '동호회' 탭 — 내 동호회 목록 · 만들기 · 초대코드로 가입 (Pro 기능)
class CrewBody extends StatefulWidget {
  final AppState state;
  const CrewBody({super.key, required this.state});

  @override
  State<CrewBody> createState() => CrewBodyState();
}

class CrewBodyState extends State<CrewBody> {
  bool _loading = true;
  bool _loggedIn = false;
  String? _error;
  ProStatus _pro = ProStatus.none;
  List<CrewSummary> _crews = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final me = await AccountService.instance.me(refresh: true);
    if (me == null) {
      if (mounted) {
        setState(() {
          _loggedIn = false;
          _loading = false;
        });
      }
      return;
    }
    try {
      final (pro, crews) = await CrewApi.myCrews();
      // 동호회 목록을 볼 때 과제도 함께 개인 루틴에 맞춰 둔다
      CrewSyncService.instance.syncTasks(force: true).catchError((_) {});
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _pro = pro;
        _crews = crews;
        _loading = false;
      });
    } on CrewApiException catch (e) {
      if (mounted) {
        setState(() {
          _loggedIn = true;
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openPro() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ProScreen()));
    await refresh();
  }

  Future<bool> _requirePro() async {
    if (_pro.pro) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pro가 필요해요'),
        content: const Text('동호회는 반장·회원 모두 Pro 회원만 이용할 수 있어요.\n'
            '받은 Pro 키를 먼저 등록해 주세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('닫기')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pro 키 등록')),
        ],
      ),
    );
    if (go == true) await _openPro();
    return false;
  }

  Future<void> _create() async {
    if (!await _requirePro() || !mounted) return;
    final body = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const CrewSettingsDialog());
    if (body == null) return;
    try {
      final id = await CrewApi.createCrew(body);
      await refresh();
      if (!mounted) return;
      _snack('동호회를 만들었어요 🎉 과제를 추가하고 초대코드를 공유하세요');
      _openCrew(id);
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _join() async {
    if (!await _requirePro() || !mounted) return;
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('초대코드로 가입'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: '초대코드 (6자리)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              maxLength: 20,
              decoration: const InputDecoration(
                  labelText: '동호회에서 쓸 이름 (비우면 계정 이름)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('가입')),
        ],
      ),
    );
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (ok != true || code.isEmpty) return;
    try {
      final id = await CrewApi.joinCrew(code, displayName: name);
      await CrewSyncService.instance.syncTasks(force: true);
      await refresh();
      if (!mounted) return;
      _snack('가입했어요! 동호회 과제가 내 루틴에 들어왔어요 ✅');
      _openCrew(id);
    } on CrewApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _openCrew(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CrewDetailScreen(crewId: id, state: widget.state)),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading && _crews.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_loggedIn) {
      return _CenterMessage(
        icon: Icons.groups_rounded,
        title: '동호회로 함께 습관 지키기',
        body: '반장이 낸 공통 과제를 함께 인증하고,\n누가 제출했는지 현황판으로 확인해요.\n\n'
            '동호회는 계정 로그인 후 이용할 수 있어요.',
        action: FilledButton.icon(
          onPressed: () async {
            if (await ensureWebLogin(context,
                reason: '동호회를 이용하려면 로그인이 필요해요.')) {
              await refresh();
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('로그인'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _ProBanner(pro: _pro, onTap: _openPro),
          const SizedBox(height: 12),
          if (_error != null)
            Card(
              color: cs.errorContainer,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: cs.onErrorContainer),
                title: Text(_error!,
                    style: TextStyle(color: cs.onErrorContainer)),
                trailing: TextButton(
                    onPressed: refresh, child: const Text('다시 시도')),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('동호회 만들기'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _join,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('초대코드 가입'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('내 동호회 ${_crews.length}',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (_crews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                '아직 참여한 동호회가 없어요.\n동호회를 만들거나 초대코드로 가입해 보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ..._crews.map((c) => _CrewCard(crew: c, onTap: () => _openCrew(c.id))),
        ],
      ),
    );
  }
}

class _ProBanner extends StatelessWidget {
  final ProStatus pro;
  final VoidCallback onTap;
  const _ProBanner({required this.pro, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = pro.admin
        ? 'Pro · 관리자 (키 발행)'
        : pro.pro
            ? (pro.lifetime
                ? 'Pro 이용 중 · 평생'
                : 'Pro 이용 중 · ${DateFormat('yyyy.MM.dd').format(pro.expiresAt!)}까지')
            : 'Pro 키 등록하고 동호회 시작하기';
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: pro.pro
                ? const [AppTheme.stamp, AppTheme.seed]
                : [Colors.blueGrey.shade400, Colors.blueGrey.shade600],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                    pro.pro
                        ? Icons.workspace_premium_rounded
                        : Icons.key_rounded,
                    color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewCard extends StatelessWidget {
  final CrewSummary crew;
  final VoidCallback onTap;
  const _CrewCard({required this.crew, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.stamp.withValues(alpha: 0.15),
          child: const Icon(Icons.groups_rounded, color: AppTheme.stamp),
        ),
        title: Text(crew.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${crew.startDate.replaceAll('-', '.')} ~ ${crew.endDate.replaceAll('-', '.')}'
            ' · ${crew.memberCount}명'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: crew.myRole.isManager
                ? AppTheme.stamp
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(crew.myRole.label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: crew.myRole.isManager ? Colors.white : null)),
        ),
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget action;
  const _CenterMessage(
      {required this.icon,
      required this.title,
      required this.body,
      required this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: AppTheme.stamp),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      );
}

/// 동호회 만들기 / 설정 변경 — 반환: 서버로 보낼 본문
class CrewSettingsDialog extends StatefulWidget {
  final CrewInfo? initial;
  const CrewSettingsDialog({super.key, this.initial});

  @override
  State<CrewSettingsDialog> createState() => _CrewSettingsDialogState();
}

class _CrewSettingsDialogState extends State<CrewSettingsDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _desc = TextEditingController(text: widget.initial?.description);
  late final _fine =
      TextEditingController(text: '${widget.initial?.fineAmount ?? 0}');
  late final _cap =
      TextEditingController(text: '${widget.initial?.fineCap ?? 49000}');
  late DateTime _start;
  late DateTime _end;
  late bool _leaderExempt = widget.initial?.leaderExempt ?? true;
  final _fmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _start = widget.initial == null
        ? today
        : DateTime.parse(widget.initial!.startDate);
    _end = widget.initial == null
        ? today.add(const Duration(days: 62)) // 기본 9주(63일) 시즌
        : DateTime.parse(widget.initial!.endDate);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _fine.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked.isBefore(_start) ? _start : picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '동호회 만들기' : '동호회 설정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(
                  labelText: '동호회 이름', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _desc,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                  labelText: '소개·규칙 (선택)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('시작 ${_fmt.format(_start)}')),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('종료 ${_fmt.format(_end)}')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fine,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '미제출 1회 벌금(원)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cap,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '1인 상한(원)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _leaderExempt,
              onChanged: (v) => setState(() => _leaderExempt = v),
              title: const Text('반장은 벌금·상금 정산에서 제외'),
            ),
            const Text('벌금은 기록만 해요. 실제 송금은 동호회에서 직접 해 주세요.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'name': name,
              'description': _desc.text.trim(),
              'startDate': _fmt.format(_start),
              'endDate': _fmt.format(_end),
              'fineAmount': int.tryParse(_fine.text.trim()) ?? 0,
              'fineCap': int.tryParse(_cap.text.trim()) ?? 0,
              'leaderExempt': _leaderExempt,
            });
          },
          child: Text(widget.initial == null ? '만들기' : '저장'),
        ),
      ],
    );
  }
}
