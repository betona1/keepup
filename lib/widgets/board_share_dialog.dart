import 'package:flutter/material.dart';

/// 게시판 업로드 전 제목·소감을 다듬는 다이얼로그.
/// 회고 카드·인증 직후 공유가 함께 쓴다. 확정하면 (제목, 소감), 취소하면 null.
Future<(String, String)?> promptBoardPost(
  BuildContext context, {
  required String title,
  required String body,
  String attachNote = '회고 카드 이미지가 함께 올라가요',
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) {
      final titleCtrl = TextEditingController(text: title);
      final bodyCtrl = TextEditingController(text: body);
      return AlertDialog(
        title: const Text('웹 게시판에 자랑하기'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bodyCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '소감',
                  hintText: '느낀 점을 남겨보세요',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.image_outlined,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(attachNote,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty ||
                  bodyCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                  ctx, (titleCtrl.text.trim(), bodyCtrl.text.trim()));
            },
            child: const Text('게시하기'),
          ),
        ],
      );
    },
  );
}
