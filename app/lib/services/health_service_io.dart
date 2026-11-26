import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:url_launcher/url_launcher.dart';

import 'health_service.dart';

HealthService createHealthService() => DeviceHealthService();

/// Phone build: reads the health store through the `health` package.
///
/// What the package (and the platforms) allow, and so what this does:
///  * iPhone: HealthKit never says whether reading was allowed. Asking
///    shows the system sheet the first time only and then returns at once;
///    a read that was not allowed simply finds no samples. So a read of
///    nothing is [StepsResult.noData], never "denied", and only the person
///    can turn access back on, in the Health app.
///  * Android: Health Connect says whether steps are allowed, and the app
///    can ask again. It may be missing or too old ([StepsResult.notInstalled]),
///    in which case the store page can be opened.
class DeviceHealthService implements HealthService, HealthAccess {
  DeviceHealthService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final Health _health = Health();
  final FlutterSecureStorage _storage;
  bool _configured = false;

  /// Set once the app has asked for access on this device. Kept beside the
  /// wallet key, in the same storage.
  static const _askedName = 'cypher.health.asked';

  static const _types = [HealthDataType.STEPS];
  static const _read = [HealthDataAccess.READ];

  @override
  bool get available => true;

  @override
  String get source => Platform.isIOS ? 'healthkit' : 'healthconnect';

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Health Connect is installed and recent enough. Always true on iOS.
  Future<bool> _installed() async {
    if (!Platform.isAndroid) return true;
    final status = await _health.getHealthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  Future<void> _markAsked() async {
    try {
      await _storage.write(key: _askedName, value: 'true');
    } catch (_) {
      // Only changes a button's words; never worth failing a check-in for.
    }
  }

  @override
  Future<bool> askedBefore() async {
    try {
      return await _storage.read(key: _askedName) == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestAccess() async {
    await _configure();
    if (!await _installed()) return false;
    if (Platform.isAndroid) {
      // The package warns that asking can block when access is already
      // given, so look first. (On iOS this answer is always unknown.)
      if (await _health.hasPermissions(_types, permissions: _read) == true) {
        await _markAsked();
        return true;
      }
    }
    final given = await _health.requestAuthorization(
      _types,
      permissions: _read,
    );
    await _markAsked();
    return given;
  }

  @override
  Future<bool> connect() => requestAccess();

  @override
  Future<StepsRead> readSteps({bool ask = true}) async {
    try {
      await _configure();
      if (!await _installed()) return StepsRead.notInstalled;
      if (ask) {
        final given = await requestAccess();
        // Android knows: steps are not allowed, so there is nothing to read.
        if (!given && Platform.isAndroid) return StepsRead.noData;
      }
      final now = DateTime.now();
      final utc = now.toUtc();
      final dayStart = DateTime.utc(utc.year, utc.month, utc.day).toLocal();
      final steps = await _health.getTotalStepsInInterval(
        dayStart,
        now,
        includeManualEntry: false,
      );
      // iOS: no samples (or reading not allowed) is 0. Android: null when
      // the read was refused.
      if (steps == null || steps <= 0) return StepsRead.noData;
      return StepsRead.ok(steps);
    } catch (e) {
      return StepsRead.error(e.toString());
    }
  }

  @override
  Future<int> stepsToday() async {
    final read = await readSteps();
    switch (read.result) {
      case StepsResult.ok:
        return read.steps;
      case StepsResult.noData:
        return 0;
      case StepsResult.notInstalled:
        throw Exception(
          'Health Connect is not on this phone. Install it to read your '
          'steps.',
        );
      case StepsResult.error:
      case StepsResult.unavailable:
        throw Exception('Your steps could not be read. Try again.');
    }
  }

  @override
  Future<bool> openSettings() async {
    if (Platform.isIOS) {
      // launchUrl, not canLaunchUrl: asking first would need the scheme in
      // LSApplicationQueriesSchemes; opening it does not.
      if (await _launch('x-apple-health://')) return true;
      // The app's own page in Settings, if the Health app is missing.
      return _launch('app-settings:');
    }
    await _configure();
    if (!await _installed()) {
      await _health.installHealthConnect();
      return true;
    }
    // Health Connect's own permission screen. After two refusals Android
    // stops showing it; then the person allows Steps in Health Connect.
    return requestAccess();
  }

  @override
  Future<void> installHealthConnect() async {
    if (!Platform.isAndroid) return;
    await _health.installHealthConnect();
  }

  Future<bool> _launch(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
