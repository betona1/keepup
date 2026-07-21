import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models/notif_settings.dart';
import '../services/notification_service.dart';

/// 알림 설정 (전역) — 아침 리마인더 시각 + 마감 임박 슬롯 on/off.
/// 혼자 쓰는 앱이라 루틴별이 아닌 앱 전체 하나의 설정으로 단순하게 둔다.
class NotifSettingsScreen extends StatefulWidget {
  final AppState state;
  const NotifSettingsScreen({super.key, required this.state});

  @override
  State<NotifSettingsScreen> createState() => _NotifSettingsScreenState();
}

class _NotifSettingsScreenState extends State<NotifSettingsScreen> {
  late NotifSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.state.notifSettings;
  }

  Future<void> _apply(NotifSettings next) async {
    setState(() => _s = next);
    await widget.state.updateNotifSettings(next);
  }

  Future<void> _pickMorning() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.morningHour, minute: _s.morningMinute),
      helpText: '아침 리마인더 시각',
    );
    if (picked != null) {
      await _apply(
          _s.copyWith(morningHour: picked.hour, morningMinute: picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final anySlot = _s.activeOffsets.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 32 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _sectionLabel(context, '아침 리마인더'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.wb_sunny_outlined, color: cs.primary),
                  title: const Text('아침 리마인더 시각'),
                  subtitle: const Text(
                      '결과형 루틴 마감 3일 전부터 매일 이 시각에 알려요'),
                  trailing: Text(
                    _s.morningLabel,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  onTap: _pickMorning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel(context, '마감 임박 알림'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.timelapse),
                  title: const Text('마감 3시간 전'),
                  value: _s.slot180,
                  onChanged: (v) => _apply(_s.copyWith(slot180: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.hourglass_bottom),
                  title: const Text('마감 1시간 전'),
                  value: _s.slot60,
                  onChanged: (v) => _apply(_s.copyWith(slot60: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.alarm),
                  title: const Text('마감 30분 전'),
                  value: _s.slot30,
                  onChanged: (v) => _apply(_s.copyWith(slot30: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              anySlot
                  ? '미인증 상태일 때만 울리고, 인증하면 그날 알림은 자동으로 사라져요.'
                  : '⚠️ 마감 임박 알림을 모두 껐어요. 마감을 놓치기 쉬우니 하나쯤은 켜두길 권해요.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: anySlot ? cs.onSurfaceVariant : cs.error,
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await NotificationService.instance.scheduleTestNotification();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('1분 뒤 테스트 알림이 울립니다. 앱을 꺼도 울려요!')));
              }
            },
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('테스트 알림 보내기 (1분 뒤)'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
