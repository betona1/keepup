import 'package:flutter/material.dart';

import '../services/crew_api.dart';

/// 신고 사유 — 서버 crew_reports.reason 과 같다
const reportReasons = <String, String>{
  'abuse': '욕설·혐오 표현',
  'sexual': '음란·선정적인 내용',
  'harassment': '괴롭힘·따돌림',
  'spam': '스팸·광고',
  'privacy': '개인정보 노출',
  'other': '기타',
};

/// 동호회 게시글·댓글·제출물 신고 (Play UGC 정책) — 운영자(메인 관리자)가 확인 후 처리한다.
/// [targetType]: post | comment | submission
Future<void> showReportSheet(BuildContext context,
    {required int crewId,
    required String targetType,
    required int targetId}) async {
  String reason = 'abuse';
  final memo = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('신고하기',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('운영자가 확인한 뒤 삭제 등 조치해요. 신고한 사람은 상대에게 알려지지 않아요.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: reason,
                  onChanged: (v) => setS(() => reason = v ?? reason),
                  child: Column(
                    children: reportReasons.entries
                        .map((e) => RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: e.key,
                              title: Text(e.value),
                            ))
                        .toList(),
                  ),
                ),
                TextField(
                  controller: memo,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                      hintText: '자세한 내용 (선택)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('신고 보내기'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final memoText = memo.text.trim();
  memo.dispose();
  if (ok != true || !context.mounted) return;
  try {
    await CrewApi.report(crewId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        memo: memoText);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('신고를 접수했어요. 운영자가 확인할게요 🙏')));
    }
  } on CrewApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
