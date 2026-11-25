// Finding the server on chain: OriginRegistry's `origin()` read with a raw
// eth_call, the host checked and kept, and the one retry of a server call
// after the server moved.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacepact/config.dart';
import 'package:pacepact/services/origin_service.dart';
import 'package:pacepact/services/verifier_api.dart';

/// `cast abi-encode 'f(string)' 'cypher-run-demo.trycloudflare.com'`.
const encodedDemo =
    '0x'
    '0000000000000000000000000000000000000000000000000000000000000020'
    '0000000000000000000000000000000000000000000000000000000000000021'
    '6379706865722d72756e2d64656d6f2e747279636c6f7564666c6172652e636f'
    '6d00000000000000000000000000000000000000000000000000000000000000';

/// What OriginRegistry answered on BSC testnet before the server first set
/// it (`cast call <registry> 'origin()'`): the empty string.
const encodedEmpty =
    '0x'
    '0000000000000000000000000000000000000000000000000000000000000020'
    '0000000000000000000000000000000000000000000000000000000000000000';

/// [text] encoded the way `origin()` returns it.
String encode(String text) {
  final bytes = utf8.encode(text);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final padded = hex.padRight(((hex.length + 63) ~/ 64) * 64, '0');
  return '0x${32.toRadixString(16).padLeft(64, '0')}'
      '${bytes.length.toRadixString(16).padLeft(64, '0')}$padded';
}

http.Response rpcResult(String hex) =>
    http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': hex}), 200);

/// An RPC endpoint whose registry holds [hosts], one per reading (the last
/// one stays). Counts the readings and keeps each request body.
class FakeRpc {
  FakeRpc(this.hosts);
  final List<String> hosts;
  int calls = 0;
  final bodies = <Map<String, dynamic>>[];

  late final client = MockClient((r) async {
    bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
    final host = hosts[calls < hosts.length ? calls : hosts.length - 1];
    calls++;
    return rpcResult(encode(host));
  });
}

OriginService originWith(
  http.Client client, {
  OriginCache? cache,
  List<String> rpcUrls = const ['https://rpc.test'],
  Duration timeout = const Duration(seconds: 4),
  Duration refreshGap = Duration.zero,
}) => OriginService(
  client: client,
  rpcUrls: rpcUrls,
  cache: cache ?? MemoryOriginCache(),
  timeout: timeout,
  refreshGap: refreshGap,
);

