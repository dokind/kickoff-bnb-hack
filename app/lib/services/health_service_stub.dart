import 'health_service.dart';

HealthService createHealthService() => _NoHealthService();

/// Web build: there is no health store. The check-in is self-reported.
class _NoHealthService implements HealthService, HealthAccess {
  @override
  bool get available => false;

  @override
  String get source => 'self';

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<int> stepsToday() =>
      throw Exception('A browser cannot read steps. Type them in instead.');

  @override
  Future<bool> askedBefore() async => false;

  @override
  Future<StepsRead> readSteps({bool ask = true}) async => StepsRead.unavailable;

  @override
  Future<bool> connect() async => false;

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<void> installHealthConnect() async {}
}
