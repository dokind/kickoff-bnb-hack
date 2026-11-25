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
abstract class HealthService {
  factory HealthService() => impl.createHealthService();

  /// False where there is no health store to read (the web build).
  bool get available;

  /// What the server is told the steps came from: "healthkit" on an iPhone,
  /// "healthconnect" on Android, "self" where there is no health store.
  String get source;

  /// Asks for permission to read steps. Returns whether it was given.
  /// Always false where there is no health store.
  Future<bool> requestAccess();

  /// Steps recorded since the current UTC day began. Days are counted in UTC
  /// on the chain and on the server, so the same window is read here.
  Future<int> stepsToday();
}
