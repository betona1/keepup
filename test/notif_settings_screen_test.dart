import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/app_state.dart';
import 'package:keepup/models/notif_settings.dart';
import 'package:keepup/models/routine.dart';
import 'package:keepup/screens/notif_settings_screen.dart';
import 'package:keepup/services/storage_service.dart';
import 'package:keepup/theme.dart';

/// 설정 화면 — 스위치 토글이 AppState에 반영되는지 (알림 예약은 실기기 몫).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 설정 변경은 알림 재예약(reconcile → cancelAll)을 부른다.
  // 테스트엔 플랫폼이 없으니 알림 플러그인 채널을 no-op으로 막는다.
  const notifChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
  });

  testWidgets('마감 3시간 전 스위치를 끄면 설정에 저장된다', (tester) async {
    final storage = _FakeStorage();
    final state = AppState(storage);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: NotifSettingsScreen(state: state),
    ));

    // 초기값: 09:00 · 슬롯 3개 모두 켜짐
    expect(find.text('09:00'), findsOneWidget);
    expect(state.notifSettings.slot180, isTrue);

    // '마감 3시간 전' 스위치 끄기
    final row = find.widgetWithText(SwitchListTile, '마감 3시간 전');
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(state.notifSettings.slot180, isFalse);
    expect(storage.saved?.slot180, isFalse); // 저장까지 됐는지
    // 나머지는 그대로
    expect(state.notifSettings.slot60, isTrue);
  });

  testWidgets('모든 임박 슬롯을 끄면 경고 문구가 뜬다', (tester) async {
    final state = AppState(_FakeStorage());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: NotifSettingsScreen(state: state),
    ));

    for (final label in ['마감 3시간 전', '마감 1시간 전', '마감 30분 전']) {
      await tester.tap(find.widgetWithText(SwitchListTile, label));
      await tester.pumpAndSettle();
    }

    expect(state.notifSettings.activeOffsets, isEmpty);
    expect(find.textContaining('모두 껐어요'), findsOneWidget);
  });
}

class _FakeStorage implements StorageService {
  NotifSettings? saved;
  @override
  List<Routine> loadRoutines() => [];
  @override
  List<Certification> loadCerts() => [];
  @override
  NotifSettings loadNotifSettings() => NotifSettings.defaults;
  @override
  Future<void> saveRoutines(List<Routine> r) async {}
  @override
  Future<void> saveCerts(List<Certification> c) async {}
  @override
  Future<void> saveNotifSettings(NotifSettings s) async => saved = s;
}
