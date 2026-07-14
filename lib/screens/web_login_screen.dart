import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/account_service.dart';

/// keywordream.com 간편로그인(카카오/구글/네이버/이메일)을 웹뷰로 진행하고,
/// 완료되면 /api/auth/apptoken 에서 앱용 장기 토큰을 읽어 저장한다.
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  static const _tokenUrl = 'https://keywordream.com/api/auth/apptoken';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          if (mounted) setState(() => _loading = false);
          if (_done || !url.startsWith(_tokenUrl)) return;
          _done = true;
          try {
            // JSON 응답 페이지의 본문에서 토큰 추출
            final raw = await _controller
                .runJavaScriptReturningResult('document.body.innerText');
            var text = raw.toString();
            // 플랫폼에 따라 문자열이 따옴표로 감싸져 올 수 있다
            if (text.startsWith('"')) {
              text = jsonDecode(text) as String;
            }
            final body = jsonDecode(text);
            final token = body?['data']?['token'] as String?;
            if (token != null && token.isNotEmpty) {
              await AccountService.instance.saveToken(token);
              if (mounted) Navigator.pop(context, true);
              return;
            }
          } catch (_) {/* 아래 공통 실패 처리 */}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('로그인 처리에 실패했어요. 다시 시도해 주세요.')),
            );
            Navigator.pop(context, false);
          }
        },
      ))
      ..loadRequest(Uri.parse(
          'https://keywordream.com/login?next=${Uri.encodeComponent(_tokenUrl)}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('keywordream 로그인'),
        titleTextStyle: TextStyle(
          fontFamily: 'NanumGothic',
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
