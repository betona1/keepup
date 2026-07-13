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
import 'screens/history_screen.dart';
import 'screens/add_routine_screen.dart';

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
      NotificationService.instance
          .reconcile(widget.state.routines, widget.state.certs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['오늘의 습관', '기록 · 추억'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          // [임시] 알림 동작 확인 버튼 — 실기기 테스트 끝나면 제거
          IconButton(
            tooltip: '테스트 알림 (1분 뒤)',
            icon: const Icon(Icons.notification_add_outlined),
            onPressed: () async {
              await NotificationService.instance.scheduleTestNotification();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('1분 뒤 테스트 알림이 울립니다. 앱을 꺼도 울려요!')),
                );
              }
            },
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
