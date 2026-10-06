import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/crew.dart';
import '../services/crew_api.dart';
import '../theme.dart';
import 'admin_screen.dart';

/// Pro 키 등록 + (관리자) Pro 키 발행·관리.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  ProStatus? _status;
  String? _error;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await CrewApi.proStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
      });
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final s = await CrewApi.redeem(code);
      if (!mounted) return;
      setState(() => _status = s);
      _code.clear();
      _snack('Pro가 활성화됐어요 🎉 이제 동호회를 만들거나 가입할 수 있어요');
    } on CrewApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Pro')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!,
                      style: TextStyle(color: cs.onErrorContainer)),
                ),
              ),
            _StatusCard(status: s),
            const SizedBox(height: 16),
            const Text('Pro로 할 수 있는 것',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            const _Feature(
                Icons.groups_rounded, '동호회 만들기·가입', '반장·부반장을 정하고 함께 습관을 지켜요'),
            const _Feature(Icons.assignment_turned_in_outlined, '공통 과제',
                '반장이 만든 과제가 내 루틴으로 들어오고, 도장을 찍으면 자동 제출'),
            const _Feature(
                Icons.fact_check_outlined, '제출 현황판', '마감까지 누가 냈고 누가 아직인지 한눈에'),
            const _Feature(Icons.insights_outlined, '통계·정산',
                '미제출 집계, 벌금·상금 정산, 앱 미설치 회원까지 관리'),
            const SizedBox(height: 20),
            if (s != null && !s.admin) ...[
              Text(s.pro ? 'Pro 키 추가 등록 (기간 연장)' : 'Pro 키 등록',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'LC-XXXX-XXXX-XXXX',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key_rounded),
                ),
                onSubmitted: (_) => _redeem(),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy ? null : _redeem,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: Text(_busy ? '확인 중…' : '등록하기'),
              ),
              const SizedBox(height: 8),
              Text('키는 동호회 반장이나 운영자에게 받을 수 있어요.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
            if (s?.mainAdmin == true)
              FilledButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminScreen())),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('관리자 화면 (키 발행·Pro 회원·동호회 전체)'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              )
            else if (s?.admin == true)
              Text('관리자 계정이지만 Pro 키 발행은 메인 관리자만 할 수 있어요.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ProStatus? status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    final pro = s?.pro ?? false;
    final String sub;
    if (s == null) {
      sub = '확인 중…';
    } else if (s.admin) {
      sub = '관리자 계정 — 항상 Pro';
    } else if (s.pro) {
      sub = s.lifetime
          ? '평생 이용'
          : '${DateFormat('yyyy.MM.dd').format(s.expiresAt!)}까지';
    } else if (s.expiresAt != null) {
      sub = '${DateFormat('yyyy.MM.dd').format(s.expiresAt!)}에 만료됐어요';
    } else {
      sub = '아직 Pro가 아니에요';
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: pro
              ? const [AppTheme.stamp, AppTheme.seed]
              : [Colors.blueGrey.shade400, Colors.blueGrey.shade600],
        ),
      ),
      child: Row(
        children: [
          Icon(pro ? Icons.workspace_premium_rounded : Icons.lock_outline,
              color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pro ? 'Pro 이용 중' : '무료 이용 중',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _Feature(this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppTheme.stamp),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(desc),
      );
}

class ProKeyTile extends StatelessWidget {
  final ProKey k;
  final VoidCallback onShare;
  final VoidCallback onRevoke;
  const ProKeyTile(
      {super.key,
      required this.k,
      required this.onShare,
      required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final usedUp = k.usedCount >= k.maxUses;
    return Card(
      child: ListTile(
        title: SelectableText(k.code,
            style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                decoration: k.revoked ? TextDecoration.lineThrough : null)),
        subtitle: Text(
          '${k.durationLabel} · 사용 ${k.usedCount}/${k.maxUses}'
          '${k.revoked ? ' · 폐기됨' : usedUp ? ' · 소진' : ''}'
          '${k.note != null ? '\n${k.note}' : ''}',
          style: TextStyle(color: k.revoked ? cs.error : null),
        ),
        isThreeLine: k.note != null,
        trailing: k.revoked
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'copy') {
                    Clipboard.setData(ClipboardData(text: k.code));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('복사했어요')));
                  }
                  if (v == 'share') onShare();
                  if (v == 'revoke') onRevoke();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('복사')),
                  PopupMenuItem(value: 'share', child: Text('공유')),
                  PopupMenuItem(value: 'revoke', child: Text('폐기')),
                ],
              ),
      ),
    );
  }
}

/// 키 발행 옵션 — 기간 / 1개당 사용 인원 / 개수 / 메모
class IssueKeyDialog extends StatefulWidget {
  const IssueKeyDialog({super.key});

  @override
  State<IssueKeyDialog> createState() => _IssueKeyDialogState();
}

class _IssueKeyDialogState extends State<IssueKeyDialog> {
  int? _days = 365;
  int _maxUses = 1;
  int _count = 1;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _durations = <int?, String>{
    30: '30일',
    90: '90일',
    365: '1년',
    null: '평생',
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await CrewApi.issueKeys(
          count: _count,
          durationDays: _days,
          maxUses: _maxUses,
          note: _note.text.trim());
      if (mounted) Navigator.pop(context, codes);
    } on CrewApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _stepper(String label, int value, int min, int max,
          ValueChanged<int> onChanged) =>
      Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(
              width: 36,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pro 키 발행'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이용 기간'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: _durations.entries
                  .map((e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _days == e.key,
                        onSelected: (_) => setState(() => _days = e.key),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            _stepper('키 1개당 사용 인원', _maxUses, 1, 100,
                (v) => setState(() => _maxUses = v)),
            _stepper('발행 개수', _count, 1, 20, (v) => setState(() => _count = v)),
            Text(
              _maxUses > 1 ? '동호회 단위 배포: 키 1개를 $_maxUses명이 함께 써요' : '1인용 키',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLength: 100,
              decoration: const InputDecoration(
                  labelText: '메모 (예: 독서동호회 10명용)',
                  border: OutlineInputBorder()),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '발행 중…' : '발행')),
      ],
    );
  }
}
