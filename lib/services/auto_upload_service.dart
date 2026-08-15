import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/routine.dart';
import 'account_service.dart';
import 'cloud_sync_service.dart';

/// 기록이 바뀔 때마다(도장·루틴 변경 등) 로그인돼 있으면 클라우드 백업을
/// 자동으로 새로 올린다 — "폰이 원본"이라는 전제의 단방향 자동 올리기.
///
/// - 웹(PWA)에서는 동작하지 않는다. 브라우저 쪽 기록이 폰의 백업을 조용히
///   덮어쓰는 사고를 막기 위해서다. 웹은 '폰에서 가져오기'로 받기만 한다.
/// - 연속 변경은 [_debounce] 동안 묶어서 한 번만 올린다.
/// - 실패(오프라인·세션 만료 등)는 조용히 넘기고 '올릴 게 남았다'(dirty)만
///   기억해 뒀다가 다음 앱 시작/복귀 때 다시 시도한다. 화면을 막지 않는다.
/// - 빈 기록(루틴·인증 0개)은 올리지 않는다 — 새 설치가 클라우드를 지우는 사고 방지.
class AutoUploadService {
  static final AutoUploadService instance = AutoUploadService._();
  AutoUploadService._();

  static const _enabledKey = 'auto_upload_enabled_v1';
  static const _dirtyKey = 'auto_upload_dirty_v1';
  static const _lastAtKey = 'auto_upload_last_at_v1';

  /// 연속 변경(인증 여러 건, 루틴 수정 등)을 한 번의 업로드로 묶는 대기 시간
  static const _debounce = Duration(seconds: 5);

  /// 지금 기기의 최신 기록을 읽어오는 함수 — main에서 AppState로 연결한다.
  /// (디바운스 뒤에 올리므로, 호출 시점이 아니라 업로드 시점의 데이터를 쓴다)
  (List<Routine>, List<Certification>) Function()? provider;

  Timer? _timer;
  bool _running = false;

  /// 최근 자동 올리기 성공 시각 (클라우드 시트 표시용)
  final ValueNotifier<DateTime?> lastUploadedAt = ValueNotifier(null);

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastAtKey);
      if (raw != null) lastUploadedAt.value = DateTime.tryParse(raw);
    } catch (_) {/* 표시용이므로 무시 */}
  }

  /// 자동 올리기 켜짐 여부 (기본 켜짐)
  Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      return false; // 저장소를 못 읽는 환경(테스트 등)에서는 동작하지 않는다
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {}
    if (value) {
      await flushIfDirty(); // 켜는 순간 밀린 기록이 있으면 바로 올린다
    } else {
      _timer?.cancel();
    }
  }

  /// 기록 변경 직후 호출 — dirty 표시 후, 로그인·설정이 맞으면 잠시 뒤 올린다.
  void schedule() {
    if (kIsWeb) return;
    _setDirty(true);
    _arm();
  }

  /// 앱 시작·복귀 때 호출 — 지난번에 못 올린 기록이 있으면 다시 시도한다.
  Future<void> flushIfDirty() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_dirtyKey) != true) return;
    } catch (_) {
      return;
    }
    await _arm();
  }

  /// 수동 올리기/내려받기 직후 호출 — 로컬과 클라우드가 같아졌으므로
  /// 대기 중인 자동 올리기를 거두고 dirty를 지운다.
  void markClean() {
    if (kIsWeb) return;
    _timer?.cancel();
    _setDirty(false);
  }

  Future<void> _arm() async {
    if (!await enabled()) return;
    String? token;
    try {
      token = await AccountService.instance.sessionToken();
    } catch (_) {}
    if (token == null) return; // 미로그인 — dirty만 남겨 두고 조용히 대기
    _timer?.cancel();
    _timer = Timer(_debounce, _run);
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      final data = provider?.call();
      if (data == null) return;
      final (routines, certs) = data;
      if (routines.isEmpty && certs.isEmpty) {
        // 빈 기록으로 클라우드를 덮지 않는다 (전부 지운 경우는 수동 올리기로)
        await _setDirty(false);
        return;
      }
      await CloudSyncService.upload(routines, certs);
      await _setDirty(false);
      final now = DateTime.now();
      lastUploadedAt.value = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastAtKey, now.toIso8601String());
      } catch (_) {}
    } catch (_) {
      // 오프라인·60MB 초과·세션 만료 등 — dirty 유지, 다음 기회에 재시도.
      // 자동 동작이라 화면에 오류를 띄우지 않는다 (수동 올리기는 그대로 쓸 수 있다).
    } finally {
      _running = false;
    }
  }

  Future<void> _setDirty(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dirtyKey, value);
    } catch (_) {}
  }
}
