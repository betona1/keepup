import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'app_state.dart';
import 'theme.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'widgets/marquee_text.dart';
import 'services/backup_service.dart';
import 'screens/history_screen.dart';
import 'screens/add_routine_screen.dart';
import 'screens/notif_settings_screen.dart';

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

  final storage = await StorageService.create();
  final state = AppState(storage);
  await state.load();

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
      title: '습관 챌린지',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: RootScreen(state: state),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      NotificationService.instance.reconcile(
          widget.state.routines,
          widget.state.certs,
          widget.state.notifSettings);
    }
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

  @override
  Widget build(BuildContext context) {
    final titles = ['습관챌린지', '기록 · 추억'];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: _index == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titles[0]),
                  // 내가 선언한 습관들이 전광판처럼 흐른다
                  ListenableBuilder(
                    listenable: widget.state,
                    builder: (context, _) {
                      final names = widget.state.routines
                          .map((r) => r.title)
                          .join('  ·  ');
                      if (names.isEmpty) return const SizedBox.shrink();
                      return MarqueeText(
                        text: names,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              )
            : Text(titles[_index]),
        actions: [
          // 알림 설정 (아침 리마인더 시각 · 마감 임박 슬롯 · 테스트 알림)
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
            },
            itemBuilder: (_) => const [
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
