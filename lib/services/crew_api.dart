import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/crew.dart';
import 'account_service.dart';

/// 과제 점검형 제출 첨부 — 양식 항목 하나에 여러 개
class UploadFile {
  final String itemId;
  final String name;
  final Uint8List bytes;
  final String mime;
  const UploadFile(
      {required this.itemId,
      required this.name,
      required this.bytes,
      required this.mime});
}

/// Pro·동호회 API 호출 실패 — [message]는 화면에 그대로 띄울 수 있는 한국어 문장.
class CrewApiException implements Exception {
  final String code;
  final String message;
  final int status;
  const CrewApiException(this.code, this.message, this.status);

  /// 네트워크 문제(재시도하면 될 수도 있음)인지
  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

/// log.keywordream.com 의 Pro·동호회 API.
///
/// 네이티브는 저장된 세션 토큰을 Cookie 헤더로, 웹앱(PWA)은 같은 오리진이라
/// 상대 경로로 부르면 세션 쿠키가 자동으로 붙는다 (CloudSyncService와 같은 방식).
class CrewApi {
  static const base = 'https://log.keywordream.com';

  static Uri _uri(String path) => Uri.parse(kIsWeb ? path : '$base$path');

  /// 동호회 사진 주소 (서버가 주는 '/api/crews/..' 상대 경로를 앱에서 열 수 있게)
  static String mediaUrl(String path) => kIsWeb ? path : '$base$path';

  /// 사진 요청에 붙일 헤더 (동호회 회원만 볼 수 있는 비공개 사진)
  static Future<Map<String, String>> imageHeaders() async {
    if (kIsWeb) return const {};
    final token = await AccountService.instance.sessionToken();
    return token == null ? const {} : {'Cookie': 'session=$token'};
  }

  static Future<Map<String, String>> _headers({bool json = false}) async {
    final h = <String, String>{if (json) 'Content-Type': 'application/json'};
    if (!kIsWeb) {
      final token = await AccountService.instance.sessionToken();
      if (token == null) {
        throw const CrewApiException('unauthorized', '로그인이 필요해요', 401);
      }
      h['Cookie'] = 'session=$token';
    }
    return h;
  }

  static const _messages = {
    'unauthorized': '로그인이 필요해요 (세션이 만료됐을 수 있어요)',
    'forbidden': '권한이 없어요',
    'not_found': '찾을 수 없어요 (동호회에서 나갔거나 삭제됐을 수 있어요)',
    'task_not_found': '과제가 종료됐거나 삭제됐어요',
    'invalid_input': '입력값을 확인해 주세요',
    'invalid_key': '올바른 Pro 키가 아니에요',
    'key_used_up': '이미 사용 횟수가 다 찬 키예요',
    'key_already_used_by_you': '이미 등록한 키예요',
    'pro_required': 'Pro 회원만 이용할 수 있어요. Pro 키를 먼저 등록해 주세요',
    'invalid_code': '초대코드를 다시 확인해 주세요',
    'crew_full': '동호회 인원이 가득 찼어요 (최대 100명)',
    'leader_cannot_leave': '반장은 다른 회원에게 반장을 넘긴 뒤에 나갈 수 있어요',
    'offline_member_role': '앱 미설치 회원은 운영진이 될 수 없어요',
    'not_duty_day': '이 날은 과제 의무일이 아니에요',
    'deadline_passed': '마감이 지나 동호회에 제출할 수 없어요. 반장·부반장에게 인정을 요청하세요',
    'not_open_yet': '아직 제출할 수 없는 날이에요',
    'window_not_open': '아직 인증 시간대가 아니에요',
    'before_join': '동호회 가입 전 날짜라 제출할 수 없어요',
    'note_required': '이 과제는 소감 작성이 필수예요',
    'future_date': '미래 날짜는 체크할 수 없어요',
    'image_too_large': '사진이 너무 커요 (5MB 제한)',
    'unsupported_image_type': '지원하지 않는 사진 형식이에요',
    'unsupported_audio_type': '지원하지 않는 녹음 형식이에요',
    'file_too_large': '파일이 너무 커요 (사진 5MB · 자료 20MB · 합계 50MB 제한)',
    'invalid_form': '제출 양식을 확인해 주세요 (항목 이름이 비어 있거나 중복)',
    'kind_change': '과제 유형(인증형·점검형)은 바꿀 수 없어요. 새 과제로 만들어 주세요',
    'not_assignment': '과제 점검형에서만 회차 내용을 정할 수 있어요',
  };

