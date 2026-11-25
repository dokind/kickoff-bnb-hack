// Many rounds: the server calls under /rounds, the order of Home's slider,
// which round is selected and remembered, rounds opened by link, unlisted
// rounds and their registration, and the fallback to a server that knows
// one round only.
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/config.dart';
import 'package:pacepact/services/verifier_api.dart';

import 'support.dart';

/// 10 Dec 2026, 5 Dec 2026 and 20 Nov 2026 (already past at [fixedNow]),
/// in unix seconds.
const dec10 = 1796860800;
const dec5 = 1796428800;
const nov20 = 1795132800;

/// A server with the featured round A (closes 2 Dec) and three more: B
/// closes 10 Dec, C closes 5 Dec, D is launched.
FakeServer fourRounds() => FakeServer()
  ..more.addAll([
    roundJson(at: launcherB, name: 'Lumpini Striders', deadline: dec10),
    roundJson(at: launcherC, name: 'Night Owls', deadline: dec5),
    roundJson(at: launcherD, name: 'Old Guard', launched: true),
  ]);

List<String> ids(AppState state) => [for (final r in state.rounds) r.id];

void main() {
  group('the server, round by round', () {
    test(
      'GET /rounds reads the list: featured first, each round whole',
      () async {
        final server = fourRounds();
        final rounds = (await server.api.rounds())!;
        expect(server.requests, ['GET /rounds']);
        expect(
          [for (final r in rounds) r.launcher],
          [launcher, launcherB, launcherC, launcherD],
        );
        final first = rounds.first;
        expect(first.featured, isTrue);
        expect(first.name, 'Morning Movers');
        expect(first.deposit, usd(1000));
        expect(first.liquidityBps, 3000);
        expect(first.checkInGoal, 6);
        expect(first.totalCheckIns, 2);
        expect(first.memberCount, 3);
        expect(first.prizeNow, usd(2100));
        expect(first.poolQuoteNow, usd(900));
        expect(first.deadline.toUtc(), DateTime.utc(2026, 12, 2));
        expect(first.launched, isFalse);
        expect(first.phaseAt(fixedNow), RoundPhase.open);
        expect(first.phaseAt(DateTime.utc(2026, 12, 3)), RoundPhase.expired);
        expect(rounds[1].featured, isFalse);
        expect(rounds[3].phaseAt(fixedNow), RoundPhase.launched);
        expect(rounds[3].token, tokenAddress);
      },
    );

    test(
      'an unlisted round is left out of the list, not of its address',
      () async {
        final server = fourRounds()..unlisted.add(launcherC);
        final listed = (await server.api.rounds())!;
        expect([
          for (final r in listed) r.launcher,
        ], isNot(contains(launcherC)));
        final byAddress = (await server.api.roundAt(launcherC.toUpperCase()))!;
        expect(server.requests.last, 'GET /rounds/$launcherC');
        expect(byAddress.name, 'Night Owls');
        expect(byAddress.unlisted, isTrue);
        expect(byAddress.minSteps, 1000);
        expect((await server.api.roundAt(launcherB))!.unlisted, isFalse);
      },
    );

    test('an address our factory never made is "no round"', () async {
      expect(await FakeServer().api.roundAt(launcherD), isNull);
    });

    test('me, members and the check-in are asked of the round', () async {
      final server = fourRounds()
        ..meAt[launcherB] = meJson(daysOf: 4, streak: 3)
        ..membersAt[launcherB] = [
          {'address': testAddress, 'daysOf': 4, 'streak': 3},
        ];
      final api = server.api;
      final me = await api.me(testKey.address.with0x, launcher: launcherB);
      expect(me.daysOf, 4);
      expect((await api.members(launcher: launcherB)).single.daysOf, 4);
      await api.checkIn(
        testKey,
        launcher: launcherB,
        steps: 6214,
        source: 'self',
        now: fixedNow,
      );
      expect(server.requests, [
        'GET /rounds/$launcherB/me/$testAddress',
        'GET /rounds/$launcherB/members',
        'POST /rounds/$launcherB/checkin',
      ]);
      // The same body and the same signed text as the old /checkin.
      expect(server.bodies['/rounds/$launcherB/checkin'], {
        'address': testAddress,
        'steps': 6214,
        'source': 'self',
        'signature': VerifierApi.sign(
          testKey,
          'Cypher Run checkin $launcherB $today 6214',
        ),
      });
    });

    test('the registration text is pinned, and so is its signature', () {
      expect(
        VerifierApi.roundMessage(
          '0x1000000000000000000000000000000000000001',
          unlisted: true,
        ),
        'Cypher Run round 0x1000000000000000000000000000000000000001 unlisted',
      );
      expect(
        VerifierApi.roundMessage(
          '0xABCDEF0000000000000000000000000000000001',
          unlisted: false,
        ),
        'Cypher Run round 0xabcdef0000000000000000000000000000000001 listed',
      );
      // `cast wallet sign` with the test key.
      expect(
        VerifierApi.sign(
          testKey,
          VerifierApi.roundMessage(launcher, unlisted: true),
        ),
        '0xe2e6768d2efed0ab94413783fd691c92a240209b3124b9b91d1fb1122451bb82'
        '75fc4025c1e49cb95e5ba9c2eee36d741a5d80f790b29029827a9c41cb6397221b',
      );
      expect(
        VerifierApi.sign(
          testKey,
          VerifierApi.roundMessage(launcher, unlisted: false),
        ),
        '0xfb41d7e8122a0c797a79beb65dccb8acb0e490551b066b194718556d927e0893'
        '6b5cc38ea071d91ad3366004661ca4dc7180897d4aeb4210b790e90364c7a0db1b',
      );
    });

    test(
      'POST /rounds sends the launcher, the choice and the signature',
      () async {
        final server = fourRounds();
        final saved = await server.api.registerRound(
          testKey,
          launcher: launcherB.toUpperCase().replaceFirst('0X', '0x'),
          unlisted: true,
        );
        expect(saved, isTrue);
        expect(server.requests, ['POST /rounds']);
        expect(server.bodies['/rounds'], {
          'launcher': launcherB,
          'unlisted': true,
          'signature': VerifierApi.sign(
            testKey,
            'Cypher Run round $launcherB unlisted',
          ),
        });
        // The creator may call it again to change the setting.
        expect(
          await server.api.registerRound(
            testKey,
            launcher: launcherB,
            unlisted: false,
          ),
          isFalse,
        );
        expect(server.unlisted, isEmpty);
      },
    );

    test('a server from before /rounds answers null, not an error', () async {
      final server = FakeServer()..legacy = true;
      expect(await server.api.rounds(), isNull);
    });
  });

  group('invite links', () {
    test('the link is <web address>/#/r/<launcher>', () {
      expect(
        AppConfig.inviteLinkFor(
          'https://run.example/',
          '0xABCDEF0000000000000000000000000000000001',
        ),
        'https://run.example/#/r/0xabcdef0000000000000000000000000000000001',
      );
      expect(
        AppConfig.inviteLinkFor('https://run.example/app', launcher),
        'https://run.example/app/#/r/$launcher',
      );
      // A phone build made without WEB_BASE_URL has no link to hand out.
      expect(AppConfig.inviteLinkFor('', launcher), '');
    });

    test('a link, a route or a bare address gives the launcher', () {
      expect(
        AppConfig.launcherFromLink('https://run.example/#/r/$launcherB'),
        launcherB,
      );
      expect(AppConfig.launcherFromLink('/r/$launcherB'), launcherB);
      expect(
        AppConfig.launcherFromLink(
          ' 0xABCDEF0000000000000000000000000000000001 ',
        ),
        '0xabcdef0000000000000000000000000000000001',
      );
      expect(AppConfig.launcherFromLink('/r/0x1234'), isNull);
      expect(AppConfig.launcherFromLink('/r/${launcherB}ff'), isNull);
      expect(AppConfig.launcherFromLink('https://run.example/'), isNull);
    });
  });

  group('the slider\'s order', () {
    test(
      'featured, then joined, then open by deadline, launched, ended',
      () async {
        final server = fourRounds()
          ..more.add(
            roundJson(at: createdLauncher, name: 'Gone', deadline: nov20),
          );
        // This wallet has joined B (which closes last) and nothing else.
        final chain = FakeChain()
          ..others[launcherB] = FakeChain(isMember: true);
        final state = await makeState(server: server, chain: chain);

        expect(ids(state), [
          launcher, // featured
          launcherB, // joined
          launcherC, // open, closes 5 Dec
          launcherD, // launched
          createdLauncher, // closed 20 Nov with no launch
        ]);
        expect(state.joined, {launcherB});
        expect(state.isMemberOf(launcherB), isTrue);
        expect(state.isMemberOf(launcherC), isFalse);
        // The featured round is the one selected at first.
        expect(state.selected, launcher);
        expect(state.selectedIndex, 0);
        expect(state.round!.name, 'Morning Movers');
      },
    );

    test('open rounds nobody here joined go by nearest deadline', () async {
      final state = await makeState(server: fourRounds());
      expect(ids(state), [launcher, launcherC, launcherB, launcherD]);
    });

    test('joining a round moves it up; the selection stays on it', () async {
      final chain = FakeChain()..others[launcherB] = FakeChain();
      final state = await makeState(server: fourRounds(), chain: chain);
      state.select(launcherB);
      await state.refresh();
      expect(state.selectedIndex, 2);
      await state.payDeposit();
      expect(chain.asked, [launcherB], reason: 'the deposit went to B');
      expect(ids(state), [launcher, launcherB, launcherC, launcherD]);
      expect(state.selected, launcherB);
      expect(state.selectedIndex, 1);
      expect(state.isMember, isTrue);
      expect(state.stage, HomeStage.checkIn);
    });
  });

  group('the selected round', () {
    test('everything under the cards is read for that round', () async {
      final server = fourRounds()
        ..meAt[launcherB] = meJson(daysOf: 4, streak: 3)
        ..membersAt[launcherB] = [
          {'address': testAddress, 'daysOf': 4, 'streak': 3},
        ];
      final chain = FakeChain()
        ..others[launcherB] = FakeChain(isMember: true, daysOf: 4);
      final state = await makeState(server: server, chain: chain);
      expect(state.stage, HomeStage.join);
      expect(state.streak, 0);
      server.requests.clear();

      state.select(launcherB);
      // At once, from the list; the rest follows.
      expect(state.round!.name, 'Lumpini Striders');
      await pumpEventQueue();
      expect(
        server.requests,
        containsAll([
          'GET /rounds/$launcherB',
          'GET /rounds/$launcherB/me/$testAddress',
          'GET /rounds/$launcherB/members',
        ]),
      );
      expect(state.stage, HomeStage.checkIn);
      expect(state.streak, 3);
      expect(state.daysOf, 4);
      expect(state.members.single.address, testAddress);

      // The check-in is signed for, and sent to, that round.
      await state.checkIn(selfReported: 6214);
      expect(
        server.bodies['/rounds/$launcherB/checkin']!['signature'],
        VerifierApi.sign(testKey, 'Cypher Run checkin $launcherB $today 6214'),
      );
      expect(chain.asked, [launcherB]);
      expect(server.count('POST /checkin'), 0);

      // Back on the first round, its own numbers are there again.
      state.select(launcher);
      expect(state.stage, HomeStage.join);
      expect(state.streak, 0);
    });

    test('a round the person chose is remembered between launches', () async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: fourRounds(), store: store);
      state.select(launcherC);
      await pumpEventQueue();
      expect(store.rounds!['selected'], launcherC);

      final next = await makeState(server: fourRounds(), store: store);
      expect(next.selected, launcherC);
      expect(next.round!.name, 'Night Owls');
      // The order is still featured first: the slider opens on its 2nd card.
      expect(ids(next).first, launcher);
      expect(next.selectedIndex, 1);
    });

    test('a card that came by itself is not what is remembered', () async {
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: fourRounds(), store: store);
      state.select(launcherC, remember: false);
      await pumpEventQueue();
      expect(state.selected, launcherC);
      expect(store.rounds?['selected'], isNull);
      final next = await makeState(server: fourRounds(), store: store);
      expect(next.selected, launcher);
    });

    test('a remembered round that is gone falls back to the first', () async {
      final store = MemoryStore(
        key: testKey,
        onboarded: true,
        rounds: {'selected': createdLauncher, 'known': <dynamic>[]},
      );
      final state = await makeState(server: fourRounds(), store: store);
      expect(state.selected, launcher);
    });
  });

  group('a round opened by its link', () {
    test('an unlisted round is selected and stays on this device', () async {
      final server = fourRounds()..unlisted.add(launcherC);
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(server: server, store: store);
      expect(ids(state), isNot(contains(launcherC)));

      await state.openLink(launcherC.toUpperCase().replaceFirst('0X', '0x'));
      expect(state.selected, launcherC);
      expect(state.round!.name, 'Night Owls');
      expect(state.round!.unlisted, isTrue);
      expect(ids(state), contains(launcherC));
      expect(state.notice, isNull);

      // A new launch still shows it, though the public list does not.
      final next = await makeState(server: server, store: store);
      expect(ids(next), contains(launcherC));
      expect(next.selected, launcherC);
      expect(
        (await server.api.rounds())!.map((r) => r.id),
        isNot(contains(launcherC)),
      );
    });

    test('a link to a listed round just selects it', () async {
      final state = await makeState(server: fourRounds());
      await state.openLink(launcherB);
      expect(state.selected, launcherB);
    });

    test(
      'an address that is not a round: one sentence, nothing kept',
      () async {
        final store = MemoryStore(key: testKey, onboarded: true);
        final state = await makeState(server: FakeServer(), store: store);
        await state.openLink(launcherD);
        expect(state.selected, launcher);
        expect(state.notice, 'That link does not lead to a round.');
        expect(state.knownRound(launcherD), isNull);
        expect(store.rounds!['known'], isEmpty);
      },
    );

    test('before there is a wallet the link is kept for after', () async {
      final server = fourRounds()..unlisted.add(launcherC);
      final store = MemoryStore();
      final state = await makeState(
        wallet: false,
        server: server,
        store: store,
      );
      await state.openLink(launcherC);
      expect(state.selected, isNull);
      expect(server.requests, isEmpty);
      await state.completeOnboarding();
      await state.refresh();
      expect(state.selected, launcherC);
    });
  });

  group('starting a round', () {
    test(
      'it is on this wallet\'s slider at once, before the server knows',
      () async {
        // The server has not found the round on chain yet.
        final server = FakeServer();
        final store = MemoryStore(key: testKey, onboarded: true);
        final state = await makeState(server: server, store: store);
        final address = await state.createRound(
          name: 'Lumpini Striders',
          deposit: usd(500),
          liquidityBps: 5000,
          checkInGoal: 12,
          deadline: fixedNow.add(const Duration(days: 7)),
          unlisted: true,
        );
        expect(address, createdLauncher);
        expect(ids(state), [launcher, createdLauncher]);
        expect(state.selected, createdLauncher);
        final round = state.round!;
        expect(round.name, 'Lumpini Striders');
        expect(round.deposit, usd(500));
        expect(round.checkInGoal, 12);
        expect(round.unlisted, isTrue);

        // The server was asked to save the choice and could not yet.
        expect(server.count('POST /rounds'), greaterThan(0));
        final known = state.knownRound(createdLauncher)!;
        expect(known.registered, isFalse);
        expect(
          known.registerError,
          contains('not found this round on chain yet'),
        );

        // Kept on the device: a new launch still has it.
        final next = await makeState(server: server, store: store);
        expect(ids(next), contains(createdLauncher));
        expect(next.selected, createdLauncher);
        expect(next.round!.name, 'Lumpini Striders');

        // Once the server has found it, the next read registers it by itself.
        server.more.add(
          roundJson(at: createdLauncher, name: 'Lumpini Striders'),
        );
        await next.refresh();
        expect(next.knownRound(createdLauncher)!.registered, isTrue);
        expect(server.unlisted, {createdLauncher});
        expect(
          server.bodies['/rounds']!['signature'],
          VerifierApi.sign(
            testKey,
            'Cypher Run round $createdLauncher unlisted',
          ),
        );
        // Unlisted: not in the public list, still on its creator's slider.
        expect((await server.api.rounds())!.map((r) => r.id), [launcher]);
        expect(ids(next), contains(createdLauncher));
        expect(next.round!.unlisted, isTrue);
      },
    );

    test('the creator can change the listing afterwards', () async {
      final server = FakeServer()
        ..more.add(roundJson(at: createdLauncher, name: 'Lumpini Striders'));
      server.unlisted.add(createdLauncher);
      final state = await makeState(server: server);
      await state.createRound(
        name: 'Lumpini Striders',
        deposit: usd(1000),
        liquidityBps: 3000,
        checkInGoal: 6,
        deadline: fixedNow.add(const Duration(days: 7)),
        unlisted: true,
      );
      expect(state.knownRound(createdLauncher)!.unlisted, isTrue);
      await state.registerRound(createdLauncher, unlisted: false);
      expect(server.unlisted, isEmpty);
      expect(server.bodies['/rounds']!['unlisted'], isFalse);
      expect(state.knownRound(createdLauncher)!.unlisted, isFalse);
      expect(state.round!.unlisted, isFalse);
    });

    test('a refusal from the server is its own sentence', () async {
      final server = FakeServer()
        ..registerStatus = 401
        ..registerError = {
          'error': 'bad_signature',
          'message': 'Only the wallet that started the round can change this.',
        };
      final state = await makeState(server: server);
      await expectLater(
        state.registerRound(launcher, unlisted: true),
        throwsA(
          predicate((e) => '$e'.contains('Only the wallet that started')),
        ),
      );
      expect(state.knownRound(launcher)!.registered, isFalse);
    });
  });

  group('a server that knows one round only', () {
    test('GET /rounds answers 404: the old calls carry the app', () async {
      final server = FakeServer()..legacy = true;
      final chain = FakeChain(isMember: true);
      final state = await makeState(server: server, chain: chain);

      expect(state.legacyServer, isTrue);
      expect(ids(state), [launcher]);
      expect(state.rounds.single.featured, isTrue);
      expect(state.selected, launcher);
      expect(state.round!.name, 'Morning Movers');
      expect(state.round!.minSteps, 1000);
      expect(state.stage, HomeStage.checkIn);
      expect(state.members, hasLength(2));
      expect(
        server.requests,
        containsAll([
          'GET /rounds',
          'GET /round',
          'GET /me/$testAddress',
          'GET /members',
        ]),
      );

      await state.checkIn(selfReported: 6214);
      expect(server.count('POST /checkin'), 1);
      expect(
        server.bodies['/checkin']!['signature'],
        VerifierApi.sign(testKey, 'Cypher Run checkin $launcher $today 6214'),
      );
      expect(chain.calls, ['checkIn 20782']);
      expect(state.stage, HomeStage.checkedIn);
      // Nothing but GET /rounds was asked under /rounds.
      expect(server.requests.where((r) => r.contains('/rounds')).toSet(), {
        'GET /rounds',
      });
    });

    test('no round on the old server is still "no round"', () async {
      final server = FakeServer()
        ..legacy = true
        ..round = null;
      final state = await makeState(server: server);
      expect(state.stage, HomeStage.noRound);
      expect(state.rounds, isEmpty);
    });

    test(
      'a round started here still shows, and registers after the update',
      () async {
        final server = FakeServer()..legacy = true;
        final store = MemoryStore(key: testKey, onboarded: true);
        final state = await makeState(server: server, store: store);
        await state.createRound(
          name: 'Lumpini Striders',
          deposit: usd(1000),
          liquidityBps: 3000,
          checkInGoal: 6,
          deadline: fixedNow.add(const Duration(days: 7)),
        );
        await pumpEventQueue();
        expect(ids(state), [launcher, createdLauncher]);
        expect(state.selected, createdLauncher);
        final known = state.knownRound(createdLauncher)!;
        expect(known.registered, isFalse);
        expect(
          known.registerError,
          contains('does not keep a list of rounds yet'),
        );

        // The old server signs for its current round only.
        state.joined.add(createdLauncher);
        await expectLater(
          state.checkIn(selfReported: 6214),
          throwsA(
            predicate((e) => '$e'.contains('cannot sign check-ins for this')),
          ),
        );
        expect(server.count('POST /checkin'), 0);

        // The server is updated: the same build moves to the new calls and
        // registers the round.
        server
          ..legacy = false
          ..more.add(roundJson(at: createdLauncher, name: 'Lumpini Striders'));
        await state.refresh();
        expect(state.legacyServer, isFalse);
        expect(state.knownRound(createdLauncher)!.registered, isTrue);
        expect(ids(state), [launcher, createdLauncher]);
      },
    );

    test('the app moves back to the old calls if the server does', () async {
      final server = fourRounds();
      final state = await makeState(server: server);
      expect(ids(state), hasLength(4));
      server.legacy = true;
      await state.refresh();
      expect(state.legacyServer, isTrue);
      expect(ids(state), [launcher]);
    });
  });
}
