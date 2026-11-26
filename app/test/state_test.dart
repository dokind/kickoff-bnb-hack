// AppState: which action Home shows, the gas wait, the check-in in two
// steps, and what happens when the server or the chain cannot be read.
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/widgets/gauges.dart' show DayState;

import 'support.dart';

/// Has no gas for the first [emptyReads] balance reads, then 0.03 tBNB: a
/// faucet transfer that takes a moment to be mined.
class SlowFaucetChain extends FakeChain {
  SlowFaucetChain(this.emptyReads) : super(bnb: 0);
  int emptyReads;
  int reads = 0;

  @override
  Future<BigInt> bnbBalance(String address) async {
    reads++;
    return reads > emptyReads ? usd(0.03) : BigInt.zero;
  }
}

void main() {
  group('Home stage', () {
    test('no round open', () async {
      final state = await makeState(server: FakeServer()..round = null);
      expect(state.stage, HomeStage.noRound);
      expect(state.round, isNull);
    });

    test('server unreachable: one sentence, then it recovers', () async {
      final server = FakeServer()..offline = true;
      final state = await makeState(server: server);
      expect(state.stage, HomeStage.error);
      expect(state.roundError, VerifierApi.unreachable);
      server.offline = false;
      await state.refresh();
      expect(state.roundError, isNull);
      expect(state.stage, HomeStage.join);
    });

    test('not a member: join', () async {
      final state = await makeState();
      expect(state.stage, HomeStage.join);
      expect(state.deposit, usd(1000));
      expect(state.isMember, isFalse);
    });

    test('member, not checked in: check in', () async {
      final state = await makeState(chain: FakeChain(isMember: true));
      expect(state.stage, HomeStage.checkIn);
    });

    test('member, checked in today: checked in', () async {
      final state = await makeState(
        chain: FakeChain(isMember: true, checkedInToday: true, daysOf: 3),
        server: FakeServer()..me = meJson(daysOf: 3, streak: 3),
      );
      expect(state.stage, HomeStage.checkedIn);
      expect(state.daysOf, 3);
      expect(state.streak, 3);
    });

    test('bar full: launch, for a member and for anyone else', () async {
      for (final member in [true, false]) {
        final state = await makeState(
          chain: FakeChain(isMember: member, totalCheckIns: 6, pool: 1500),
          server: FakeServer()..round = roundJson(totalCheckIns: 6),
        );
        expect(state.goalReached, isTrue);
        expect(state.stage, HomeStage.launch);
        expect(state.poolShort, BigInt.zero);
      }
    });

    test(
      'the chain\'s count fills the bar before the server catches up',
      () async {
        final state = await makeState(
          chain: FakeChain(isMember: true, totalCheckIns: 6, pool: 900),
          server: FakeServer()..round = roundJson(totalCheckIns: 5),
        );
        expect(state.totalCheckIns, 6);
        expect(state.stage, HomeStage.launch);
        // 900 in the pool: 600 short of the 1,500 Flap needs.
        expect(state.poolShort, usd(600));
      },
    );

    test('launched: claim with days, result without', () async {
      final withDays = await makeState(
        chain: FakeChain(launched: true, isMember: true, daysOf: 3),
        server: FakeServer()..round = roundJson(launched: true),
      );
      expect(withDays.stage, HomeStage.claim);
      expect(withDays.token, tokenAddress);
      final without = await makeState(
        chain: FakeChain(launched: true, isMember: true),
        server: FakeServer()..round = roundJson(launched: true),
      );
      expect(without.stage, HomeStage.result);
    });

    test('deadline passed without a launch: refund, or ended', () async {
      final late = DateTime.utc(2026, 12, 3);
      final owed = await makeState(
        now: late,
        chain: FakeChain(isMember: true, refundable: 1000),
      );
      expect(owed.pastDeadline, isTrue);
      expect(owed.stage, HomeStage.refund);
      final nothing = await makeState(now: late, chain: FakeChain());
      expect(nothing.stage, HomeStage.ended);
      // A full bar after the deadline cannot launch any more.
      final full = await makeState(
        now: late,
        chain: FakeChain(totalCheckIns: 6, pool: 1500),
        server: FakeServer()..round = roundJson(totalCheckIns: 6),
      );
      expect(full.stage, HomeStage.ended);
    });

    test('chain unreadable: the server\'s numbers stand in', () async {
      final state = await makeState(
        chain: FakeChain()..down = true,
        server: FakeServer()
          ..me = meJson(daysOf: 2, streak: 2, checkedInToday: true),
      );
      expect(state.onChain, isNull);
      expect(state.isMember, isTrue);
      expect(state.daysOf, 2);
      expect(state.stage, HomeStage.checkedIn);
      expect(state.deposit, usd(1000));
      expect(state.poolQuoteNow, usd(900));
    });
  });

  group('this wallet\'s own days', () {
    test('known once the chain or the server has answered', () async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2),
      );
      expect(state.yourDaysKnown, isTrue);
      expect(state.selectedReadOnce, isTrue);

      // The chain is read, the server is not.
      final chainOnly = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2),
        server: FakeServer()..me = {'member': Object()},
      );
      expect(chainOnly.me, isNull);
      expect(chainOnly.yourDaysKnown, isTrue);
      expect(chainOnly.daysOf, 2);

      // Neither answered: the 0 is not a count.
      final neither = await makeState(
        chain: FakeChain(isMember: true)..down = true,
        server: FakeServer()..me = {'member': Object()},
      );
      expect(neither.yourDaysKnown, isFalse);
      expect(neither.selectedReadOnce, isTrue);
    });

    test('a joined round just selected is a member\'s before its days are '
        'read', () async {
      final chain = FakeChain();
      chain.others[launcherB] = FakeChain(
        isMember: true,
        daysOf: 3,
        totalCheckIns: 4,
      );
      final server = FakeServer()
        ..more.add(roundJson(at: launcherB, name: 'Night Owls'))
        ..meAt[launcherB] = meJson(daysOf: 3, streak: 3);
      final state = await makeState(chain: chain, server: server);
      expect(state.joined, contains(launcherB));
      expect(state.selected, launcher);

      state.select(launcherB);
      // Nothing of it read yet: a member, with days not known.
      expect(state.isMember, isTrue);
      expect(state.yourDaysKnown, isFalse);
      expect(state.selectedReadOnce, isFalse);

      await state.refresh();
      expect(state.yourDaysKnown, isTrue);
      expect(state.selectedReadOnce, isTrue);
      expect(state.daysOf, 3);
    });
  });

  group('gas', () {
    test('a new wallet asks the faucet in the background, once', () async {
      final server = FakeServer();
      final state = await makeState(server: server, chain: FakeChain(bnb: 0));
      await Future<void>.delayed(Duration.zero);
      expect(server.count('POST /faucet'), 1);
      expect(state.funding, isFalse);
    });

    test('a funded wallet does not ask', () async {
      final server = FakeServer();
      await makeState(server: server, chain: FakeChain(bnb: 0.03));
      expect(server.count('POST /faucet'), 0);
    });

    test('the first transaction waits for the gas to arrive', () async {
      final chain = SlowFaucetChain(4);
      final state = await makeState(chain: chain);
      final seen = <bool>[];
      state.addListener(() => seen.add(state.funding));
      await state.getTestDollars(usd(1000));
      expect(seen, contains(true), reason: '"Preparing your wallet" showed');
      expect(state.funding, isFalse);
      expect(chain.calls, ['mint 1000']);
      expect(state.usd, usd(1000));
    });

    test(
      'gas that never arrives is one sentence, and nothing is sent',
      () async {
        final chain = FakeChain(bnb: 0);
        final state = await makeState(
          chain: chain,
          server: FakeServer()..faucet = {'funded': false, 'reason': 'served'},
        );
        await expectLater(
          state.getTestDollars(usd(1000)),
          throwsA(
            predicate((e) => '$e'.contains('no test BNB for network fees yet')),
          ),
        );
        expect(chain.calls, isEmpty);
        expect(state.funding, isFalse);
      },
    );

    test('the faucet will not fill the wallet again: one sentence at once, '
        'no 45-second wait', () async {
      final chain = FakeChain(bnb: 0.0001);
      final server = FakeServer()
        ..faucet = {
          'funded': false,
          'bnbTx': null,
          'reason': 'already_funded',
          'message': 'this wallet was already funded once',
        };
      final state = AppState(
        store: MemoryStore(key: testKey, onboarded: true),
        chain: chain,
        api: server.api,
        health: FakeHealth(),
        clock: () => fixedNow,
        gasPoll: const Duration(seconds: 3),
        gasPollTries: 15,
      );
      await state.init();
      final watch = Stopwatch()..start();
      await expectLater(
        state.getTestDollars(usd(1000)),
        throwsA(predicate((e) => '$e'.contains(AppState.faucetDoneMessage))),
      );
      // One short look (3 s), not 15 x 3 s.
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      expect(chain.calls, isEmpty);
      expect(state.funding, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('after "sent", the background top-up reads the balance until the '
        'transfer lands', () async {
      final chain = SlowFaucetChain(3);
      final server = FakeServer();
      final state = AppState(
        store: MemoryStore(key: testKey, onboarded: true),
        chain: chain,
        api: server.api,
        health: FakeHealth(),
        clock: () => fixedNow,
        gasPoll: Duration.zero,
        gasPollTries: 5,
      );
      await state.init();
      for (var i = 0; i < 20 && state.bnb == BigInt.zero; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(server.count('POST /faucet'), 1);
      expect(state.bnb, usd(0.03), reason: 'Wallet shows the faucet gas');
    });

    test(
      'launching needs the whole 7,000,000 gas limit in the wallet',
      () async {
        final chain = FakeChain(bnb: 0.005, totalCheckIns: 6, pool: 1500);
        final state = await makeState(
          chain: chain,
          server: FakeServer()..round = roundJson(totalCheckIns: 6),
        );
        await expectLater(
          state.launch(),
          throwsA(predicate((e) => '$e'.contains('Anyone else in the round'))),
        );
        expect(chain.calls, isEmpty);
        chain.bnb = usd(0.03);
        await state.launch();
        expect(chain.calls, ['launch']);
        expect(state.launched, isTrue);
      },
    );
  });

  group('join', () {
    test('mint the deposit, then approve and join', () async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      await state.getTestDollars(state.deposit);
      expect(state.usd, usd(1000));
      await state.payDeposit();
      expect(chain.calls, ['mint 1000', 'join 1000']);
      expect(state.isMember, isTrue);
      expect(state.usd, BigInt.zero);
      expect(state.stage, HomeStage.checkIn);
    });

    test('a sponsor mints what is missing and adds it to the pool', () async {
      final chain = FakeChain(dollars: 100, pool: 900);
      final state = await makeState(chain: chain);
      await state.sponsor(usd(600));
      expect(chain.calls, ['mint 500', 'sponsor 600']);
      expect(state.poolQuoteNow, usd(1500));
      expect(state.poolShort, BigInt.zero);
    });
  });

  group('check-in', () {
    test('browser: self-reported steps, then the day on chain', () async {
      final chain = FakeChain(isMember: true);
      final server = FakeServer();
      final store = MemoryStore(key: testKey, onboarded: true);
      final state = await makeState(chain: chain, server: server, store: store);
      final tx = await state.checkIn(selfReported: 6214);
      expect(tx, startsWith('0xc1'));
      expect(server.bodies['/rounds/$launcher/checkin']!['steps'], 6214);
      expect(server.bodies['/rounds/$launcher/checkin']!['source'], 'self');
      expect(chain.calls, ['checkIn 20782']);
      expect(state.checkedInToday, isTrue);
      expect(state.stage, HomeStage.checkedIn);
      expect(store.pending, isNull);
    });

    test('phone: steps come from the health store', () async {
      final server = FakeServer();
      final state = await makeState(
        chain: FakeChain(isMember: true),
        server: server,
        health: FakeHealth(available: true, steps: 8040),
      );
      await state.checkIn();
      expect(server.bodies['/rounds/$launcher/checkin']!['steps'], 8040);
      expect(
        server.bodies['/rounds/$launcher/checkin']!['source'],
        'healthkit',
      );
    });

    test('too few steps never reaches the server', () async {
      final server = FakeServer();
      final state = await makeState(
        chain: FakeChain(isMember: true),
        server: server,
      );
      await expectLater(
        state.checkIn(selfReported: 12),
        throwsA(
          predicate(
            (e) => '$e'.contains('at least 1,000 steps today. You have 12'),
          ),
        ),
      );
      expect(server.count('POST /rounds/$launcher/checkin'), 0);
    });

    test(
      'a signed check-in that failed on chain is kept and sent again',
      () async {
        final chain = FakeChain(isMember: true, fail: 'checkIn');
        final server = FakeServer();
        final store = MemoryStore(key: testKey, onboarded: true);
        final state = await makeState(
          chain: chain,
          server: server,
          store: store,
        );

        await expectLater(state.checkIn(selfReported: 6214), throwsException);
        expect(state.hasPendingCheckIn, isTrue);
        expect(store.pending!['attesterSignature'], attesterSignature);
        expect(store.pending!['launcher'], launcher);

        // A new session finds it and does not ask the server a second time.
        final again = await makeState(
          chain: chain,
          server: server,
          store: store,
        );
        expect(again.hasPendingCheckIn, isTrue);
        await again.checkIn();
        expect(server.count('POST /rounds/$launcher/checkin'), 1);
        expect(chain.calls, ['checkIn 20782']);
        expect(again.hasPendingCheckIn, isFalse);
        expect(store.pending, isNull);
      },
    );

    test('yesterday\'s signed check-in is not reused today', () async {
      final store = MemoryStore(
        key: testKey,
        onboarded: true,
        pending: {
          'day': '2026-11-24',
          'dayIndex': 20781,
          'attesterSignature': attesterSignature,
          'launcher': launcher,
        },
      );
      final state = await makeState(
        chain: FakeChain(isMember: true),
        store: store,
      );
      expect(state.hasPendingCheckIn, isFalse);
    });
  });

  group('after the launch', () {
    test('claim pays the share and can be pressed again later', () async {
      final chain = FakeChain(
        launched: true,
        isMember: true,
        daysOf: 3,
        totalCheckIns: 6,
        claimableTokens: 250000,
        claimableQuote: 1050,
      );
      final state = await makeState(
        chain: chain,
        server: FakeServer()
          ..round = roundJson(launched: true, totalCheckIns: 6),
      );
      expect(state.hasClaimable, isTrue);
      expect(state.claimableTokens, usd(250000));
      await state.claim();
      expect(chain.calls, ['claim']);
      expect(state.hasClaimable, isFalse);
      expect(state.claimedTokens, usd(250000));
      expect(state.claimedQuote, usd(1050));
      // Trading tax arrives: there is something to claim again.
      chain.claimableQuote = 18.59;
      await state.refresh();
      expect(state.hasClaimable, isTrue);
      expect(state.stage, HomeStage.claim);
    });

    test('refund returns the deposit after a missed deadline', () async {
      final chain = FakeChain(isMember: true, refundable: 1000);
      final state = await makeState(
        now: DateTime.utc(2026, 12, 3),
        chain: chain,
      );
      await state.refund();
      expect(chain.calls, ['refund']);
      expect(state.usd, usd(1000));
      expect(state.stage, HomeStage.ended);
    });
  });

  group('the week strip', () {
    test(
      'seven UTC days ending today; missed only after the first check-in',
      () async {
        final state = await makeState(
          chain: FakeChain(isMember: true),
          server: FakeServer()
            ..me = meJson(
              daysOf: 2,
              streak: 0,
              days: ['2026-11-21', '2026-11-23'],
            ),
        );
        final week = state.week;
        expect(week.length, 7);
        expect(week.first.$1, DateTime.utc(2026, 11, 19));
        expect(week.last.$1, DateTime.utc(2026, 11, 25));
        expect(
          [for (final d in week) d.$2],
          [
            DayState.upcoming, // 19: before the first check-in
            DayState.upcoming, // 20
            DayState.done, // 21
            DayState.missed, // 22
            DayState.done, // 23
            DayState.missed, // 24
            DayState.today, // 25
          ],
        );
      },
    );

    test('today is done as soon as the chain has it', () async {
      final state = await makeState(
        chain: FakeChain(isMember: true, checkedInToday: true, daysOf: 1),
      );
      expect(state.week.last.$2, DayState.done);
    });
  });

  group('wallet', () {
    test(
      'importing a key switches the wallet and reads the round again',
      () async {
        final store = MemoryStore(key: testKey, onboarded: true);
        final state = await makeState(store: store);
        const other =
            '0x00000000000000000000000000000000000000000000000000000000000000aa';
        await state.importKey(other);
        expect(state.address.toLowerCase(), isNot(testAddress));
        expect(store.key!.address, state.key!.address);
        await expectLater(
          state.importKey('not a key'),
          throwsA(predicate((e) => '$e'.contains('not a private key'))),
        );
      },
    );

    test('starting a round names it and derives the symbol', () async {
      final chain = FakeChain();
      final state = await makeState(chain: chain);
      final address = await state.createRound(
        name: 'Lumpini Striders',
        deposit: usd(1000),
        liquidityBps: 3000,
        checkInGoal: 6,
        deadline: fixedNow.add(const Duration(days: 7)),
      );
      expect(address, '0x5000000000000000000000000000000000000005');
      expect(chain.calls, ['createRound Lumpini Striders LS 1000 3000 6']);
    });
  });
}
