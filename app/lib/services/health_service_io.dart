import 'dart:io' show Platform;

import 'package:health/health.dart';

import 'health_service.dart';

HealthService createHealthService() => DeviceHealthService();

/// Phone build: reads the health store through the `health` package.
class DeviceHealthService implements HealthService {
  final Health _health = Health();
  bool _configured = false;

  @override
  bool get available => true;

  @override
  String get source => Platform.isIOS ? 'healthkit' : 'healthconnect';

  @override
  Future<bool> requestAccess() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    return _health.requestAuthorization(
      [HealthDataType.STEPS],
      permissions: [HealthDataAccess.READ],
    );
  }

  @override
  Future<int> stepsToday() async {
    if (!await requestAccess()) {
      throw Exception('Allow access to your steps to check in.');
    }
    final now = DateTime.now();
    final utc = now.toUtc();
    final dayStart = DateTime.utc(utc.year, utc.month, utc.day).toLocal();
    final steps = await _health.getTotalStepsInInterval(
      dayStart,
      now,
      includeManualEntry: false,
    );
    return steps ?? 0;
  }
}
