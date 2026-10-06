import 'dart:math';

import 'package:flutter/material.dart';

import '../models/crew.dart';

/// 과제 점검형 제출 양식 편집기 — 항목을 더하고, 순서를 바꾸고, 필수 여부를 정한다.
/// 과제 기본 양식과 회차별 양식이 함께 쓴다.
class CrewFormEditor extends StatefulWidget {
  final List<FormItem> initial;
  final ValueChanged<List<FormItem>> onChanged;
  const CrewFormEditor(
      {super.key, required this.initial, required this.onChanged});

  /// 새 과제의 추천 양식 — 요약 글 + 자료 첨부(선택)
  static List<FormItem> get starter => const [
        FormItem(id: 'body', type: FormItemType.text, label: '과제 내용', minChars: 1),
        FormItem(
            id: 'files',
            type: FormItemType.file,
            label: '자료 첨부',
            required: false,
            maxFiles: 3),
      ];

  @override
  State<CrewFormEditor> createState() => _CrewFormEditorState();
}

class _CrewFormEditorState extends State<CrewFormEditor> {
  late final List<FormItem> _items = [...widget.initial];

  static final _rand = Random();
  String _newId() =>
      'i${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(999)}';

  void _emit() {
    setState(() {});
    widget.onChanged(List.unmodifiable(_items));
  }

  static String _defaultLabel(FormItemType t) => switch (t) {
        FormItemType.text => '내용 (요약·감상)',
        FormItemType.question => '질문을 적어 주세요',
        FormItemType.photo => '인증 사진',
        FormItemType.file => '자료 첨부',
        FormItemType.audio => '녹음',
        FormItemType.link => '링크 (블로그·유튜브 등)',
        FormItemType.number => '수치',
      };

  static IconData _icon(FormItemType t) => switch (t) {
        FormItemType.text => Icons.notes,
        FormItemType.question => Icons.quiz_outlined,
        FormItemType.photo => Icons.photo_camera_outlined,
        FormItemType.file => Icons.attach_file,
        FormItemType.audio => Icons.mic_none,
        FormItemType.link => Icons.link,
        FormItemType.number => Icons.pin_outlined,
      };

  Future<void> _edit(int index) async {
    final edited = await showDialog<FormItem>(
      context: context,
      builder: (_) => _ItemDialog(item: _items[index]),
    );
    if (edited == null) return;
    _items[index] = edited;
    _emit();
  }

  Future<void> _add() async {
    final type = await showModalBottomSheet<FormItemType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('어떤 항목을 넣을까요?',
                    style: TextStyle(fontWeight: FontWeight.w800))),
            ...FormItemType.values.map((t) => ListTile(
                  leading: Icon(_icon(t)),
                  title: Text(t.label),
                  subtitle: Text(switch (t) {
                    FormItemType.text => '요약·감상·풀이를 글로 (최소 글자 수 지정 가능)',
                    FormItemType.question => '반장이 낸 질문에 답하기 (문항마다 하나씩)',
                    FormItemType.photo => '날짜 워터마크가 찍힌 인증 사진',
                    FormItemType.file => 'PDF·한글·워드·엑셀·이미지 등 자료',
                    FormItemType.audio => '발음·낭독 녹음 (운영진이 들어 보고 점검)',
                    FormItemType.link => '블로그·유튜브·드라이브 주소',
                    FormItemType.number => '쪽수·km·분 같은 숫자 (단위 지정)',
                  }),
                  onTap: () => Navigator.pop(ctx, t),
                )),
          ],
        ),
      ),
    );
    if (type == null) return;
    final item = FormItem(
      id: _newId(),
      type: type,
      label: _defaultLabel(type),
      minChars: type == FormItemType.text || type == FormItemType.question ? 1 : null,
      maxFiles: type.isFile ? 3 : null,
    );
    _items.add(item);
    _emit();
    await _edit(_items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('항목이 없어요. 아래에서 추가해 주세요.',
                style: TextStyle(color: cs.error)),
          ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            _items.insert(b, _items.removeAt(a));
            _emit();
          },
          children: [
            for (var i = 0; i < _items.length; i++)
              Card(
                key: ValueKey(_items[i].id),
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: () => _edit(i),
                  leading: ReorderableDragStartListener(
                      index: i, child: Icon(_icon(_items[i].type))),
                  title: Text(_items[i].label,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    _items[i].type.label,
                    _items[i].required ? '필수' : '선택',
                    if ((_items[i].minChars ?? 1) > 1) '${_items[i].minChars}자 이상',
                    if (_items[i].unit?.isNotEmpty ?? false) '단위 ${_items[i].unit}',
                    if (_items[i].type.isFile) '최대 ${_items[i].maxFiles ?? 3}개',
                  ].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      _items.removeAt(i);
                      _emit();
                    },
                  ),
                ),
              ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _items.length >= 12 ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('항목 추가'),
        ),
      ],
    );
  }
}

class _ItemDialog extends StatefulWidget {
  final FormItem item;
  const _ItemDialog({required this.item});

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _label = TextEditingController(text: widget.item.label);
  late final _min =
      TextEditingController(text: '${widget.item.minChars ?? 1}');
  late final _unit = TextEditingController(text: widget.item.unit ?? '');
  late bool _required = widget.item.required;
  late int _maxFiles = widget.item.maxFiles ?? 3;

  @override
  void dispose() {
    _label.dispose();
    _min.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item.type;
    final textual = t == FormItemType.text || t == FormItemType.question;
    return AlertDialog(
      title: Text('${t.label} 항목'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              maxLength: 200,
              maxLines: t == FormItemType.question ? 4 : 1,
              minLines: 1,
              decoration: InputDecoration(
                  labelText: t == FormItemType.question ? '질문' : '항목 이름',
                  border: const OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              title: const Text('필수 항목'),
            ),
            if (textual)
              TextField(
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '최소 글자 수', border: OutlineInputBorder()),
              ),
            if (t == FormItemType.number)
              TextField(
                controller: _unit,
                maxLength: 10,
                decoration: const InputDecoration(
                    labelText: '단위 (예: 쪽, km, 분)',
                    border: OutlineInputBorder()),
              ),
            if (t.isFile)
              Row(
                children: [
                  const Expanded(child: Text('최대 첨부 개수')),
                  IconButton(
                      onPressed: _maxFiles > 1
                          ? () => setState(() => _maxFiles--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$_maxFiles',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(
                      onPressed: _maxFiles < 5
                          ? () => setState(() => _maxFiles++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소')),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            Navigator.pop(
              context,
              FormItem(
                id: widget.item.id,
                type: t,
                label: label,
                required: _required,
                minChars: textual
                    ? (int.tryParse(_min.text.trim()) ?? 1).clamp(1, 5000)
                    : null,
                unit: t == FormItemType.number ? _unit.text.trim() : null,
                maxFiles: t.isFile ? _maxFiles : null,
              ),
            );
          },
          child: const Text('확인'),
        ),
      ],
    );
  }
}
