import 'package:flutter/foundation.dart';

import 'health_service_stub.dart'
    if (dart.library.io) 'health_service_io.dart'
    as impl;

/// Reads today's steps from Apple Health / Health Connect. Steps typed in by
/// hand are left out, so what is sent was recorded by a device.
///
/// The phone build reads the health store (health_service_io.dart). A browser
/// has no health store, so the web build gets a stand-in whose [available] is
/// false (health_service_stub.dart) and the `health` package is never
/// compiled for the web. There the check-in is a number the person types:
/// self-reported, for the testnet demo only.
///
/// The status API (what a read found, whether the app asked before, opening
/// the Health app) is [HealthAccess]. Both real services implement it; use
/// it through [HealthStatus], which also works for a service that only
/// implements this class.
abstract class HealthService {
  factory HealthService() => impl.createHealthService();

  /// False where there is no health store to read (the web build).
  bool get available;

  /// What the server is told the steps came from: "healthkit" on an iPhone,
  /// "healthconnect" on Android, "self" where there is no health store.
  String get source;

  /// Asks for permission to read steps. Returns whether it was given.
  /// Always false where there is no health store.
  ///
  /// On an iPhone the answer says only that the question was put: HealthKit
  /// never tells an app whether reading was allowed, and after the first
  /// answer it returns without showing anything.
  Future<bool> requestAccess();

  /// Steps recorded since the current UTC day began. Days are counted in UTC
  /// on the chain and on the server, so the same window is read here.
  Future<int> stepsToday();
}

/// What a read of today's steps found.
enum StepsResult {
  /// Steps were read.
  ok,

  /// No step samples today. On an iPhone this is also what a read the
  /// person did not allow looks like: HealthKit hides the difference.
  noData,

  /// Android without Health Connect (or with one too old to use).
  notInstalled,

  /// The read failed.
  error,

  /// No health store on this device (the web build).
  unavailable,
}

/// One read of today's steps: the [result] and, when it is [StepsResult.ok],
/// the [steps].
@immutable
class StepsRead {
  const StepsRead._(this.result, [this.steps = 0, this.message]);

  const StepsRead.ok(int steps) : this._(StepsResult.ok, steps);
  const StepsRead.error([String? message])
    : this._(StepsResult.error, 0, message);

  static const noData = StepsRead._(StepsResult.noData);
  static const notInstalled = StepsRead._(StepsResult.notInstalled);
  static const unavailable = StepsRead._(StepsResult.unavailable);

  final StepsResult result;
  final int steps;

  /// What went wrong, for [StepsResult.error]. Not shown as is.
  final String? message;

  bool get isOk => result == StepsResult.ok;

  @override
  bool operator ==(Object other) =>
      other is StepsRead &&
      other.result == result &&
      other.steps == steps &&
      other.message == message;

  @override
  int get hashCode => Object.hash(result, steps, message);

  @override
  String toString() => result == StepsResult.ok
      ? 'StepsRead.ok($steps)'
      : 'StepsRead.${result.name}';
}

/// The status API of a health store, beside [HealthService].
abstract class HealthAccess {
  /// The app has asked for access on this device before.
  Future<bool> askedBefore();

  /// Reads today's steps and says what it found. Never throws.
  ///
  /// When [ask] is true the permission is asked for first; after the first
  /// answer an iPhone shows nothing, so asking again is harmless.
  Future<StepsRead> readSteps({bool ask = true});

  /// Asks for access to steps (the first time: the system's sheet).
  Future<bool> connect();

  /// Where the person can change the access themselves. iPhone: opens the
  /// Health app. Android: Health Connect's permission screen. Returns false
  /// when nothing could be opened.
  Future<bool> openSettings();

  /// Android: opens the store page of Health Connect. Does nothing elsewhere.
  Future<void> installHealthConnect();
}

/// Which health store a device has, for the words on screen.
enum HealthStore { none, appleHealth, healthConnect }

/// The status API on any [HealthService]: forwarded to [HealthAccess] when
/// the service implements it, else worked out from [HealthService.stepsToday]
/// and [HealthService.requestAccess].
extension HealthStatus on HealthService {
  HealthAccess? get _access {
    final Object self = this;
    return self is HealthAccess ? self : null;
  }

  /// The store, named the way the person knows it. Follows the platform the
  /// app is drawn for, as onboarding does.
  HealthStore get store => !available
      ? HealthStore.none
      : defaultTargetPlatform == TargetPlatform.iOS
      ? HealthStore.appleHealth
      : HealthStore.healthConnect;

  /// "Apple Health" or "Health Connect".
  String get storeName =>
      store == HealthStore.appleHealth ? 'Apple Health' : 'Health Connect';

  bool get isAppleHealth => store == HealthStore.appleHealth;

  Future<bool> askedBefore() async {
    if (!available) return false;
    try {
      return await _access?.askedBefore() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<StepsRead> readSteps({bool ask = true}) async {
    if (!available) return StepsRead.unavailable;
    final access = _access;
    if (access != null) return access.readSteps(ask: ask);
    try {
      final steps = await stepsToday();
      return steps > 0 ? StepsRead.ok(steps) : StepsRead.noData;
    } catch (e) {
      return StepsRead.error(e.toString());
    }
  }

  Future<bool> connect() async {
    if (!available) return false;
    final access = _access;
    try {
      return access != null ? await access.connect() : await requestAccess();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openSettings() async {
    if (!available) return false;
    try {
      return await _access?.openSettings() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    if (!available) return;
    try {
      await _access?.installHealthConnect();
    } catch (_) {}
  }
}
