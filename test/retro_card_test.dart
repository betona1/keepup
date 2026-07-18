import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:keepup/app_state.dart';
import 'package:keepup/models/notif_settings.dart';
import 'package:keepup/models/routine.dart';
import 'package:keepup/services/retro_service.dart';
import 'package:keepup/services/storage_service.dart';
import 'package:keepup/theme.dart';
import 'package:keepup/widgets/retro_card.dart';

/// 회고 카드 렌더 검증 — 실기기 없이 레이아웃(오버플로)과 통계를 확인하고,
/// 실제 카드 이미지를 PNG로 뽑아 눈으로 볼 수 있게 한다.
///   flutter test test/retro_card_test.dart
/// 결과물: build/retro_preview/*.png
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    await _loadNanumGothic();
  });

  testWidgets('적립형 63일 시즌 — 도장 대부분 채운 카드', (tester) async {
    final routine = _routine(
      title: '매일 아침 5천보 걷기',
      reason: '출근 전 30분, 하루를 내 편으로 만들고 싶어서',
      type: RoutineType.accumulate,
      dutyCycle: DutyCycle.everyday,
      verifyMethod: VerifyMethod.steps,
      days: 63,
    );
    // 의무일 중 군데군데 빠뜨린 시즌
    final state = _stateWith(
      routine: routine,
      stamped: (i) => !(i % 9 == 4 || (i >= 20 && i <= 22) || i > 58),
      steps: 5400,
    );
    final stats = state.retroStatsFor(routine.id);

    expect(stats.totalDutyDays, 63); // 매일 = 63일 전부 의무
    expect(stats.certifiedDays, stats.totalCerts);
    expect(stats.percent, inInclusiveRange(70, 85));
    expect(stats.missedDays, greaterThan(0));
    expect(stats.dayMarks.length % 7, 0); // 그리드는 항상 7의 배수
    expect(stats.tallyLabel, contains('보')); // 걸음수 누적 표시

    await _pumpAndShoot(tester, state, routine, 'season_63days');
  });

  testWidgets('결과형 1년 시즌 — 53주 그리드가 폭 안에 들어오는가', (tester) async {
    final routine = _routine(
      title: '주 1회 독서 결과 인증',
      reason: '1년에 책 24권을 읽는 사람이 되기로 했다',
      type: RoutineType.result,
      dutyCycle: DutyCycle.weekly,
      verifyMethod: VerifyMethod.timer,
      days: 365,
    );
    final state = _stateWith(
      routine: routine,
      stamped: (i) => i % 5 != 3, // 다섯 주에 한 번씩 놓침
      durationSec: 45 * 60,
    );
    final stats = state.retroStatsFor(routine.id);

    expect(stats.weeks, greaterThan(50)); // 1년 = 52~54주
    expect(stats.totalDutyDays, inInclusiveRange(51, 53)); // 주 1회
    expect(stats.percent, inInclusiveRange(75, 85)); // 5주 중 1주 놓침 ≈ 80%
    expect(stats.missedDays, greaterThan(5)); // 놓친 주가 그리드에 남는다
    expect(stats.tallyLabel, contains('시간'));

    await _pumpAndShoot(tester, state, routine, 'season_1year');
  });

  testWidgets('도장이 하나도 없는 시즌 — 0% 카드', (tester) async {
    final routine = _routine(
      title: '중국어 발음 매일 한마디',
      reason: '',
      type: RoutineType.accumulate,
      dutyCycle: DutyCycle.sixDays,
      verifyMethod: VerifyMethod.audio,
      days: 30,
    );
    final state = _stateWith(routine: routine, stamped: (_) => false);
    final stats = state.retroStatsFor(routine.id);

    expect(stats.percent, 0);
    expect(stats.longestStreak, 0);
    expect(stats.certifiedDays, 0);
    expect(stats.tallyLabel, isNull); // 누적 수치 없음 → 배지 숨김
    expect(stats.headline, contains('첫 도장'));
    // 주6일 = 일요일은 의무 아님
    expect(stats.totalDutyDays, lessThan(30));

    await _pumpAndShoot(tester, state, routine, 'season_zero');
  });

  testWidgets('완주 100% — PERFECT 배지', (tester) async {
    final routine = _routine(
      title: '자기 전 명상 15분',
      reason: '하루를 조용히 닫는 법을 배우고 싶었다',
      type: RoutineType.accumulate,
      dutyCycle: DutyCycle.everyday,
      verifyMethod: VerifyMethod.timer,
      days: 30,
    );
    final state = _stateWith(
      routine: routine,
      stamped: (_) => true,
      durationSec: 15 * 60,
    );
    final stats = state.retroStatsFor(routine.id);

    expect(stats.percent, 100);
    expect(stats.badge, 'PERFECT');
    expect(stats.longestStreak, 30);
    expect(stats.missedDays, 0);
    expect(stats.headline, contains('빠지지 않았어요'));

    await _pumpAndShoot(tester, state, routine, 'season_perfect');
  });

  // 앱이 실제로 쓰는 캡처 경로 — 공유 시트(share_plus)만 실기기 몫으로 남는다
  testWidgets('RetroService.capture — 카드가 PNG 파일로 구워진다', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('keepup_retro_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    _mockAppDocumentsDir(tmp.path);
    addTearDown(_unmockAppDocumentsDir);

    final routine = _routine(
      title: '계단 15층 오르기',
      reason: '엘리베이터 대신 내 다리를 쓰기로',
      type: RoutineType.accumulate,
      dutyCycle: DutyCycle.everyday,
      verifyMethod: VerifyMethod.photo,
      days: 30,
    );
    final state = _stateWith(routine: routine, stamped: (i) => i % 4 != 0);
    final stats = state.retroStatsFor(routine.id);
    final key = GlobalKey();

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(key: key, child: RetroCard(stats: stats)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 엔진 디코딩(runAsync)이 필요한 작업은 모두 이 블록 안에서 끝낸다 —
    // 가짜 시간축에서는 실제 비동기가 완료되지 않아 밖으로 새면 멈춘다
    late File out;
    late int width;
    late int height;
    await tester.runAsync(() async {
      out = await RetroService.capture(key, pixelRatio: 2.0);
      final decoded = await decodeImageFromList(out.readAsBytesSync());
      width = decoded.width;
      height = decoded.height;
    });

    expect(out.existsSync(), isTrue);
    expect(out.path, contains('retro'));
    expect(out.path, endsWith('.png'));

    // 진짜 PNG인지 (매직 넘버) + 카드 폭 * pixelRatio 만큼 나왔는지
    final bytes = out.readAsBytesSync();
    expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(width, (RetroCard.width * 2).round());
    expect(height, greaterThan(500));
  });

  test('화면에 없는 카드를 캡처하면 친절한 에러', () async {
    await expectLater(
      RetroService.capture(GlobalKey()),
      throwsA(isA<StateError>()),
    );
  });
}