  /// 서버 오류 코드 → 화면 문구 (제출 화면의 '지금 제출할 수 없는 이유' 등)
  static String messageFor(String code) => _messages[code] ?? '지금은 제출할 수 없어요 ($code)';

  /// 항목별 오류(`missing:<id>` 등)는 양식 항목 이름으로 풀어 준다
  static String _itemMessage(String code, Map<String, String> labels) {
    final i = code.indexOf(':');
    if (i < 0) return _messages[code] ?? '요청 실패 ($code)';
    final kind = code.substring(0, i);
    final label = labels[code.substring(i + 1)] ?? code.substring(i + 1);
    return switch (kind) {
      'missing' => '「$label」 항목을 채워 주세요',
      'too_short' => '「$label」 글자 수가 부족해요',
      'invalid_link' => '「$label」에 http로 시작하는 주소를 넣어 주세요',
      _ => '요청 실패 ($code)',
    };
  }

  static Future<dynamic> _send(Future<http.Response> Function() req) async {
    final http.Response res;
    try {
      res = await req().timeout(const Duration(seconds: 30));
    } on CrewApiException {
      rethrow;
    } catch (_) {
      throw const CrewApiException(
          'network', '서버에 연결하지 못했어요. 네트워크를 확인해 주세요', 0);
    }
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw CrewApiException(
          'server', '서버가 응답하지 않아요 (${res.statusCode})', res.statusCode);
    }
    if (json['ok'] == true) return json['data'];
    final code = json['error'] as String? ?? 'unknown';
    throw CrewApiException(
        code, _messages[code] ?? '요청 실패 ($code)', res.statusCode);
  }

  static Future<dynamic> _get(String path) async {
    final h = await _headers();
    return _send(() => http.get(_uri(path), headers: h));
  }

  static Future<dynamic> _json(String method, String path,
      [Object? body]) async {
    final h = await _headers(json: true);
    final b = body == null ? null : jsonEncode(body);
    return _send(() => switch (method) {
          'POST' => http.post(_uri(path), headers: h, body: b),
          'PATCH' => http.patch(_uri(path), headers: h, body: b),
          'PUT' => http.put(_uri(path), headers: h, body: b),
          _ => http.delete(_uri(path), headers: h, body: b),
        });
  }

  // ── Pro ──────────────────────────────────────────────────────────

  static Future<ProStatus> proStatus() async =>
      ProStatus.fromJson(await _get('/api/pro/me') as Map<String, dynamic>);

  static Future<ProStatus> redeem(String code) async => ProStatus.fromJson(
      await _json('POST', '/api/pro/redeem', {'code': code})
          as Map<String, dynamic>);

