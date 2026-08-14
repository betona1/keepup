import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'app_state.dart';
import 'theme.dart';
import 'services/media_store.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/timer_service.dart';
import 'screens/home_screen.dart';
import 'screens/certify_screen.dart';
import 'services/backup_service.dart';
import 'services/cloud_sync_service.dart';
import 'widgets/cloud_sync_sheet.dart';
import 'widgets/login_sheet.dart';
import 'screens/history_screen.dart';
import 'screens/add_routine_screen.dart';
import 'screens/notif_settings_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 날짜 로케일(한국어 요일 등)
  await initializeDateFormatting('ko');

  // 타임존 초기화 (예약 알림에 필요)
  tzdata.initializeTimeZones();
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
  }

  await NotificationService.instance.init();

  // 사진 저장소 준비 (네이티브: 앱 문서 폴더 / 웹: 브라우저 IndexedDB)
  await MediaStore.init();

  final storage = await StorageService.create();
  final state = AppState(storage);
  await state.load();

  // 진행 중이던 타이머 세션 복원 (앱을 껐다 켜도 달리기·명상 시간이 이어짐)
  await TimerService.instance.load();

  // 알림 권한 요청 (첫 실행 시)
  await NotificationService.instance.requestPermissions();

  runApp(HabitApp(state: state));
}

class HabitApp extends StatelessWidget {
  final AppState state;
  const HabitApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '로그챌린지',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // 데스크톱 브라우저에서 창 폭을 따라 무한정 넓어지지 않게 —
      // 폰 폭(520)으로 가운데 정렬하고 양옆은 브랜드 네이비로 채운다.
      // 다이얼로그·바텀시트도 이 안에서 뜨므로 함께 적당한 크기가 된다.
      builder: (context, child) {
        if (!kIsWeb) return child!;
        return LayoutBuilder(builder: (context, constraints) {
          const maxW = 520.0;
          if (constraints.maxWidth <= maxW) return child!;
          final mq = MediaQuery.of(context);
          return ColoredBox(
            color: AppTheme.navyDeep,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: maxW),
                decoration: const BoxDecoration(boxShadow: [
                  BoxShadow(color: Colors.black45, blurRadius: 40),
                ]),
                // 화면 코드가 MediaQuery로 폭을 읽어도 실제 폭과 맞도록 보정
                child: MediaQuery(
                  data: mq.copyWith(size: Size(maxW, mq.size.height)),
                  child: child!,
                ),
              ),
            ),
          );
        });
      },
      home: _Entry(state: state),
    );
  }
}

/// 인트로(3초) → 앱 본화면. 인트로는 첫 실행 여부와 무관하게 매번 짧게 보여준다.
class _Entry extends StatefulWidget {
  final AppState state;
  const _Entry({required this.state});

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  bool _intro = true;

  @override
  Widget build(BuildContext context) {
    // 본화면을 먼저 깔고 그 위를 인트로가 덮는다.
    // 인트로가 스스로 옅어지며 사라지므로 중간에 빈 화면이 깜빡이지 않고,
    // 인트로가 도는 3초 동안 본화면이 미리 준비된다.
    return Stack(
      children: [
        RootScreen(state: widget.state),
        if (_intro)
          Positioned.fill(
            child: SplashScreen(
              onDone: () {
                if (mounted) setState(() => _intro = false);
              },
            ),
          ),
      ],
    );
  }
}

class RootScreen extends StatefulWidget {
  final AppState state;
  const RootScreen({super.key, required this.state});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _index = 0;