// ── path_provider 모킹 (테스트에는 앱 문서 폴더가 없다) ────────────

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void _mockAppDocumentsDir(String path) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    if (call.method == 'getApplicationDocumentsDirectory') return path;
    return null;
  });
}

void _unmockAppDocumentsDir() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
}

// ── 헬퍼 ───────────────────────────────────────────────────────

/// 오늘 끝나는 시즌 (= 종료 직후, 회고 카드를 보는 시점)
Routine _routine({
  required String title,
  required String reason,
  required RoutineType type,
  required DutyCycle dutyCycle,
  required VerifyMethod verifyMethod,
  required int days,
}) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final start = end.subtract(Duration(days: days - 1));
  return Routine(
    id: 'r1',
    type: type,
    title: title,
    reason: reason,
    dutyCycle: dutyCycle,
    createdAt: start,
    verifyMethod: verifyMethod,
    startDate: start,
    endDate: end,
  );
}

/// 의무일만 골라 인증 기록을 만든다.
/// [stamped]에는 날짜 오프셋이 아니라 **의무일 순번**(0,1,2…)이 들어간다 —
/// 주기(매일/주1회)에 따라 의무일 간격이 달라지므로 순번이어야 의도대로 건너뛴다.
AppState _stateWith({
  required Routine routine,
  required bool Function(int dutyIndex) stamped,
  int? steps,
  int? durationSec,
}) {
  final state = AppState(_FakeStorage());
  final certs = <Certification>[];
  final total = routine.endDate.difference(routine.startDate).inDays;
  var dutyIndex = 0;
  for (var off = 0; off <= total; off++) {
    final day = routine.startDate.add(Duration(days: off));
    if (!routine.isDutyDay(day)) continue;
    final i = dutyIndex++;
    if (!stamped(i)) continue;
    certs.add(Certification(
      id: 'c$off',
      routineId: routine.id,
      dateKey: dateKeyOf(day),
      photoPath: '',
      memo: '',
      timestamp: DateTime(day.year, day.month, day.day, 21, 30),
      verifyMethod: routine.verifyMethod.name,
      steps: steps,
      durationSec: durationSec,
    ));
  }
  state.routines = [routine];
  state.certs = certs;
  return state;
}

/// 카드를 그려 오버플로 없이 그려졌는지 확인하고 PNG로 저장한다.
Future<void> _pumpAndShoot(
  WidgetTester tester,
  AppState state,
  Routine routine,
  String name,
) async {
  final stats = state.retroStatsFor(routine.id);
  final key = GlobalKey();

  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF1F8),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: RetroCard(stats: stats),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // RenderFlex 오버플로 등 렌더 예외는 여기서 잡힌다
  expect(tester.takeException(), isNull);
  expect(find.text('${stats.percent}'), findsOneWidget);
  expect(find.text(routine.title), findsOneWidget);

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final dir = Directory('build/retro_preview');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// 번들 폰트를 테스트 렌더러에 올린다 (없으면 한글이 네모로 나온다)
Future<void> _loadNanumGothic() async {
  final loader = FontLoader('NanumGothic');
  var found = false;
  for (final f in [
    'assets/fonts/NanumGothic-Regular.ttf',
    'assets/fonts/NanumGothic-Bold.ttf',
    'assets/fonts/NanumGothic-ExtraBold.ttf',
  ]) {
    final file = File(f);
    if (file.existsSync()) {
      found = true;
      loader.addFont(
          Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  if (found) await loader.load();
}

/// 저장소를 건드리지 않는 테스트용 스텁 (회고 통계는 순수 계산이라 저장이 필요 없다)
class _FakeStorage implements StorageService {
  @override
  List<Routine> loadRoutines() => [];
  @override
  List<Certification> loadCerts() => [];
  @override
  NotifSettings loadNotifSettings() => NotifSettings.defaults;
  @override
  Future<void> saveRoutines(List<Routine> routines) async {}
  @override
  Future<void> saveCerts(List<Certification> certs) async {}
  @override
  Future<void> saveNotifSettings(NotifSettings s) async {}
}