void main() {
  group('origin() decoding', () {
    test('a real encoded string', () {
      expect(
        OriginService.decodeAbiString(encodedDemo),
        'cypher-run-demo.trycloudflare.com',
      );
      expect(OriginService.decodeAbiString(encodedEmpty), '');
      expect(OriginService.decodeAbiString(encode('a.example')), 'a.example');
    });

    test('an answer that is not one ABI string is refused', () {
      expect(OriginService.decodeAbiString('0x'), isNull);
      expect(OriginService.decodeAbiString('0x1234'), isNull);
      expect(OriginService.decodeAbiString('nothex' * 30), isNull);
      // A length longer than the data.
      expect(
        OriginService.decodeAbiString(
          '0x'
          '0000000000000000000000000000000000000000000000000000000000000020'
          '00000000000000000000000000000000000000000000000000000000000000ff',
        ),
        isNull,
      );
      // An offset past the end.
      expect(
        OriginService.decodeAbiString(
          '0x'
          '0000000000000000000000000000000000000000000000000000000000000400'
          '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        isNull,
      );
    });

    test('the selector is origin()', () {
      // `cast sig 'origin()'`.
      expect(OriginService.originSelector, '0x938b5f32');
      expect(
        AppConfig.originRegistry,
        '0xb9aD45Dc177C801f10670F2aac03B467f1C367d2',
      );
    });
  });

  group('host check', () {
    test('only a plain host name is taken', () {
      for (final good in [
        'cypher-run-demo.trycloudflare.com',
        'api.example.org',
        'localhost',
        'A1-b2.Example.COM',
      ]) {
        expect(OriginService.isValidHost(good), isTrue, reason: good);
      }
      for (final bad in [
        'evil.com/path',
        'a b',
        'https://x',
        '',
        'x:8080',
        'user@x.com',
        'user:pass@x.com',
        'x.com?q=1',
        'x.com#f',
        '-x.com',
        'x-.com',
        'x..com',
        '.x.com',
        'x.com.',
        ' x.com',
        'x.com\n',
        'a' * 64,
      ]) {
        expect(OriginService.isValidHost(bad), isFalse, reason: bad);
      }
    });
  });

  group('reading the chain', () {
    test('one eth_call of origin() to the registry', () async {
      final rpc = FakeRpc(['cypher-run-demo.trycloudflare.com']);
      final origin = originWith(rpc.client);
      expect(await origin.resolve(), 'cypher-run-demo.trycloudflare.com');
      expect(origin.fresh, isTrue);
      expect(origin.apiBase, 'https://cypher-run-demo.trycloudflare.com/api');
      expect(rpc.calls, 1);
      final body = rpc.bodies.single;
      expect(body['method'], 'eth_call');
      expect(body['params'], [
        {'to': AppConfig.originRegistry, 'data': '0x938b5f32'},
        'latest',
      ]);
    });

    test('the next RPC URL is tried when one fails', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add(r.url.host);
        if (r.url.host == 'down.test') {
          throw http.ClientException('Failed to fetch', r.url);
        }
        if (r.url.host == 'broken.test') return http.Response('oops', 500);
        return rpcResult(encodedDemo);
      });
      final origin = originWith(
        client,
        rpcUrls: const [
          'https://down.test',
          'https://broken.test',
          'https://up.test',
        ],
      );
      expect(await origin.resolve(), 'cypher-run-demo.trycloudflare.com');
      expect(asked, ['down.test', 'broken.test', 'up.test']);
    });

    test('a slow RPC is given up after the timeout', () async {
      final never = Completer<http.Response>();
      final origin = originWith(
        MockClient((r) => never.future),
        rpcUrls: const ['https://slow.test', 'https://slow2.test'],
        timeout: const Duration(milliseconds: 50),
      );
      final watch = Stopwatch()..start();
      expect(await origin.resolve(), '');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(origin.fresh, isFalse);
    });

    test('a first RPC that hangs leaves time for the second', () async {
      final never = Completer<http.Response>();
      final asked = <String>[];
      final origin = originWith(
        MockClient((r) {
          asked.add(r.url.host);
          if (r.url.host == 'hang.test') return never.future;
          return Future.value(rpcResult(encode('next.example')));
        }),
        rpcUrls: const ['https://hang.test', 'https://up.test'],
        timeout: const Duration(milliseconds: 200),
      );
      expect(await origin.resolve(), 'next.example');
      expect(asked, ['hang.test', 'up.test']);
      expect(origin.fresh, isTrue);
    });

    test('a value that is not a plain host is not used', () async {
      final rpc = FakeRpc(['evil.com/path']);
      final origin = originWith(rpc.client);
      expect(await origin.resolve(), '');
      expect(origin.apiBase, '');
    });

    test('the host is kept on the device and used when the chain is '
        'out of reach', () async {
      final cache = MemoryOriginCache();
      final first = originWith(
        FakeRpc(['cypher-run-demo.trycloudflare.com']).client,
        cache: cache,
      );
      await first.resolve();
      expect(cache.host, 'cypher-run-demo.trycloudflare.com');

      final offline = originWith(
        MockClient(
          (r) async => throw http.ClientException('Failed to fetch', r.url),
        ),
        cache: cache,
      );
      expect(await offline.resolve(), 'cypher-run-demo.trycloudflare.com');
      expect(offline.fresh, isFalse);

      // Nothing set on chain yet (empty): the kept host stands.
      final empty = originWith(
        MockClient((r) async => rpcResult(encodedEmpty)),
        cache: cache,
      );
      expect(await empty.resolve(), 'cypher-run-demo.trycloudflare.com');

      // A kept value that is not a plain host is ignored.
      final bad = originWith(
        MockClient((r) async => rpcResult(encodedEmpty)),
        cache: MemoryOriginCache('evil.com/path'),
      );
      expect(await bad.resolve(), '');
    });

    test('a fresh host replaces the kept one', () async {
      final cache = MemoryOriginCache('old-name.trycloudflare.com');
      final origin = originWith(
        FakeRpc(['new-name.trycloudflare.com']).client,
        cache: cache,
      );
      expect(origin.host, '');
      expect(await origin.resolve(), 'new-name.trycloudflare.com');
      expect(cache.host, 'new-name.trycloudflare.com');
    });

    test('refresh reads the chain at most once per gap, and calls made '
        'together share one reading', () async {
      final rpc = FakeRpc(['a.example', 'b.example', 'c.example']);
      final origin = originWith(
        rpc.client,
        refreshGap: const Duration(minutes: 1),
      );
      await origin.resolve();
      expect(rpc.calls, 1);
      final both = await Future.wait([origin.refresh(), origin.refresh()]);
      expect(both, ['b.example', 'b.example']);
      expect(rpc.calls, 2);
      expect(await origin.refresh(), 'b.example');
      expect(rpc.calls, 2);
    });
  });

  group('resolution order', () {
    test('build value, tunnel page, chain (fresh, else kept), none', () async {
      final origin = originWith(
        MockClient((r) async => rpcResult(encodedEmpty)),
        cache: MemoryOriginCache('kept.trycloudflare.com'),
      );
      await origin.resolve();
      String base({String define = '', bool web = true, String page = ''}) =>
          AppConfig.apiBaseFor(
            define: define,
            web: web,
            pageOrigin: page,
            originHost: origin.host,
          );
      expect(
        base(define: 'https://dev.example', page: 'https://dokind.github.io'),
        'https://dev.example',
      );
      expect(
        base(page: 'https://old.trycloudflare.com'),
        'https://old.trycloudflare.com/api',
      );
      expect(
        base(page: 'https://dokind.github.io'),
        'https://kept.trycloudflare.com/api',
      );
      expect(base(web: false), 'https://kept.trycloudflare.com/api');

      final fresh = originWith(
        FakeRpc(['fresh.trycloudflare.com']).client,
        cache: MemoryOriginCache('kept.trycloudflare.com'),
      );
      await fresh.resolve();
      expect(
        AppConfig.apiBaseFor(
          define: '',
          web: false,
          pageOrigin: '',
          originHost: fresh.host,
        ),
        'https://fresh.trycloudflare.com/api',
      );

      final none = originWith(MockClient((r) async => rpcResult(encodedEmpty)));
      await none.resolve();
      expect(
        AppConfig.apiBaseFor(
          define: '',
          web: false,
          pageOrigin: '',
          originHost: none.host,
        ),
        '',
      );
    });
  });

  group('one retry after the server moved', () {
    const members = [
      {'address': '0x1000000000000000000000000000000000000001', 'daysOf': 2},
    ];

    /// The server behind [live]; any other host answers [goneStatus] the
    /// way a stopped Cloudflare quick tunnel does.
    MockClient serverAt(
      List<String> asked, {
      required String live,
      int goneStatus = 530,
    }) => MockClient((r) async {
      asked.add('${r.url.host}${r.url.path}');
      if (r.url.host == live) return http.Response(jsonEncode(members), 200);
      return http.Response('<html>error code: 1033</html>', goneStatus);
    });

    VerifierApi apiWith(MockClient server, OriginService origin) => VerifierApi(
      client: server,
      baseUrl: origin.apiBase,
      relocate: () async {
        await origin.refresh();
        return origin.apiBase;
      },
    );

    test('530, the host changes on chain, the same call answers 200 '
        'from the new host', () async {
      final rpc = FakeRpc(['old.trycloudflare.com', 'new.trycloudflare.com']);
      final origin = originWith(rpc.client);
      await origin.resolve();
      final asked = <String>[];
      final api = apiWith(
        serverAt(asked, live: 'new.trycloudflare.com'),
        origin,
      );

      final list = await api.members();
      expect(list.single.daysOf, 2);
      expect(asked, [
        'old.trycloudflare.com/api/members',
        'new.trycloudflare.com/api/members',
      ]);
      expect(rpc.calls, 2);

      // The next call goes straight to the new host.
      await api.members();
      expect(asked.last, 'new.trycloudflare.com/api/members');
      expect(asked.length, 3);
      expect(rpc.calls, 2);
    });

    test(
      '502 and 503 from the tunnel and a failed connection count too',
      () async {
        for (final status in [502, 503]) {
          final rpc = FakeRpc(['old.example', 'new.example']);
          final origin = originWith(rpc.client);
          await origin.resolve();
          final asked = <String>[];
          final api = apiWith(
            serverAt(asked, live: 'new.example', goneStatus: status),
            origin,
          );
          expect((await api.members()).single.daysOf, 2);
          expect(asked.length, 2, reason: '$status');
        }

        final rpc = FakeRpc(['old.example', 'new.example']);
        final origin = originWith(rpc.client);
        await origin.resolve();
        final asked = <String>[];
        final api = apiWith(
          MockClient((r) async {
            asked.add(r.url.host);
            if (r.url.host == 'old.example') {
              throw http.ClientException('Failed host lookup', r.url);
            }
            return http.Response(jsonEncode(members), 200);
          }),
          origin,
        );
        expect((await api.members()).single.daysOf, 2);
        expect(asked, ['old.example', 'new.example']);
      },
    );

    test('no loop: one retry at most, then one plain sentence', () async {
      final rpc = FakeRpc(['old.example', 'new.example', 'newer.example']);
      final origin = originWith(rpc.client);
      await origin.resolve();
      final asked = <String>[];
      final api = apiWith(serverAt(asked, live: 'nowhere.example'), origin);
      await expectLater(
        api.members(),
        throwsA(
          isA<VerifierException>().having(
            (e) => e.message,
            'message',
            VerifierApi.unreachable,
          ),
        ),
      );
      expect(asked, ['old.example/api/members', 'new.example/api/members']);
      expect(rpc.calls, 2);
    });

    test('the same host on chain: no retry', () async {
      final rpc = FakeRpc(['old.example']);
      final origin = originWith(rpc.client);
      await origin.resolve();
      final asked = <String>[];
      final api = apiWith(serverAt(asked, live: 'nowhere.example'), origin);
      await expectLater(api.members(), throwsA(isA<VerifierException>()));
      expect(asked, ['old.example/api/members']);
    });

    test("the server's own 503 (with its error body) is not a move", () async {
      final rpc = FakeRpc(['old.example', 'new.example']);
      final origin = originWith(rpc.client);
      await origin.resolve();
      final asked = <String>[];
      final api = apiWith(
        MockClient((r) async {
          asked.add(r.url.host);
          return http.Response(
            jsonEncode({
              'error': 'chain_unavailable',
              'message': 'could not read the round on chain; try again',
            }),
            503,
          );
        }),
        origin,
      );
      await expectLater(
        api.members(),
        throwsA(
          isA<VerifierException>().having(
            (e) => e.code,
            'code',
            'chain_unavailable',
          ),
        ),
      );
      expect(asked, ['old.example']);
      expect(rpc.calls, 1);
    });

    test('no address at start: looked up once on the first call', () async {
      final rpc = FakeRpc(['', 'new.example']);
      final origin = originWith(rpc.client);
      await origin.resolve();
      expect(origin.apiBase, '');
      final asked = <String>[];
      final api = apiWith(serverAt(asked, live: 'new.example'), origin);
      expect((await api.members()).single.daysOf, 2);
      expect(asked, ['new.example/api/members']);

      final stillNone = originWith(FakeRpc(['']).client);
      await stillNone.resolve();
      final api2 = apiWith(serverAt(asked, live: 'new.example'), stillNone);
      await expectLater(
        api2.members(),
        throwsA(
          isA<VerifierException>().having(
            (e) => e.message,
            'message',
            'This build has no server address yet.',
          ),
        ),
      );
    });
  });
}
