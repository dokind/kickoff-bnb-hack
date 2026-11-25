import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Where the server's host is kept between visits. A parameter so tests can
/// hold it in memory.
abstract class OriginCache {
  Future<String?> read();
  Future<void> write(String host);
}

/// The device's own storage: the platform keystore on a phone, the site's
/// storage in a browser (flutter_secure_storage keeps it in localStorage
/// there). Any failure reads as "nothing kept".
class SecureOriginCache implements OriginCache {
  static const _name = 'cypherrun.origin.host';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String host) async {
    try {
      await _storage.write(key: _name, value: host);
    } catch (_) {
      // Not kept: the next start reads the chain again.
    }
  }
}

/// A cache that lives as long as the app does.
class MemoryOriginCache implements OriginCache {
  MemoryOriginCache([this.host]);
  String? host;

  @override
  Future<String?> read() async => host;

  @override
  Future<void> write(String host) async => this.host = host;
}

/// Finds the server on chain. The server writes its current host to
/// OriginRegistry (../contracts/src/OriginRegistry.sol) whenever it moves;
/// this reads `origin()` with a plain `eth_call`, so no build carries the
/// server's address and the server can move without a rebuild.
///
/// Only a plain host name is taken (letters, digits, dots and hyphens). The
/// API is then `https://<host>/api`.
class OriginService {
  OriginService({
    http.Client? client,
    List<String>? rpcUrls,
    this.registry = AppConfig.originRegistry,
    this.timeout = const Duration(seconds: 4),
    this.refreshGap = const Duration(seconds: 15),
    OriginCache? cache,
    DateTime Function()? clock,
  }) : _http = client ?? http.Client(),
       rpcUrls = rpcUrls ?? AppConfig.rpcUrls,
       _cache = cache ?? SecureOriginCache(),
       _clock = clock ?? DateTime.now;

  /// The one the app uses.
  static final OriginService instance = OriginService();

  final http.Client _http;
  final List<String> rpcUrls;
  final String registry;

  /// The longest one reading of the chain may take, across every RPC URL.
  final Duration timeout;

  /// [refresh] reads the chain at most once in this time.
  final Duration refreshGap;

  final OriginCache _cache;
  final DateTime Function() _clock;

  /// `cast sig 'origin()'`.
  static const String originSelector = '0x938b5f32';

  String? _fresh;
  String? _cached;
  bool _cacheRead = false;
  DateTime? _lastRefresh;
  Future<String>? _running;

  /// The host read from the chain in this run, else the one kept on the
  /// device, else empty.
  String get host => _fresh ?? _cached ?? '';

  /// True when [host] was read from the chain in this run.
  bool get fresh => _fresh != null;

  /// The API's base URL for [host], or empty.
  String get apiBase => host.isEmpty ? '' : apiBaseForHost(host);

  static String apiBaseForHost(String host) => 'https://$host/api';

  /// Reads the kept host, then the chain. Never throws and never takes much
  /// longer than [timeout]. Returns [host].
  Future<String> resolve() => _running ??= _resolve().whenComplete(() {
    _running = null;
  });

  /// [resolve] again after a server call failed. Reads the chain at most
  /// once per [refreshGap]; calls made while one reading runs share it.
  Future<String> refresh() {
    if (_running != null) return _running!;
    final now = _clock();
    final last = _lastRefresh;
    if (last != null && now.difference(last) < refreshGap) {
      return Future.value(host);
    }
    _lastRefresh = now;
    return resolve();
  }

  Future<String> _resolve() async {
    if (!_cacheRead) {
      _cacheRead = true;
      final kept = await _cache.read();
      if (kept != null && isValidHost(kept)) _cached = kept.toLowerCase();
    }
    final read = await fetch();
    if (read != null) {
      _fresh = read;
      if (read != _cached) {
        _cached = read;
        await _cache.write(read);
      }
    }
    return host;
  }

  /// `origin()` from the chain, checked. Null when no RPC answered within
  /// [timeout], or the registry holds nothing usable (empty today).
  Future<String?> fetch() async {
    final deadline = _clock().add(timeout);
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_call',
      'params': [
        {'to': registry, 'data': originSelector},
        'latest',
      ],
    });
    for (var i = 0; i < rpcUrls.length; i++) {
      final url = rpcUrls[i];
      final left = deadline.difference(_clock());
      if (left <= Duration.zero) break;
      // A URL that hangs must not eat the whole budget: each one gets an
      // even share of what is left, so the next one is still asked.
      final share = left ~/ (rpcUrls.length - i);
      try {
        final r = await _http
            .post(
              Uri.parse(url),
              headers: {'content-type': 'application/json'},
              body: body,
            )
            .timeout(share);
        if (r.statusCode != 200) continue;
        final answer = jsonDecode(r.body);
        if (answer is! Map || answer['result'] is! String) continue;
        final text = decodeAbiString(answer['result'] as String);
        if (text == null) continue;
        // The registry answered. Empty (nothing set yet) or not a plain host
        // name: no fresh host, so the one kept on the device stands.
        final value = text.trim().toLowerCase();
        return isValidHost(value) ? value : null;
      } catch (_) {
        // This URL is down or slow: try the next one.
      }
    }
    return null;
  }

  /// A plain host name: labels of letters, digits and hyphens joined by
  /// dots. No scheme, path, port, credentials or spaces.
  static bool isValidHost(String text) {
    if (text.isEmpty || text.length > 253) return false;
    final label = r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?';
    return RegExp('^$label(?:\\.$label)*\$').hasMatch(text);
  }

  /// The one string an `eth_call` of a `string` getter returns, from its
  /// hex answer. Null when the answer is not one ABI-encoded string.
  static String? decodeAbiString(String hex) {
    var h = hex.trim();
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.length < 128 || h.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
    BigInt word(int at) =>
        BigInt.parse(h.substring(at * 2, at * 2 + 64), radix: 16);
    final offset = word(0);
    if (offset > BigInt.from(h.length ~/ 2 - 32)) return null;
    final at = offset.toInt();
    final length = word(at);
    final start = (at + 32) * 2;
    if (length > BigInt.from((h.length - start) ~/ 2)) return null;
    final end = start + length.toInt() * 2;
    final bytes = <int>[
      for (var i = start; i < end; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ];
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
