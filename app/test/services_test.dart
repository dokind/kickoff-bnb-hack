// The encodings the app relies on, pinned against the contracts' own
// vectors and `cast`, and the server client against a mock server.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacepact/config.dart';
import 'package:pacepact/services/abi.dart';
import 'package:pacepact/services/chain_service.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/services/wallet_store.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import 'support.dart';

String hex(List<int> bytes) => bytesToHex(bytes, include0x: true);

String selector(ContractAbi abi, String fn) => hex(
  ChainService.callData(abi, fn, _zeroArgs[fn] ?? const []).sublist(0, 4),
);

final _zero = EthereumAddress.fromHex(AppConfig.zeroAddress);
final _zeroArgs = <String, List<dynamic>>{
  'sponsor': [BigInt.zero],
  'checkIn': [BigInt.zero, Uint8List(0)],
  'mint': [_zero, BigInt.zero],
  'approve': [_zero, BigInt.zero],
  'newLauncher': [_zero, Uint8List(0)],
  'claimable': [_zero],
  'checkedInOn': [_zero, BigInt.zero],
};

void main() {
  group('ABI encodings', () {
    test('function selectors match `cast sig`', () {
      expect(selector(checkInLauncherAbi, 'join'), '0xb688a363');
      expect(selector(checkInLauncherAbi, 'sponsor'), '0xb6cce5e2');
      expect(selector(checkInLauncherAbi, 'checkIn'), '0xb1674d67');
      expect(selector(checkInLauncherAbi, 'launch'), '0x01339c21');
      expect(selector(checkInLauncherAbi, 'refund'), '0x590e1ae3');
      expect(selector(checkInLauncherAbi, 'checkedInOn'), '0x5c288990');
      expect(selector(streakVaultAbi, 'claim'), '0x4e71d92d');
      expect(selector(streakVaultAbi, 'claimable'), '0x402914f5');
      expect(selector(erc20Abi, 'mint'), '0x40c10f19');
      expect(selector(erc20Abi, 'approve'), '0x095ea7b3');
      expect(selector(portalAbi, 'newLauncher'), '0x2d9bc0de');
    });

    test('checkIn(day, signature) is the calldata `cast calldata` builds', () {
      // The contracts' worked vector: day 20782 and the attester's signature
      // (test_checkInSignatureVector in ../contracts).
      const signature =
          '0xea91a378e84c0366ee93151c23b319e4ace635db74a3175e585737d4cd9cd525'
          '6dc9ee53d41e88ce0ac5b09c04f13e85612648bf490fad7c1e32814fc11b7cdc1c';
      final data = ChainService.callData(checkInLauncherAbi, 'checkIn', [
        BigInt.from(20782),
        hexToBytes(signature),
      ]);
      expect(
        hex(data),
        '0xb1674d67'
        '000000000000000000000000000000000000000000000000000000000000512e'
        '0000000000000000000000000000000000000000000000000000000000000040'
        '0000000000000000000000000000000000000000000000000000000000000041'
        'ea91a378e84c0366ee93151c23b319e4ace635db74a3175e585737d4cd9cd525'
        '6dc9ee53d41e88ce0ac5b09c04f13e85612648bf490fad7c1e32814fc11b7cdc'
        '1c00000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test('mint(address, amount) mints the deposit to the wallet itself', () {
      final data = ChainService.callData(erc20Abi, 'mint', [
        EthereumAddress.fromHex('0x2000000000000000000000000000000000000002'),
        usd(1000),
      ]);
      expect(
        hex(data),
        '0x40c10f19'
        '0000000000000000000000002000000000000000000000000000000000000002'
        '00000000000000000000000000000000000000000000003635c9adc5dea00000',
      );
    });

    test('the round config is the 480 bytes the factory decodes', () {
      // ROUND_CONFIG_VECTOR in ../contracts/test/CheckInLauncher.t.sol.
      final data = ChainService.encodeRoundConfig(
        name: 'Morning Movers',
        symbol: 'MOVE',
        salt: Uint8List(32)..[31] = 0xab,
        deposit: usd(1000),
        liquidityBps: 3000,
        checkInGoal: 6,
        deadline: DateTime.fromMillisecondsSinceEpoch(1796342400 * 1000),
        attester: '0xFCAd0B19bB29D4674531d6f115237E16AfCE377c',
      );
      expect(data.length, 480);
      expect(
        hex(data),
        '0x'
        '0000000000000000000000000000000000000000000000000000000000000020'
        '0000000000000000000000000000000000000000000000000000000000000120'
        '0000000000000000000000000000000000000000000000000000000000000160'
        '00000000000000000000000000000000000000000000000000000000000001a0'
        '00000000000000000000000000000000000000000000000000000000000000ab'
        '00000000000000000000000000000000000000000000003635c9adc5dea00000'
        '0000000000000000000000000000000000000000000000000000000000000bb8'
        '0000000000000000000000000000000000000000000000000000000000000006'
        '000000000000000000000000000000000000000000000000000000006b120280'
        '000000000000000000000000fcad0b19bb29d4674531d6f115237e16afce377c'
        '000000000000000000000000000000000000000000000000000000000000000e'
        '4d6f726e696e67204d6f76657273000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000004'
        '4d4f564500000000000000000000000000000000000000000000000000000000'
        '0000000000000000000000000000000000000000000000000000000000000000',
      );
    });

    test('the launcher is read from CheckInLauncherCreated', () {
      expect(
        ChainService.createdTopic,
        '0xed94e0617397203451d10ef884497281481cf818778db8ba4555231d1928856b',
      );
      const factory = '0x7000000000000000000000000000000000000007';
      FilterEvent log(String address, String topic0) => FilterEvent(
        address: EthereumAddress.fromHex(address),
        topics: [
          topic0,
          '0x000000000000000000000000${launcher.substring(2)}',
          '0x000000000000000000000000${testAddress.substring(2)}',
        ],
      );
      expect(
        ChainService.launcherFromLogs([
          log(AppConfig.portal, ChainService.createdTopic),
          log(factory, '0x${'11' * 32}'),
          log(factory, ChainService.createdTopic),
        ], factory),
        launcher,
      );
      expect(ChainService.launcherFromLogs([], factory), isNull);
    });

    test('every transaction has an explicit gas limit; launch 7,000,000', () {
      expect(AppConfig.gasPriceWei, BigInt.from(1000000000));
      expect(GasLimit.launch, 7000000);
      expect(GasLimit.newLauncher, 1000000);
      expect(GasLimit.claim, 500000);
      expect(GasLimit.join, 250000);
      expect(GasLimit.checkIn, 200000);
      // The wallet must hold the whole limit before the launch is sent.
      expect(
        AppConfig.launchGasWei > BigInt.from(7000000) * AppConfig.gasPriceWei,
        isTrue,
      );
    });
  });

  group('launch salt', () {
    test('a mined salt gives a token address ending in 7777', () {
      final seed = Uint8List.fromList(List.generate(32, (i) => i));
      final salt = mineSalt(seed);
      final input = Uint8List(85)
        ..[0] = 0xff
        ..setRange(1, 21, hexToBytes(AppConfig.portal))
        ..setRange(21, 53, salt)
        ..setRange(53, 85, hexToBytes(AppConfig.tokenInitCodeHash));
      expect(hex(keccak256(input)).endsWith('7777'), isTrue);
      expect(salt.sublist(0, 28), seed.sublist(0, 28));
    });

    test('the browser path finds the same salt in chunks', () async {
      final seed = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      expect(await mineSaltAsync(seed, web: true), mineSalt(seed));
    });

    test('a round name becomes a short symbol', () {
      expect(symbolFor('Morning Movers'), 'MM');
      expect(symbolFor('Lumpini'), 'LUMPIN');
      expect(symbolFor('  6am club, Bangkok!  '), '6CB');
      expect(symbolFor('…'), 'ROUND');
    });
  });

  group('signed texts', () {
    test('check-in: lower-case launcher, UTC day, whole steps', () {
      expect(
        VerifierApi.checkInMessage(
          '0x1000000000000000000000000000000000000001',
          today,
          6214,
        ),
        'Cypher Run checkin 0x1000000000000000000000000000000000000001 '
        '2026-11-25 6214',
      );
      expect(
        VerifierApi.checkInMessage(
          '0xABCDEF0000000000000000000000000000000001',
          today,
          1,
        ),
        startsWith('Cypher Run checkin 0xabcdef'),
      );
    });

    test('personal_sign matches `cast wallet sign` for the test key', () {
      expect(testKey.address.with0x.toLowerCase(), testAddress);
      expect(
        VerifierApi.sign(
          testKey,
          VerifierApi.checkInMessage(launcher, today, 6214),
        ),
        '0xbe5e14862e2dc6280ef3e223922bc904426546c063fc0dd45aadacd5d72a810a'
        '793954c447e70f4a4635300757543dacb3c936abb5bb6b958ca05dddb6bb1edc1c',
      );
      expect(
        VerifierApi.sign(testKey, VerifierApi.faucetMessage(testAddress)),
        '0x27f14d6ae2fae90c9b299470c6f7b506982a744fd3dcd37eafebd292d760deb8'
        '1d269fd8f50023efdccc7ba6be924a7e6b6ea7521220ce9ab1824c766d72463f1c',
      );
    });
  });

  group('VerifierApi', () {
    test(
      'GET /round reads the round; amounts are whole-unit strings',
      () async {
        final server = FakeServer();
        final round = (await server.api.round())!;
        expect(server.requests, ['GET /round']);
        expect(round.launcher, launcher);
        expect(round.name, 'Morning Movers');
        expect(round.deposit, usd(1000));
        expect(round.liquidityBps, 3000);
        expect(round.depositToPool, usd(300));
        expect(round.depositToPrize, usd(700));
        expect(round.checkInGoal, 6);
        expect(round.totalCheckIns, 2);
        expect(round.memberCount, 3);
        expect(round.poolQuoteNow, usd(900));
        expect(round.prizeNow, usd(2100));
        expect(round.deadline.toUtc(), DateTime.utc(2026, 12, 2));
        expect(round.launched, isFalse);
        expect(round.token, isNull);
        expect(round.vault, isNull);
        expect(round.flapUrl, isNull);
        expect(round.minSteps, 1000);
      },
    );

    test('amounts are read as decimals, numbers or base units', () {
      expect(amountFromJson('1500.000000000000000000'), usd(1500));
      expect(amountFromJson('356.2'), usd(356.2));
      expect(amountFromJson(700), usd(700));
      expect(amountFromJson('1000000000000000000000'), usd(1000));
      expect(amountFromJson('0'), BigInt.zero);
      expect(amountFromJson(null), BigInt.zero);
      expect(amountFromJson('soon'), BigInt.zero);
    });

    test(
      'a launched round carries the token, the vault and the Flap link',
      () async {
        final server = FakeServer()..round = roundJson(launched: true);
        final round = (await server.api.round())!;
        expect(round.launched, isTrue);
        expect(round.token, tokenAddress);
        expect(round.vault, vault);
        expect(round.flapUrl, 'https://flap.sh/bnb-testnet/$tokenAddress');
      },
    );

    test('404 no_round is "no round", not an error', () async {
      final server = FakeServer()..round = null;
      expect(await server.api.round(), isNull);
    });

    test('GET /me/:address is asked in lower case', () async {
      final server = FakeServer()
        ..me = meJson(
          daysOf: 3,
          streak: 2,
          checkedInToday: true,
          days: ['2026-11-22', '2026-11-24', today],
        );
      final me = await server.api.me(testKey.address.with0x);
      expect(server.requests, ['GET /me/$testAddress']);
      expect(me.member, isTrue);
      expect(me.daysOf, 3);
      expect(me.streak, 2);
      expect(me.bestStreak, 2);
      expect(me.checkedInToday, isTrue);
      expect(me.days, ['2026-11-22', '2026-11-24', today]);
      expect(me.claimableTokens, BigInt.zero);
    });

    test('GET /members reads a plain list (or a wrapped one)', () async {
      final server = FakeServer();
      final members = await server.api.members();
      expect(members.length, 2);
      expect(members.first.daysOf, 2);
      expect(members.first.streak, 2);
      expect(members.first.checkedInToday, isTrue);

      final wrapped = VerifierApi(
        baseUrl: 'http://server.test',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'members': [
                {'address': testAddress.toUpperCase(), 'daysOf': '4'},
              ],
            }),
            200,
          ),
        ),
      );
      final one = (await wrapped.members()).single;
      expect(one.address, testAddress);
      expect(one.daysOf, 4);
    });

    test(
      'the check-in goes to the round: address, steps, source, signature',
      () async {
        final server = FakeServer();
        final ticket = await server.api.checkIn(
          testKey,
          launcher: launcher,
          steps: 6214,
          source: 'self',
          now: fixedNow,
        );
        expect(server.requests, ['POST /rounds/$launcher/checkin']);
        expect(server.bodies['/rounds/$launcher/checkin'], {
          'address': testAddress,
          'steps': 6214,
          'source': 'self',
          'signature': VerifierApi.sign(
            testKey,
            'Cypher Run checkin $launcher $today 6214',
          ),
        });
        expect(ticket.day, today);
        expect(ticket.dayIndex, 20782);
        expect(ticket.attesterSignature, attesterSignature);
      },
    );

    test('a check-in answer without a real signature is refused', () async {
      final server = FakeServer()
        ..checkIn = {
          'day': today,
          'dayIndex': 20782,
          'attesterSignature': '0x',
        };
      expect(
        () => server.api.checkIn(
          testKey,
          launcher: launcher,
          steps: 6214,
          source: 'self',
          now: fixedNow,
        ),
        throwsA(
          isA<VerifierException>().having(
            (e) => e.message,
            'message',
            contains('did not sign'),
          ),
        ),
      );
    });

    test('the server\'s sentence is shown; a bare code is not', () async {
      final server = FakeServer()
        ..checkInStatus = 400
        ..checkIn = {
          'error': 'too_few_steps',
          'message': 'A check-in needs at least 1000 steps.',
        };
      Future<void> go() => server.api.checkIn(
        testKey,
        launcher: launcher,
        steps: 12,
        source: 'self',
        now: fixedNow,
      );
      await expectLater(
        go,
        throwsA(
          isA<VerifierException>()
              .having(
                (e) => e.message,
                'message',
                'A check-in needs at least 1000 steps.',
              )
              .having((e) => e.code, 'code', 'too_few_steps')
              .having((e) => e.status, 'status', 400),
        ),
      );
      server.checkIn = {'error': 'not_member'};
      await expectLater(
        go,
        throwsA(
          isA<VerifierException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Cypher Run\'s server'),
              isNot(contains('not_member')),
            ),
          ),
        ),
      );
    });

    test(
      'POST /faucet signs "Cypher Run faucet <address>" in lower case',
      () async {
        final server = FakeServer();
        final result = await server.api.faucet(testKey);
        expect(result.funded, isTrue);
        expect(result.tx, '0xf1');
        expect(server.bodies['/faucet'], {
          'address': testAddress,
          'signature': VerifierApi.sign(
            testKey,
            'Cypher Run faucet $testAddress',
          ),
        });
      },
    );

    test('no connection is one sentence that names no host', () async {
      final server = FakeServer()..offline = true;
      for (final call in <Future<void> Function()>[
        server.api.round,
        () => server.api.me(testAddress),
        server.api.members,
        () => server.api.faucet(testKey),
      ]) {
        await expectLater(
          call,
          throwsA(
            isA<VerifierException>().having(
              (e) => e.message,
              'message',
              VerifierApi.unreachable,
            ),
          ),
        );
      }
      expect(VerifierApi.unreachable, isNot(contains('http')));
      expect(VerifierApi.unreachable, isNot(contains('localhost')));
    });

    test('an answer that is not JSON reads as unreachable', () async {
      final api = VerifierApi(
        baseUrl: 'http://server.test',
        client: MockClient(
          (r) async => http.Response('<html>hello</html>', 200),
        ),
      );
      expect(
        api.members,
        throwsA(
          isA<VerifierException>().having(
            (e) => e.message,
            'message',
            VerifierApi.unreachable,
          ),
        ),
      );
    });

    test('a phone build without a server address says so', () {
      final api = VerifierApi(
        baseUrl: '',
        client: MockClient((r) async => http.Response('{}', 200)),
      );
      expect(
        api.round,
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

  group('config', () {
    test('the web build calls the API on its own origin under /api', () {
      expect(
        AppConfig.apiBaseFor(
          define: '',
          web: true,
          pageOrigin: 'https://cypherrun.example',
        ),
        'https://cypherrun.example/api',
      );
      // A build value pointing at this machine is never used by a hosted page.
      expect(
        AppConfig.apiBaseFor(
          define: 'http://localhost:8787',
          web: true,
          pageOrigin: 'https://cypherrun.example',
        ),
        'https://cypherrun.example/api',
      );
      expect(
        AppConfig.apiBaseFor(
          define: 'http://localhost:8787/',
          web: true,
          pageOrigin: 'http://localhost:5000',
        ),
        'http://localhost:8787',
      );
      expect(
        AppConfig.apiBaseFor(
          define: 'https://x.example/api/',
          web: false,
          pageOrigin: '',
        ),
        'https://x.example/api',
      );
      expect(AppConfig.apiBaseFor(define: '', web: false, pageOrigin: ''), '');
    });

    test('missing build values are named by their --dart-define', () {
      expect(
        AppConfig.missingFrom(
          checkInLauncherFactory: AppConfig.zeroAddress,
          streakVaultFactory: 'nope',
          attesterAddress: testAddress,
        ),
        ['CHECKIN_LAUNCHER_FACTORY', 'STREAK_VAULT_FACTORY'],
      );
      expect(
        AppConfig.missingFrom(
          checkInLauncherFactory: launcher,
          streakVaultFactory: vault,
          attesterAddress: AppConfig.zeroAddress,
        ),
        ['ATTESTER_ADDRESS'],
      );
    });

    test('the product name is one constant', () {
      expect(AppConfig.productName, 'Cypher Run');
      expect(AppConfig.heroLine, 'RUN THE\nSTAKES.');
      expect(AppConfig.chainId, 97);
      expect(
        AppConfig.quoteToken,
        '0x190C989D5665a0e404B444b53CAE9AbCfb600157',
      );
      expect(AppConfig.flapToken, 'https://flap.sh/bnb-testnet/');
    });
  });

  group('wallet key', () {
    test('a pasted key is read with or without 0x', () {
      expect(parsePrivateKey(testKeyHex)!.address, testKey.address);
      expect(parsePrivateKey('  0x$testKeyHex\n')!.address, testKey.address);
      expect(parsePrivateKey('0x1234'), isNull);
      expect(parsePrivateKey('z' * 64), isNull);
      expect(parsePrivateKey('0' * 64), isNull);
      expect(parsePrivateKey(''), isNull);
    });
  });
}
