import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/crew.dart';
import '../models/routine.dart';
import '../services/crew_api.dart';
import '../theme.dart';
import '../widgets/crew_form_editor.dart';

/// 회차별 과제 내용 — '매주 목·일' 과제라도 회차마다 안내와 제출 양식을 다르게 낸다.
class CrewSessionsScreen extends StatefulWidget {
  final int crewId;
  final CrewTask task;
  const CrewSessionsScreen({super.key, required this.crewId, required this.task});

  @override
  State<CrewSessionsScreen> createState() => _CrewSessionsScreenState();
}

class _CrewSessionsScreenState extends State<CrewSessionsScreen> {
  List<CrewSession>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await CrewApi.sessions(widget.crewId, widget.task.id);
      if (mounted) {
        setState(() {
          _sessions = s;
          _error = null;
        });
      }
    } on CrewApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(CrewSession s) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _SessionEditScreen(
            crewId: widget.crewId, task: widget.task, session: s),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _sessions;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('${widget.task.title} · 회차별 내용')),
      body: list == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Text(
                      '${widget.task.scheduleLabel}. 회차를 눌러 이번 회차 안내와 제출 양식을 정하세요. '
                      '정하지 않은 회차는 과제 기본 양식을 써요.',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('남은 회차가 없어요 (기간 종료)'),
                    ),
                  ...list.map((s) {
                    final d = DateTime.parse(s.dateKey);
                    final past = s.dateKey.compareTo(today) < 0;
                    final set = s.title != null || s.guide != null || s.customForm;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _open(s),
                        leading: CircleAvatar(
                          backgroundColor: set
                              ? AppTheme.stamp
                              : cs.surfaceContainerHighest,
                          child: Text('${d.month}/${d.day}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: set ? Colors.white : null)),
                        ),
                        title: Text(
                            s.title ??
                                '${d.month}/${d.day}(${weekdayNames[d.weekday - 1]}) 회차',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: past ? cs.onSurfaceVariant : null)),
                        subtitle: Text([
                          if (s.deadline != null)
                            '${DateFormat('M/d HH:mm').format(s.deadline!)} 마감',
                          s.customForm ? '회차 전용 양식 ${s.form.length}항목' : '기본 양식',
                          if (s.guide?.isNotEmpty ?? false) '안내 있음',
                          if (past) '지난 회차',
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _SessionEditScreen extends StatefulWidget {
  final int crewId;
  final CrewTask task;
  final CrewSession session;
  const _SessionEditScreen(
      {required this.crewId, required this.task, required this.session});

  @override
  State<_SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends State<_SessionEditScreen> {
  late final _title = TextEditingController(text: widget.session.title);
  late final _guide = TextEditingController(text: widget.session.guide);
  late bool _custom = widget.session.customForm;
  late List<FormItem> _form = widget.session.customForm
      ? widget.session.form
      : (widget.task.form.isEmpty ? CrewFormEditor.starter : widget.task.form);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _guide.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_custom && _form.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('양식 항목을 하나 이상 넣어 주세요')));
      return;
    }
    setState(() => _saving = true);
    try {
      await CrewApi.saveSession(
          widget.crewId, widget.task.id, widget.session.dateKey,
          title: _title.text.trim(),
          guide: _guide.text.trim(),
          form: _custom ? _form : null);
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
    final d = DateTime.parse(widget.session.dateKey);
    return Scaffold(
      appBar: AppBar(
          title: Text('${d.month}/${d.day}(${weekdayNames[d.weekday - 1]}) 회차')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(
                labelText: '이번 회차 제목 (예: 3장 읽고 요약)',
                border: OutlineInputBorder()),
          ),
          TextField(
            controller: _guide,
            maxLength: 5000,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
                labelText: '이번 회차 안내 (범위·준비물·주의할 점)',
                border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _custom,
            onChanged: (v) => setState(() => _custom = v),
            title: const Text('이번 회차만 제출 양식 바꾸기'),
            subtitle: Text(_custom
                ? '아래 양식으로 제출받아요'
                : '과제 기본 양식(${widget.task.form.length}항목)을 써요'),
          ),
          if (_custom)
            CrewFormEditor(initial: _form, onChanged: (f) => _form = f),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ],
      ),
    );
  }
}
