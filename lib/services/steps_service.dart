import 'package:health/health.dart';

/// 걸음수 자동 검증 — Health Connect(안드로이드)/HealthKit(iOS)에서
/// 오늘 0시부터 지금까지의 걸음수를 읽어온다.
class StepsService {
  static final StepsService instance = StepsService._();
  StepsService._();

  final Health _health = Health();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// 권한 요청 → 오늘 걸음수 반환. 권한 거부/미지원이면 null.
  Future<int?> todaySteps() async {
    await _ensureConfigured();
    const types = [HealthDataType.STEPS];

    final granted = await _health.requestAuthorization(types);
    if (!granted) return null;

    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return _health.getTotalStepsInInterval(midnight, now);
  }
}
