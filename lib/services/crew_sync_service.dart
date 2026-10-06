import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../models/routine.dart';
import 'account_service.dart';
import 'crew_api.dart';
import 'media_store.dart';

/// 동호회 과제 ↔ 개인 루틴 연동.
///
/// 1) 과제 받아오기: 내가 속한 동호회의 과제를 개인 루틴(`crew-<taskId>`)으로 만든다/갱신한다.
///    → 도장 달력·마감 알람이 개인 루틴과 똑같이 동작한다.
/// 2) 제출: 동호회 루틴에 도장을 찍으면 같은 내용(사진·소감·수치)을 동호회에 제출한다.
///    네트워크가 끊겨 있으면 대기열에 넣어 두고 앱을 다시 열 때 보낸다.
/// 3) 취소: 동호회 루틴의 인증을 지우면 마감 전인 동호회 제출도 함께 취소한다.
///
/// 결과(성공·실패 사유)는 [notices]로 흘려보내 루트 화면이 스낵바로 띄운다 —
/// 제출 실패를 조용히 삼키면 '도장은 찍혔는데 동호회엔 미제출'인 상태를 아무도 모른다.
class CrewSyncService {
  CrewSyncService._();
  static final instance = CrewSyncService._();

  static const _queueKey = 'crew_submit_queue_v1';

  /// 화면에 띄울 안내 (RootScreen이 구독)
  final notices = ValueNotifier<String?>(null);

  AppState? _state;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool _syncing = false;
  bool _flushing = false;

  void attach(AppState state) => _state = state;

  void _notice(String msg) {
    notices.value = null; // 같은 문구가 연달아 와도 다시 알리도록
    notices.value = msg;
  }

  /// 동호회 과제를 받아 개인 루틴에 반영한다.
  /// [force]가 아니면 30초 안의 반복 호출은 건너뛴다 (앱 복귀마다 부르기 때문).
  /// 사용자가 직접 새로고침했을 때만 오류를 던지고, 자동 호출은 조용히 넘어간다.
  Future<void> syncTasks({bool force = false}) async {
    final state = _state;
    if (state == null || _syncing) return;
    if (!force &&
        DateTime.now().difference(_lastSync) < const Duration(seconds: 30)) {
      return;
    }
    // 로그인 안 했으면 동호회도 없다 — 기존 동호회 루틴은 건드리지 않는다
    if (!kIsWeb && await AccountService.instance.sessionToken() == null) return;

    _syncing = true;
    try {
      final tasks = await CrewApi.myTasks();
      _lastSync = DateTime.now();
      final changed = await state.applyCrewTasks(tasks);
      if (changed > 0 && !force) {
        _notice('동호회 과제가 갱신됐어요 ($changed건)');
      }
    } on CrewApiException catch (e) {
      if (force) rethrow;
      debugPrint('동호회 과제 동기화 실패: $e');
    } finally {
      _syncing = false;
    }
  }

  /// 동호회 루틴 인증 직후 호출 — 동호회에 제출한다. 반환: 화면에 띄울 결과 문구.
  Future<String> submitCert(Certification cert, Routine routine) async {
    try {
      await _submit(cert, routine);
      return '동호회 「${routine.crewName ?? ''}」에 제출했어요 ✅';
    } on CrewApiException catch (e) {
      if (e.isNetwork) {
        await _enqueue(cert.id);
        return '지금은 연결이 안 돼서 동호회 제출을 미뤄 뒀어요. 앱을 다시 열면 자동으로 보낼게요';
      }
      return '개인 도장은 찍혔지만 동호회 제출은 실패했어요 — ${e.message}';
    }
  }

  Future<void> _submit(Certification cert, Routine routine) async {
    Uint8List? photo;
    if (cert.hasPhoto) {
      photo = await MediaStore.readBytes(cert.photoPath);
      // 워터마크 사진은 1440px JPEG라 보통 1MB 안팎. 드물게 원본이 너무 크면 사진 없이 낸다
      if (photo != null && photo.lengthInBytes > 5 * 1024 * 1024) photo = null;
    }
    await CrewApi.submit(
      crewId: routine.crewId!,
      taskId: routine.crewTaskId!,
      dateKey: cert.dateKey,
      memo: cert.memo,
      progressValue: cert.progressValue,
      verifyMethod: cert.verifyMethod,
      durationSec: cert.durationSec,
      linkUrl: cert.linkUrl,
      isBackup: cert.isBackup,
      certifiedAt: cert.timestamp,
      photoJpeg: photo,
    );
  }

  /// 동호회 루틴 인증을 지웠을 때 — 마감 전이면 동호회 제출도 취소
  Future<void> withdrawCert(Certification cert, Routine routine) async {
    await _dequeue(cert.id);
    try {
      await CrewApi.withdraw(routine.crewId!, routine.crewTaskId!, cert.dateKey);
      _notice('동호회 제출도 함께 취소했어요');
    } on CrewApiException catch (e) {
      _notice(e.code == 'deadline_passed'
          ? '마감이 지난 동호회 제출은 취소되지 않아요 (동호회 기록은 그대로)'
          : '동호회 제출 취소 실패 — ${e.message}');
    }
  }

  // ── 대기열 (오프라인일 때 미룬 제출) ─────────────────────────────

  Future<List<String>> _queue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveQueue(List<String> q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(q));
  }

  Future<void> _enqueue(String certId) async {
    final q = await _queue();
    if (!q.contains(certId)) await _saveQueue([...q, certId]);
  }

  Future<void> _dequeue(String certId) async {
    final q = await _queue();
    if (q.remove(certId)) await _saveQueue(q);
  }

  /// 미뤄 둔 제출을 보낸다 — 앱 시작·복귀 때 호출
  Future<void> flushQueue() async {
    final state = _state;
    if (state == null || _flushing) return;
    final q = await _queue();
    if (q.isEmpty) return;
    _flushing = true;
    try {
      final remain = <String>[];
      var sent = 0;
      for (final id in q) {
        final cert = state.certs.where((c) => c.id == id).firstOrNull;
        final routine = cert == null ? null : state.routineById(cert.routineId);
        if (cert == null || routine == null || !routine.isCrew) continue;
        try {
          await _submit(cert, routine);
          sent++;
        } on CrewApiException catch (e) {
          if (e.isNetwork) {
            remain.add(id);
          } else {
            _notice('미뤄 둔 동호회 제출 실패 (${routine.title}) — ${e.message}');
          }
        }
      }
      await _saveQueue(remain);
      if (sent > 0) _notice('미뤄 둔 동호회 과제 $sent건을 제출했어요 ✅');
    } finally {
      _flushing = false;
    }
  }
}
