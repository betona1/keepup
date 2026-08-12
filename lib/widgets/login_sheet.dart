import 'package:flutter/material.dart';

import '../services/account_service.dart';

/// 웹 계정 로그인을 보장한다 — 이미 로그인돼 있으면 바로 true,
/// 아니면 로그인 방법 선택 시트(기기 구글계정 원탭 / 브라우저)를 띄운다.
/// 홈 프로필과 게시판 공유가 함께 쓰는 공용 진입점.
Future<bool> ensureWebLogin(BuildContext context,
    {String reason = '성과 게시판에 올리려면 로그인이 필요해요.'}) async {
  final me = await AccountService.instance.me();
  if (me != null) return true;
  if (!context.mounted) return false;

  final cs = Theme.of(context).colorScheme;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('로그인',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(reason,
                  style:
                      TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ),
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant),
              ),
              child: const Text('G',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF4285F4))),
            ),
            title: const Text('Google 계정으로 로그인'),
            subtitle: const Text('이 기기 계정으로 바로 · 비밀번호 불필요'),
            onTap: () => Navigator.pop(ctx, 'google'),
          ),
          ListTile(
            leading: Icon(Icons.public, color: cs.primary),
            title: const Text('카카오 · 네이버 · 이메일'),
            subtitle: const Text('브라우저로 로그인'),
            onTap: () => Navigator.pop(ctx, 'web'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return false;

  final ok = choice == 'google'
      ? await AccountService.instance.loginWithGoogleNative()
      : await AccountService.instance.login();
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 취소됐거나 실패했어요. 다시 시도해 주세요.')),
    );
  }
  return ok;
}