  // '가져오기 요청' 승인 안내 — 중복 표시·과잉 폴링 방지
  bool _pullDialogOpen = false;
  DateTime _lastPullCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 타이머가 목표를 채우면 인증 화면으로 이동해 자동으로 도장을 찍는다
    TimerService.instance.onComplete = _onTimerComplete;
    // 인트로가 도는 사이에 목표를 채웠을 수도 있으니 한 번 점검한다
    TimerService.instance.checkCompletion();
    // 다른 기기가 '기록 보내달라'고 요청해 뒀는지 확인 (로그인 상태에서만 의미)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPullRequest());
    // 자동 스냅샷으로 데이터를 되살렸으면 사용자에게 알린다
    if (widget.state.restoredFromAutosave) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이전 데이터를 자동으로 복구했어요 ✅'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // 앱을 다시 열 때 알림 상태를 최신으로 재동기화
    if (s == AppLifecycleState.resumed) {
      NotificationService.instance
          .reconcile(widget.state.routines, widget.state.certs,
              widget.state.notifSettings)
          // reconcile의 cancelAll이 타이머 완료 알림을 지웠을 수 있어 다시 건다
          .then((_) => TimerService.instance.rearmNotification());
      // 백그라운드에서 타이머가 목표를 채웠는지 점검 → 완료면 자동 도장
      TimerService.instance.checkCompletion();
      // 다른 기기의 '가져오기 요청'도 이때 확인 (푸시 없이 열 때마다 폴링)
      _checkPullRequest();
    }
  }

  /// 다른 기기(웹 등)가 남긴 '기록 보내달라' 요청을 확인하고 승인 안내를 띄운다.
  Future<void> _checkPullRequest() async {
    if (_pullDialogOpen) return;
    final now = DateTime.now();
    if (now.difference(_lastPullCheck) < const Duration(seconds: 8)) return;
    _lastPullCheck = now;

    final req = await CloudSyncService.pendingPull(); // 내 요청·미로그인은 null
    if (req == null || !mounted) return;

    final routines = widget.state.routines;
    final certs = widget.state.certs;
    final timeLabel = req.requestedAt != null
        ? DateFormat('HH:mm').format(req.requestedAt!)
        : '';

    _pullDialogOpen = true;
    try {
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🌐 기록 가져오기 요청'),
          content: Text(
            '다른 기기(웹/폰)에서 이 계정으로 기록을 보내달라고 요청했어요'
            '${timeLabel.isNotEmpty ? ' ($timeLabel)' : ''}.\n\n'
            '${routines.isEmpty && certs.isEmpty ? '그런데 이 기기에는 보낼 기록이 없어요. 요청을 지울까요?' : '지금 이 기기의 기록(루틴 ${routines.length}개 · 인증 ${certs.length}개)을 보낼까요?\n요청한 기기가 자동으로 받아 가요.'}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('거절')),
            if (routines.isNotEmpty || certs.isNotEmpty)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('보내기')),
          ],
        ),
      );
      if (send == true && mounted) {
        try {
          await CloudSyncService.upload(routines, certs);
          await CloudSyncService.clearPull();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('보냈어요 — 요청한 기기가 곧 받아 가요 ✅')));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$e'.replaceFirst('Bad state: ', ''))));
          }
        }
      } else if (send == false) {
        await CloudSyncService.clearPull(); // 거절 → 요청 제거 (상대에게 알려짐)
      }
    } finally {
      _pullDialogOpen = false;
    }
  }

  /// 타이머 완료 콜백 — 인증 화면이 이미 떠 있으면 그 화면이 처리하므로 건너뛴다.
  void _onTimerComplete(String routineId, DateTime day) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || CertifyScreen.openCount > 0) return;
      final matches =
          widget.state.routines.where((r) => r.id == routineId);
      if (matches.isEmpty) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CertifyScreen(
          state: widget.state,
          routine: matches.first,
          day: day,
        ),
      ));
    });
  }

  Future<void> _exportBackup() async {
    final r = widget.state.routines.length;
    final c = widget.state.certs.length;
    if (r == 0 && c == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업할 데이터가 아직 없어요')));
      return;
    }
    try {
      await BackupService.exportAndShare(
          widget.state.routines, widget.state.certs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('백업 실패: $e')));
      }
    }
  }

  Future<void> _importBackup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('백업 불러오기'),
        content: const Text(
            '백업 파일의 내용으로 현재 데이터를 교체합니다.\n지금 이 폰에 있는 루틴·인증 기록은 사라져요. 계속할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('불러오기')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = await BackupService.pickAndRead();
      if (result == null) return; // 파일 선택 취소
      await widget.state.restoreAll(result.$1, result.$2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '복원 완료! 루틴 ${result.$1.length}개, 인증 ${result.$2.length}개를 불러왔어요 🎉')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('복원 실패: $e')));
      }
    }
  }

  /// 클라우드 백업 — 로그인한 계정에 기록을 보관/복원한다.
  /// 기기를 바꾸거나 브라우저 데이터를 지워도 되살릴 수 있다.
  Future<void> _openCloudSync() async {
    if (!await ensureWebLogin(context,
        reason: '기록을 계정에 보관하려면 로그인이 필요해요.')) {
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CloudSyncSheet(state: widget.state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['습관챌린지', '기록 · 추억'];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: _index == 0 ? const AppLogo(height: 32) : Text(titles[_index]),
        actions: [
          // 알림 설정 (아침 리마인더 시각 · 마감 임박 슬롯 · 테스트 알림)
          // 브라우저는 예약 알림 자체가 없어서 숨긴다
          if (!kIsWeb)
            IconButton(
              tooltip: '알림 설정',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotifSettingsScreen(state: widget.state),
                ),
              ),
            ),
          // 백업/이전 메뉴
          PopupMenuButton<String>(
            tooltip: '백업/이전',
            onSelected: (v) {
              if (v == 'export') _exportBackup();
              if (v == 'import') _importBackup();
              if (v == 'cloud') _openCloudSync();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'cloud',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('클라우드 백업 (계정에 보관)'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file),
                  title: Text('데이터 백업 (파일로 내보내기)'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download),
                  title: Text('백업 불러오기 (복원)'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeBody(state: widget.state),
          HistoryBody(state: widget.state),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AddRoutineScreen(state: widget.state)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('루틴'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: '오늘'),
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: '기록'),
        ],
      ),
    );
  }
}