  static Future<List<ProKey>> listKeys() async {
    final d = await _get('/api/pro/keys') as Map<String, dynamic>;
    return (d['keys'] as List)
        .map((e) => ProKey.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<String>> issueKeys({
    required int count,
    required int? durationDays,
    required int maxUses,
    String? note,
  }) async {
    final d = await _json('POST', '/api/pro/keys', {
      'count': count,
      'durationDays': durationDays,
      'maxUses': maxUses,
      if (note != null && note.isNotEmpty) 'note': note,
    }) as Map<String, dynamic>;
    return (d['codes'] as List).cast<String>();
  }

  static Future<void> revokeKey(int id) =>
      _json('POST', '/api/pro/keys/$id/revoke');

  // ── 동호회 ─────────────────────────────────────────────────────────

  static Future<(ProStatus, List<CrewSummary>)> myCrews() async {
    final d = await _get('/api/crews') as Map<String, dynamic>;
    return (
      ProStatus.fromJson(d['pro'] as Map<String, dynamic>),
      (d['crews'] as List)
          .map((e) => CrewSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 앱 개인 루틴 연동용 — 내가 속한 동호회들의 진행 중 과제
  static Future<List<CrewTask>> myTasks() async {
    final d = await _get('/api/crew-tasks/mine') as Map<String, dynamic>;
    return (d['tasks'] as List)
        .map((e) => CrewTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<int> createCrew(Map<String, dynamic> body) async {
    final d = await _json('POST', '/api/crews', body) as Map<String, dynamic>;
    return (d['id'] as num).toInt();
  }

  static Future<int> joinCrew(String inviteCode, {String? displayName}) async {
    final d = await _json('POST', '/api/crews/join', {
      'inviteCode': inviteCode,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    }) as Map<String, dynamic>;
    return (d['id'] as num).toInt();
  }

  static Future<CrewDetail> detail(int crewId) async => CrewDetail.fromJson(
      await _get('/api/crews/$crewId') as Map<String, dynamic>);

  static Future<void> updateCrew(int crewId, Map<String, dynamic> body) =>
      _json('PATCH', '/api/crews/$crewId', body);

  static Future<String> regenerateInvite(int crewId) async {
    final d = await _json('POST', '/api/crews/$crewId/invite')
        as Map<String, dynamic>;
    return d['inviteCode'] as String;
  }

  static Future<void> deleteCrew(int crewId) =>
      _json('DELETE', '/api/crews/$crewId');

  static Future<void> leaveCrew(int crewId) =>
      _json('POST', '/api/crews/$crewId/leave');

  static Future<void> addOfflineMember(int crewId,
          {required String name, String? note, String? joinedAt}) =>
      _json('POST', '/api/crews/$crewId/members', {
        'displayName': name,
        if (note != null && note.isNotEmpty) 'note': note,
        if (joinedAt != null) 'joinedAt': joinedAt,
      });

  static Future<void> updateMember(
          int crewId, int memberId, Map<String, dynamic> body) =>
      _json('PATCH', '/api/crews/$crewId/members/$memberId', body);

  static Future<void> removeMember(int crewId, int memberId) =>
      _json('DELETE', '/api/crews/$crewId/members/$memberId');

  static Future<void> createTask(int crewId, CrewTask t) =>
      _json('POST', '/api/crews/$crewId/tasks', t.toJson());

  static Future<void> updateTask(int crewId, int taskId, CrewTask t) =>
      _json('PATCH', '/api/crews/$crewId/tasks/$taskId', t.toJson());

  static Future<void> archiveTask(int crewId, int taskId) =>
      _json('DELETE', '/api/crews/$crewId/tasks/$taskId');

  /// 본인 과제 제출 — 앱에서 인증하면 자동으로 호출된다
  static Future<void> submit({
    required int crewId,
    required int taskId,
    required String dateKey,
    required String memo,
    String? progressValue,
    required String verifyMethod,
    int? durationSec,
    String? linkUrl,
    bool isBackup = false,
    required DateTime certifiedAt,
    Uint8List? photoJpeg,
  }) async {
    final h = await _headers();
    final req = http.MultipartRequest(
        'POST', _uri('/api/crews/$crewId/tasks/$taskId/submit'))
      ..headers.addAll(h)
      ..fields['dateKey'] = dateKey
      ..fields['memo'] = memo
      ..fields['verifyMethod'] = verifyMethod
      ..fields['isBackup'] = '$isBackup'
      ..fields['certifiedAt'] = certifiedAt.toUtc().toIso8601String();
    if (progressValue != null) req.fields['progressValue'] = progressValue;
    if (durationSec != null) req.fields['durationSec'] = '$durationSec';
    if (linkUrl != null) req.fields['linkUrl'] = linkUrl;
    if (photoJpeg != null) {
      req.files.add(http.MultipartFile.fromBytes('photo', photoJpeg,
          filename: 'cert.jpg', contentType: MediaType('image', 'jpeg')));
    }
    await _send(() async => http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 90))));
  }

  static Future<void> withdraw(int crewId, int taskId, String dateKey) =>
      _json('DELETE',
          '/api/crews/$crewId/tasks/$taskId/submit?dateKey=$dateKey');

  /// 반장·부반장 체크 — status: submitted(대리 제출) | excused(인정) | clear(지우기)
  static Future<void> mark(int crewId,
          {required int taskId,
          required int memberId,
          required String dateKey,
          required String status,
          String? memo}) =>
      _json('PUT', '/api/crews/$crewId/marks', {
        'taskId': taskId,
        'memberId': memberId,
        'dateKey': dateKey,
        'status': status,
        if (memo != null && memo.isNotEmpty) 'memo': memo,
      });

  static Future<CrewBoard> board(int crewId, {String? date}) async =>
      CrewBoard.fromJson(await _get(
              '/api/crews/$crewId/board${date == null ? '' : '?date=$date'}')
          as Map<String, dynamic>);

  static String _range(String? from, String? to) {
    final q = [
      if (from != null) 'from=$from',
      if (to != null) 'to=$to',
    ];
    return q.isEmpty ? '' : '?${q.join('&')}';
  }

  static Future<CrewStats> stats(int crewId, {String? from, String? to}) async =>
      CrewStats.fromJson(await _get('/api/crews/$crewId/stats${_range(from, to)}')
          as Map<String, dynamic>);

  static Future<CrewSettlement> settlement(int crewId,
          {String? from, String? to}) async =>
      CrewSettlement.fromJson(
          await _get('/api/crews/$crewId/settlement${_range(from, to)}')
              as Map<String, dynamic>);

  static Future<void> addPayment(int crewId,
          {required int memberId,
          required String kind,
          required int amount,
          String? memo}) =>
      _json('POST', '/api/crews/$crewId/payments', {
        'memberId': memberId,
        'kind': kind,
        'amount': amount,
        if (memo != null && memo.isNotEmpty) 'memo': memo,
      });

  static Future<void> deletePayment(int crewId, int paymentId) =>
      _json('DELETE', '/api/crews/$crewId/payments/$paymentId');

  // ── 과제 점검형: 회차·제출·점검 ─────────────────────────────────

  static Future<CrewSlot> slot(int crewId, int taskId, {String? dateKey}) async =>
      CrewSlot.fromJson(await _get(
              '/api/crews/$crewId/tasks/$taskId/slot${dateKey == null ? '' : '?dateKey=$dateKey'}')
          as Map<String, dynamic>);

  static Future<List<CrewSession>> sessions(int crewId, int taskId) async {
    final d = await _get('/api/crews/$crewId/tasks/$taskId/sessions')
        as Map<String, dynamic>;
    return (d['sessions'] as List)
        .map((e) => CrewSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 회차 내용 저장 — [form]이 null이면 과제 기본 양식을 쓴다
  static Future<void> saveSession(int crewId, int taskId, String dateKey,
          {String? title, String? guide, List<FormItem>? form}) =>
      _json('PUT', '/api/crews/$crewId/tasks/$taskId/sessions/$dateKey', {
        'title': title,
        'guide': guide,
        'form': form?.map((f) => f.toJson()).toList(),
      });

  /// 과제 점검형 제출 — 답안 + 항목별 첨부
  static Future<void> submitAssignment({
    required int crewId,
    required int taskId,
    required String dateKey,
    required Map<String, Object> answers,
    required List<UploadFile> files,
    required List<FormItem> form,
  }) async {
    final h = await _headers();
    final req = http.MultipartRequest(
        'POST', _uri('/api/crews/$crewId/tasks/$taskId/submit'))
      ..headers.addAll(h)
      ..fields['dateKey'] = dateKey
      ..fields['answers'] = jsonEncode(answers)
      ..fields['certifiedAt'] = DateTime.now().toUtc().toIso8601String();
    for (final f in files) {
      final parts = f.mime.split('/');
      req.files.add(http.MultipartFile.fromBytes('file:${f.itemId}', f.bytes,
          filename: f.name,
          contentType: MediaType(parts.first,
              parts.length > 1 ? parts.last : 'octet-stream')));
    }
    try {
      await _send(() async => http.Response.fromStream(
          await req.send().timeout(const Duration(minutes: 3))));
    } on CrewApiException catch (e) {
      if (e.code.contains(':')) {
        throw CrewApiException(e.code,
            _itemMessage(e.code, {for (final i in form) i.id: i.label}), e.status);
      }
      rethrow;
    }
  }

  /// 점검 — status: approved(확인) | rejected(보완 요청, 피드백 필수) | clear(취소)
  static Future<void> review(int crewId, int submissionId,
          {required String status, String? note}) =>
      _json('PUT', '/api/crews/$crewId/submissions/$submissionId/review', {
        'status': status,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  static Future<SubmissionDetail> submissionDetail(
          int crewId, int submissionId) async =>
      SubmissionDetail.fromJson(
          await _get('/api/crews/$crewId/submissions/$submissionId')
              as Map<String, dynamic>);

  /// 첨부 내려받기 (동호회 회원만 — 세션 쿠키가 필요해 직접 받는다)
  static Future<Uint8List> download(String url) async {
    final h = await imageHeaders();
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse(mediaUrl(url)), headers: h)
          .timeout(const Duration(minutes: 2));
    } catch (_) {
      throw const CrewApiException(
          'network', '서버에 연결하지 못했어요. 네트워크를 확인해 주세요', 0);
    }
    if (res.statusCode != 200) {
      throw CrewApiException(
          'download', '파일을 받지 못했어요 (${res.statusCode})', res.statusCode);
    }
    return res.bodyBytes;
  }

  // ── 게시판 ─────────────────────────────────────────────────────

  static Future<(List<CrewPostSummary>, bool, int)> posts(int crewId,
      {int page = 1}) async {
    final d = await _get('/api/crews/$crewId/posts?page=$page')
        as Map<String, dynamic>;
    return (
      (d['posts'] as List)
          .map((e) => CrewPostSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      d['canNotice'] == true,
      (d['total'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<CrewPostDetail> post(int crewId, int postId) async =>
      CrewPostDetail.fromJson(await _get('/api/crews/$crewId/posts/$postId')
          as Map<String, dynamic>);

  static Future<int> writePost(int crewId,
      {required String title, required String body, bool notice = false}) async {
    final d = await _json('POST', '/api/crews/$crewId/posts',
        {'title': title, 'body': body, 'notice': notice}) as Map<String, dynamic>;
    return (d['id'] as num).toInt();
  }

  static Future<void> editPost(int crewId, int postId,
          {required String title, required String body, bool notice = false}) =>
      _json('PATCH', '/api/crews/$crewId/posts/$postId',
          {'title': title, 'body': body, 'notice': notice});

  static Future<void> deletePost(int crewId, int postId) =>
      _json('DELETE', '/api/crews/$crewId/posts/$postId');

  static Future<void> comment(int crewId, int postId, String body) =>
      _json('POST', '/api/crews/$crewId/posts/$postId/comments', {'body': body});

  static Future<void> deleteComment(int crewId, int commentId) =>
      _json('DELETE', '/api/crews/$crewId/comments/$commentId');

  // ── 메인 관리자 ─────────────────────────────────────────────────

  static Future<AdminOverview> adminOverview() async => AdminOverview.fromJson(
      await _get('/api/admin/overview') as Map<String, dynamic>);

  static Future<List<AdminUserRow>> adminProMembers() async {
    final d = await _get('/api/admin/pro-members') as Map<String, dynamic>;
    return (d['members'] as List)
        .map((e) => AdminUserRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<AdminUserRow>> adminSearchUsers(String q) async {
    final d = await _get('/api/admin/users?q=${Uri.encodeQueryComponent(q)}')
        as Map<String, dynamic>;
    return (d['users'] as List)
        .map((e) => AdminUserRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Pro 직접 지급·연장(days: null = 평생) / 해지
  static Future<void> adminGrantPro(int userId, {int? days}) =>
      _json('POST', '/api/admin/pro-members/$userId',
          {'action': 'grant', 'days': days});

  static Future<void> adminRevokePro(int userId) =>
      _json('POST', '/api/admin/pro-members/$userId', {'action': 'revoke'});

  static Future<List<AdminCrewRow>> adminCrews() async {
    final d = await _get('/api/admin/crews') as Map<String, dynamic>;
    return (d['crews'] as List)
        .map((e) => AdminCrewRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> adminSetCrewHidden(int crewId, bool hidden) =>
      _json('POST', '/api/admin/crews/$crewId/${hidden ? 'hide' : 'restore'}');
}
