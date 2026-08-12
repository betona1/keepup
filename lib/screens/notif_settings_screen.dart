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
  /// 안내 문구에 쓰는 시스템 알림 채널 이름 (설정 앱에서 이 이름으로 보인다)
  static const _channelLabel = '습관 마감 알람';

  late NotifSettings _s;
  AlarmStatus? _status;

  @override
  void initState() {
    super.initState();
    _s = widget.state.notifSettings;
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final s = await NotificationService.instance.diagnose();
    if (mounted) setState(() => _status = s);
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
          _statusCard(context),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          _sectionLabel(context, '알람 소리'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.volume_up_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('앱 전용 알람음이 1분간 울려요',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '· 알람 볼륨으로 재생돼 무음 모드에서도 들립니다.\n'
                    '· [알람 끄기]를 누르면 즉시 멈추고, 안 누르면 1분 뒤 저절로 멈춥니다.\n'
                    '· 알람을 놓쳐도 소리 없는 카드가 알림창에 조용히 남습니다.\n'
                    '· 앱을 완전히 종료하거나 화면이 꺼져 있어도 울립니다.',
                    style: TextStyle(
                        fontSize: 12, height: 1.6, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final error = await NotificationService.instance
                            .scheduleTestNotification();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error == null
                                ? '10초 뒤 알람이 울립니다. 지금 앱을 꺼두고 확인해 보세요!'
                                : '알람 예약에 실패했어요: $error'),
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      },
                      icon: const Icon(Icons.alarm_on_rounded, size: 18),
                      label: const Text('알람 테스트 (10초 뒤)'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '소리가 안 들린다면: 휴대폰 설정 → 앱 → Log Challenge → 알림 →'
                    ' "$_channelLabel" 채널의 소리가 켜져 있는지, 그리고 알람 볼륨이'
                    ' 0이 아닌지 확인해 주세요.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 알람 상태 자가진단 — "왜 안 울리지?"를 앱 안에서 바로 확인할 수 있게 한다.
  Widget _statusCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = _status;
    if (st == null) {
      return const SizedBox(height: 4);
    }
    final ok = st.healthy && st.pendingCount > 0;
    final color = ok ? cs.tertiary : cs.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.verified_rounded : Icons.error_outline_rounded,
                    color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok ? '알람 정상 — 예약 ${st.pendingCount}건' : '알람을 확인해 주세요',
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                ),
                IconButton(
                  tooltip: '다시 점검',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: _refreshStatus,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in st.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $p',
                    style: TextStyle(fontSize: 12, height: 1.5, color: cs.error)),
              ),
            if (st.problems.isEmpty && st.pendingCount == 0)
              Text(
                '· 예약된 알람이 없어요. 오늘 인증을 이미 마쳤거나, 루틴이 없을 때는 정상입니다.',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
              ),
            if (ok)
              Text(
                '알림 권한 · 정확한 알람 권한 · 알람음까지 모두 정상입니다.',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
