// THE PRIZE: the arithmetic (shares and projections, against the vault's
// own rule) and the section on Home in each of its states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/services/chain_service.dart';
import 'package:pacepact/util/format.dart';
import 'package:pacepact/util/names.dart';
import 'package:pacepact/util/pot.dart';
import 'package:pacepact/widgets/identicon.dart';
import 'package:pacepact/widgets/pot_section.dart';

import 'support.dart';

const other = '0x2000000000000000000000000000000000000002';
const third = '0x6000000000000000000000000000000000000006';

String wallet(int i) => '0x${(0xa000 + i).toRadixString(16).padLeft(40, '0')}';

Map<String, dynamic> member(String address, int days) => {
  'address': address,
  'daysOf': days,
  'streak': days,
  'checkedInToday': false,
};

BigInt sum(Iterable<BigInt> xs) => xs.fold(BigInt.zero, (a, b) => a + b);

/// The section alone, in a list as on Home.
Future<void> pumpPot(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(390, 844),
}) async {
  usePhone(tester, size: size);
  await tester.pumpWidget(
    inApp(
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.round != null)
            PotSection(state: state, round: state.round!, onInvite: () {}),
        ],
      ),
    ),
  );
  await settle(tester);
}

/// The rows on screen, top to bottom, by the address their orb is drawn
/// from.
List<String> rowsOf(WidgetTester tester) => [
  for (final w in tester.widgetList<Identicon>(find.byType(Identicon)))
    w.address,
];

String nudge(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('pot-nudge'))).data!;

/// A chain whose round read waits for [gate], or always fails with
/// [broken], while it still says who is a member: this wallet is known to
/// be in the round before its own days are.
class SlowRoundChain extends FakeChain {
  SlowRoundChain({
    this.gate,
    this.broken = false,
    super.isMember,
    super.daysOf,
    super.totalCheckIns,
  });
  Future<void>? gate;
  bool broken;

  @override
  Future<RoundChain> roundState(
    String launcher,
    String member, {
    DateTime? now,
  }) async {
    if (broken) throw Exception('rpc down');
    await gate;
    return super.roundState(launcher, member, now: now);
  }
}

/// A state that has started reading but is not awaited, and the section
/// on screen following it.
Future<AppState> pumpReading(
  WidgetTester tester, {
  required FakeChain chain,
  required FakeServer server,
}) async {
  final state = AppState(
    store: MemoryStore(key: testKey, onboarded: true),
    chain: chain,
    api: server.api,
    health: FakeHealth(),
    clock: () => fixedNow,
  );
  await state.init();
  usePhone(tester);
  await tester.pumpWidget(
    inApp(
      ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (state.round != null)
              PotSection(state: state, round: state.round!),
          ],
        ),
      ),
    ),
  );
  await settle(tester);
  // A read that is still waiting has not said anything has changed; the
  // balances do, so what has come back is drawn.
  await state.refreshBalances();
  await settle(tester);
  return state;
}

void main() {
  group('the arithmetic', () {
    test('the vault\'s rule: amount * days / total, rounded down', () {
      // Bangkok Showup on testnet: 1,233.480561266277444141 received, three
      // check-ins, one each.
      final received = parseUnits('1233.480561266277444141')!;
      expect(shareOf(received, 1, 3), BigInt.parse('411160187088759148047'));
      expect(shareOf(usd(2100), 3, 6), usd(1050));
      expect(shareOf(usd(2100), 0, 6), BigInt.zero);
      expect(shareOf(usd(2100), 3, 0), BigInt.zero);
      expect(shareOf(BigInt.from(10), 1, 3), BigInt.from(3));
    });

    test('one member with every check-in takes the whole prize', () {
      final pot = Pot.build(
        prize: usd(700),
        totalCheckIns: 3,
        memberCount: 1,
        members: [(testAddress, 3)],
        you: testAddress,
        isMember: true,
        yourDays: 3,
      );
      expect(pot.rows, hasLength(1));
      expect(pot.you!.amount, usd(700));
      expect(pot.you!.fraction, 1);
      expect(formatShare(3, 3), '100%');
      expect(pot.unlisted, 0);
      expect(pot.someoneHasNoDays, isFalse);
    });

    test(
      'zero check-ins: nobody gets anything yet; the first takes it all',
      () {
        final pot = Pot.build(
          prize: usd(2100),
          totalCheckIns: 0,
          memberCount: 3,
          members: [(other, 0), (third, 0)],
          you: testAddress,
          isMember: true,
        );
        expect(pot.total, 0);
        expect(pot.rows.map((r) => r.amount), everyElement(BigInt.zero));
        expect(pot.rows.map((r) => r.fraction), everyElement(0));
        expect(pot.perDay, BigInt.zero);
        expect(formatShare(0, 0), '0%');
        // (0 + 1) of (0 + 1).
        expect(formatShareAfterCheckIn(0, 0), '100%');
        // Yourself first among equals.
        expect(pot.rows.first.isYou, isTrue);
      },
    );

    test('you with zero days: nothing now, and what one check-in does', () {
      final pot = Pot.build(
        prize: usd(2100),
        totalCheckIns: 5,
        memberCount: 3,
        members: [(other, 3), (third, 2), (testAddress, 0)],
        you: testAddress,
        isMember: true,
      );
      expect(pot.you!.days, 0);
      expect(pot.you!.amount, BigInt.zero);
      expect(pot.rows.last.isYou, isTrue);
      expect(formatShare(0, 5), '0%');
      // (0 + 1) of (5 + 1) is 16.66%: said rounded down.
      expect(formatShareAfterCheckIn(0, 5), '16.6%');
      expect(pot.someoneHasNoDays, isTrue);
    });

    test('uneven days: most days first, each paid by its days', () {
      final pot = Pot.build(
        prize: usd(2100),
        totalCheckIns: 6,
        memberCount: 3,
        members: [(third, 1), (testAddress, 2), (other, 3)],
        you: testAddress,
        isMember: true,
        yourDays: 2,
      );
      expect(pot.rows.map((r) => r.address), [other, testAddress, third]);
      expect(pot.rows.map((r) => r.amount), [usd(1050), usd(700), usd(350)]);
      expect(pot.rows.map((r) => formatShare(r.days, pot.total)), [
        '50%',
        '33.3%',
        '16.6%',
      ]);
      expect(pot.perDay, usd(350));
      expect(formatShareAfterCheckIn(2, 6), '42.8%');
    });

    test('a share is rounded down, and a tiny one is not called zero', () {
      expect(formatShare(1, 3), '33.3%');
      expect(formatShare(2, 3), '66.6%');
      expect(formatShare(1, 8), '12.5%');
      expect(formatShare(999, 1000), '99.9%');
      expect(formatShare(1, 5000), 'under 0.1%');
      expect(formatShare(7, 5), '100%');
    });

    test('rounded to cents, the amounts never add up to more than the '
        'prize', () {
      final cases = <(String, List<int>)>[
        ('1000.01', [1, 1, 1]),
        ('2100', [1, 1, 1, 1, 1, 1, 1]),
        ('0.05', [1, 1, 1]),
        ('1233.480561266277444141', [5, 3, 3, 2, 1, 1, 1]),
        ('999999.99', [13, 11, 7, 5, 3, 2, 1, 1, 0]),
        ('700', [0, 0, 1]),
      ];
      for (final (prize, days) in cases) {
        final total = days.fold(0, (a, b) => a + b);
        final pot = Pot.build(
          prize: parseUnits(prize)!,
          totalCheckIns: total,
          memberCount: days.length,
          members: [for (final (i, d) in days.indexed) (wallet(i), d)],
        );
        // Base units, as the vault pays them.
        expect(sum(pot.rows.map((r) => r.amount)) <= pot.prize, isTrue);
        // And as they are written on the rows, to the cent.
        final written = sum(
          pot.rows.map(
            (r) => parseUnits(formatAmount(r.amount)) ?? BigInt.zero,
          ),
        );
        expect(written <= pot.prize, isTrue, reason: '$prize over $days');
        // Rounding loses less than a cent per member, never more.
        expect(
          pot.prize - written < parseUnits('0.01')! * BigInt.from(days.length),
          isTrue,
          reason: '$prize over $days',
        );
      }
    });

    test('a total older than the list never pays out more than the prize', () {
      // The round said 3 check-ins a moment before the list counted 4.
      final pot = Pot.build(
        prize: usd(2100),
        totalCheckIns: 3,
        memberCount: 2,
        members: [(other, 2), (third, 2)],
      );
      expect(pot.total, 4);
      expect(sum(pot.rows.map((r) => r.amount)), usd(2100));
    });

    test('the chain\'s count of your days replaces the list\'s', () {
      final pot = Pot.build(
        prize: usd(2100),
        totalCheckIns: 3,
        memberCount: 2,
        members: [(other, 1), (testAddress.toUpperCase(), 1)],
        you: testAddress,
        isMember: true,
        yourDays: 2,
      );
      expect(pot.rows, hasLength(2));
      expect(pot.you!.days, 2);
      expect(pot.you!.amount, usd(1400));
    });

    test('members the list leaves out are counted, with what is known of '
        'them', () {
      final all = Pot.build(
        prize: usd(2100),
        totalCheckIns: 3,
        memberCount: 5,
        members: [(other, 2), (third, 1)],
      );
      expect(all.unlisted, 3);
      // The list holds all 3 check-ins: the other three members have none.
      expect(all.unlistedHaveNoDays, isTrue);
      expect(all.someoneHasNoDays, isTrue);

      final some = Pot.build(
        prize: usd(2100),
        totalCheckIns: 6,
        memberCount: 5,
        members: [(other, 2), (third, 1)],
      );
      expect(some.unlistedHaveNoDays, isFalse);
      // The amounts are still out of all 6 check-ins.
      expect(some.rows.first.amount, usd(700));
    });

    test('many members: the first five, then you; everyone on request', () {
      final members = [for (var i = 0; i < 80; i++) (wallet(i), 100 - i)];
      Pot potAt(int rank) => Pot.build(
        prize: usd(100000),
        totalCheckIns: 10000,
        memberCount: 81,
        members: [
          ...members.take(rank),
          (testAddress, 100 - rank),
          ...members.skip(rank),
        ],
        you: testAddress,
        isMember: true,
        yourDays: 100 - rank,
      );

      final far = potAt(30);
      final short = far.shown(everyone: false);
      expect(short, hasLength(6));
      expect(short.last.isYou, isTrue);
      expect(far.youBelow(short), isTrue);
      expect(short.take(5).map((r) => r.address), [
        for (var i = 0; i < 5; i++) wallet(i),
      ]);

      final long = far.shown(everyone: true);
      expect(long, hasLength(50));
      expect(long.where((r) => r.isYou), hasLength(1));
      expect(far.youBelow(long), isFalse);

      // Past the fiftieth, you are still shown, last.
      final last = potAt(70).shown(everyone: true);
      expect(last, hasLength(51));
      expect(last.last.isYou, isTrue);

      // In the first five there is nothing to add.
      final near = potAt(2);
      expect(near.shown(everyone: false), hasLength(5));
      expect(near.youBelow(near.shown(everyone: false)), isFalse);
    });

    test('the bar: any share shows, only a whole share fills it', () {
      expect(ShareTicks.filledFor(0), 0);
      expect(ShareTicks.filledFor(0.001), 1);
      expect(ShareTicks.filledFor(0.5), 12);
      expect(ShareTicks.filledFor(0.99), 23);
      expect(ShareTicks.filledFor(1), 24);
      expect(ShareTicks.filledFor(double.nan), 0);
    });

    test('the nudge never promises a share that does not change', () {
      expect(shareNudge(1, 3), 'Check in today and your share goes to 50%.');
      expect(shareNudge(0, 0), 'Check in today and your share goes to 100%.');
      // Every check-in so far is yours: 100% before and after.
      for (final (d, t) in [(1, 1), (2, 2), (40, 40)]) {
        expect(
          shareNudge(d, t),
          'You hold every check-in so far. Check in today to stay ahead '
          'when others show up.',
        );
      }
      // 99.9% before and after, as written: the share grows, unseen.
      expect(formatShare(999, 1000), formatShareAfterCheckIn(999, 1000));
      expect(shareNudge(999, 1000), 'Check in today to grow your share.');
    });

    test('what the bar still needs, said only while it is not full', () {
      expect(
        barNeedsSentence(6, 3),
        'The bar needs 3 more check-ins before it can launch, and each one '
        'changes these shares.',
      );
      expect(
        barNeedsSentence(5, 4),
        'The bar needs 1 more check-in before it can launch, and that one '
        'changes these shares.',
      );
      expect(
        barNeedsSentence(5000, 1000),
        startsWith('The bar needs 4,000 more check-ins'),
      );
      expect(barNeedsSentence(6, 6), isNull);
      expect(barNeedsSentence(6, 9), isNull);
    });

    test('members needed for the token pool: deposit times liquidityBps '
        'each, rounded up', () {
      // 1,000 deposit at 30%: 300 a member.
      expect(
        membersToFillPool(
          short: usd(1500),
          deposit: usd(1000),
          liquidityBps: 3000,
        ),
        5,
      );
      expect(
        membersToFillPool(
          short: usd(600),
          deposit: usd(1000),
          liquidityBps: 3000,
        ),
        2,
      );
      expect(
        membersToFillPool(
          short: usd(601),
          deposit: usd(1000),
          liquidityBps: 3000,
        ),
        3,
      );
      expect(
        membersToFillPool(
          short: BigInt.one,
          deposit: usd(1000),
          liquidityBps: 3000,
        ),
        1,
      );
      expect(
        membersToFillPool(
          short: BigInt.zero,
          deposit: usd(1000),
          liquidityBps: 3000,
        ),
        0,
      );
      // A round whose deposit adds nothing to the pool: only a sponsor.
      expect(
        membersToFillPool(short: usd(600), deposit: usd(1000), liquidityBps: 0),
        isNull,
      );
    });
  });

  group('the section', () {
    testWidgets('a member who has not checked in: the amount, the share and '
        'what today\'s check-in does to it', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 3),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 3)
          ..members = [member(other, 2), member(testAddress, 1)],
      );
      await pumpPot(tester, state);

      expect(find.text('THE PRIZE'), findsOneWidget);
      // How many members is said on the round's card above, not twice.
      expect(find.text('3 members'), findsNothing);
      expect(find.text('If it launched now, you\'d get'), findsOneWidget);
      // 2,100 of prize, 1 of 3 check-ins. The one big number.
      expect(
        tester.widget<Text>(find.byKey(const Key('pot-amount'))).data,
        '700',
      );
      expect(find.text('test USD'), findsOneWidget);
      expect(
        find.text(
          '1 of 3 check-ins is yours: 33.3% of the prize and of the token '
          'share.',
        ),
        findsOneWidget,
      );
      // The bar (goal 6) is not full: the shares still move.
      expect(
        find.text(
          'The bar needs 3 more check-ins before it can launch, and each one '
          'changes these shares.',
        ),
        findsOneWidget,
      );
      // (1 + 1) of (3 + 1).
      expect(nudge(tester), 'Check in today and your share goes to 50%.');

      // The comparison, most days first, with what each would get. Each
      // row has a friendly name and the short address under it.
      expect(rowsOf(tester), [other, testAddress]);
      expect(find.text(friendlyName(other)), findsOneWidget);
      expect(find.text('0x2000…0002'), findsOneWidget);
      expect(
        tester.getRect(find.text('0x2000…0002')).top,
        greaterThan(tester.getRect(find.text(friendlyName(other))).top),
      );
      // "You" stays "You", with no address under it.
      expect(find.text(shortAddress(testAddress)), findsNothing);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('1,400 USD'), findsOneWidget);
      expect(find.text('700 USD'), findsOneWidget);
      // Only "You" is drawn in the accent.
      final bars = tester.widgetList<ShareTicks>(find.byType(ShareTicks));
      expect(bars.map((b) => b.accent), [false, true]);
      expect(bars.first.fraction, closeTo(2 / 3, 1e-9));
      // The third member has not opened the app and has no check-in.
      expect(
        find.textContaining('1 more member has not checked in yet.'),
        findsOneWidget,
      );
      // The token part is said in words, never priced.
      expect(find.textContaining('\$'), findsNothing);
      // One word for the money part: the prize. Never "pot".
      expect(
        find.textContaining(RegExp(r'\bpot\b', caseSensitive: false)),
        findsNothing,
      );
    });

    testWidgets('a member who has checked in today is told to come back', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(
          isMember: true,
          daysOf: 2,
          totalCheckIns: 4,
          checkedInToday: true,
        ),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 4)
          ..members = [member(other, 2), member(testAddress, 2)],
      );
      await pumpPot(tester, state);

      expect(
        nudge(tester),
        'You\'re done for today. Come back tomorrow to grow it.',
      );
      expect(find.textContaining('Check in today'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('pot-amount'))).data,
        '1,050',
      );
      // Equal days: yourself first.
      expect(rowsOf(tester), [testAddress, other]);
    });

    testWidgets('no check-ins yet: no amount, the true sentence, and the '
        'first check-in takes it all', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 0)
          ..members = [member(other, 0), member(testAddress, 0)],
      );
      await pumpPot(tester, state);

      expect(
        find.text(
          'No check-ins yet. The first one would hold 100% of the prize '
          'share until someone else shows up.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pot-amount')), findsNothing);
      expect(find.text('If it launched now, you\'d get'), findsNothing);
      expect(nudge(tester), 'Check in today and your share goes to 100%.');
      expect(find.text('0 days'), findsNWidgets(2));
      expect(find.text('nothing yet'), findsNWidgets(2));
      // What zero days means when the token launches, in plain words.
      expect(
        find.textContaining(
          '0 days means no share. If the token launches, that deposit stays '
          'in the prize and the token pool; it comes back only if the round '
          'never launches.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('you with zero days among others: 0 USD now, a real share '
        'after one check-in', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, totalCheckIns: 5),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 5)
          ..members = [member(other, 3), member(third, 2)],
      );
      await pumpPot(tester, state);

      expect(
        tester.widget<Text>(find.byKey(const Key('pot-amount'))).data,
        '0',
      );
      expect(
        find.text(
          '0 of 5 check-ins are yours: 0% of the prize and of the token '
          'share.',
        ),
        findsOneWidget,
      );
      expect(nudge(tester), 'Check in today and your share goes to 16.6%.');
      // The list had not heard of this wallet yet: it still has its row.
      expect(rowsOf(tester), [other, third, testAddress]);
      expect(find.text('nothing yet'), findsOneWidget);
    });

    testWidgets('not joined: no amount of your own, what a day is worth, '
        'and the same list', (tester) async {
      final state = await makeState(
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 4)
          ..members = [member(other, 3), member(third, 1)],
      );
      await pumpPot(tester, state);

      expect(state.isMember, isFalse);
      expect(find.byKey(const Key('pot-amount')), findsNothing);
      expect(find.byKey(const Key('pot-nudge')), findsNothing);
      expect(find.text('You'), findsNothing);
      // 2,100 over 4 check-ins.
      expect(
        find.text(
          'If it launched now, each day shown up would be worth about 525 '
          'test USD.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // A visitor sees no share of their own, so no line about it.
      expect(find.byKey(const Key('pot-bar-needs')), findsNothing);
      expect(rowsOf(tester), [other, third]);
      expect(find.text('1,575 USD'), findsOneWidget);
      expect(find.text('525 USD'), findsOneWidget);
    });

    testWidgets('not joined and no check-ins: the true sentence, nothing '
        'else', (tester) async {
      final state = await makeState(
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 0, memberCount: 0)
          ..members = [],
      );
      await pumpPot(tester, state);

      expect(find.textContaining('No check-ins yet.'), findsOneWidget);
      expect(find.textContaining('each day shown up'), findsNothing);
      expect(find.text('0 members'), findsNothing);
      expect(find.text('No one has joined yet. Be the first.'), findsOneWidget);
      expect(find.byType(Identicon), findsNothing);
    });

    testWidgets('a round with one member', (tester) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2, totalCheckIns: 2),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 2, memberCount: 1, prizeNow: '700')
          ..members = [member(testAddress, 2)],
      );
      await pumpPot(tester, state);

      expect(find.text('1 member'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('pot-amount'))).data,
        '700',
      );
      expect(
        find.text(
          '2 of 2 check-ins are yours: 100% of the prize and of the token '
          'share.',
        ),
        findsOneWidget,
      );
      // (2 + 1) of (2 + 1): it stays everything, so no new number is
      // promised.
      expect(
        nudge(tester),
        'You hold every check-in so far. Check in today to stay ahead when '
        'others show up.',
      );
      expect(rowsOf(tester), [testAddress]);
      expect(tester.widget<ShareTicks>(find.byType(ShareTicks)).fraction, 1);
      expect(find.byKey(const Key('pot-everyone')), findsNothing);
      expect(find.textContaining('0 days means'), findsNothing);
    });

    testWidgets('fifty members: the list stays short, "You" is always on '
        'it, and "Show everyone" opens the rest', (tester) async {
      final members = [for (var i = 0; i < 49; i++) member(wallet(i), 60 - i)]
        ..insert(29, member(testAddress, 31));
      final total = members.fold<int>(0, (a, m) => a + (m['daysOf'] as int));
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 31, totalCheckIns: total),
        server: FakeServer()
          ..round = roundJson(
            totalCheckIns: total,
            memberCount: 50,
            checkInGoal: 5000,
          )
          ..members = members,
      );
      await pumpPot(tester, state);

      expect(find.text('50 members'), findsNothing);
      // The first five, then the person's own row.
      expect(rowsOf(tester), [
        for (var i = 0; i < 5; i++) wallet(i),
        testAddress,
      ]);
      expect(find.text('You'), findsOneWidget);
      // A mark between the fifth row and the person's own.
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('pot-everyone')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('pot-everyone')));
      await settle(tester);
      // All fifty, each once, in order of days.
      expect(rowsOf(tester), hasLength(50));
      expect(rowsOf(tester).indexOf(testAddress), 29);
      expect(find.text('You'), findsOneWidget);
      final everyone = find.byKey(const Key('pot-everyone'));
      await tester.ensureVisible(everyone);
      await settle(tester);
      expect(find.text('Show fewer'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

      await tester.tap(everyone);
      await settle(tester);
      expect(rowsOf(tester), hasLength(6));
    });

    testWidgets('after the launch: final days and what each got, no '
        'projection', (tester) async {
      final state = await makeState(
        chain: FakeChain(
          launched: true,
          isMember: true,
          daysOf: 1,
          totalCheckIns: 3,
        ),
        server: FakeServer()
          ..round = roundJson(
            launched: true,
            totalCheckIns: 3,
            prizeNow: '1233.480561266277444141',
          )
          ..me = meJson(daysOf: 1)
          ..members = [
            member(other, 2),
            member(testAddress, 1),
            member(third, 0),
          ],
      );
      await pumpPot(tester, state);

      expect(
        find.text('The token launched. These shares are final.'),
        findsOneWidget,
      );
      expect(find.textContaining('If it launched now'), findsNothing);
      expect(find.byKey(const Key('pot-amount')), findsNothing);
      expect(find.byKey(const Key('pot-nudge')), findsNothing);
      // The vault's own split of everything it has received, rounded down.
      expect(find.text('822.32 USD'), findsOneWidget);
      expect(find.text('411.16 USD'), findsOneWidget);
      expect(find.text('nothing'), findsOneWidget);
      expect(
        find.textContaining(
          'A member with 0 days has no share: that deposit went to the '
          'prize and the token pool.',
        ),
        findsOneWidget,
      );
      // A launched round takes no new members.
      expect(find.text('Invite someone'), findsNothing);
    });

    testWidgets('a round that closed without a launch shares nothing', (
      tester,
    ) async {
      final state = await makeState(
        now: DateTime.utc(2026, 12, 3),
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 2),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 2)
          ..members = [member(other, 1), member(testAddress, 1)],
      );
      await pumpPot(tester, state);

      expect(
        find.text(
          'This round closed without a launch. Every deposit goes back in '
          'full, so nothing is shared.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('USD'), findsNothing);
      expect(find.byKey(const Key('pot-nudge')), findsNothing);
      expect(rowsOf(tester), hasLength(2));
      // Refunds take members off the contract's count: the rows are said.
      expect(find.text('2 joined'), findsOneWidget);
      expect(find.textContaining('members'), findsNothing);
    });

    testWidgets('closed after refunds: the contract\'s count is not used', (
      tester,
    ) async {
      // Two of three took their deposit back; the contract now says 1.
      final state = await makeState(
        now: DateTime.utc(2026, 12, 3),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 2, memberCount: 1)
          ..members = [
            member(other, 1),
            member(third, 1),
            member(wallet(1), 0),
          ],
      );
      await pumpPot(tester, state);
      expect(find.text('3 joined'), findsOneWidget);
      expect(find.text('1 member'), findsNothing);
      expect(find.textContaining('did not check in'), findsNothing);
    });

    testWidgets('after the launch, members the list leaves out "did not '
        'check in"', (tester) async {
      final state = await makeState(
        chain: FakeChain(launched: true, totalCheckIns: 3),
        server: FakeServer()
          ..round = roundJson(
            launched: true,
            totalCheckIns: 3,
            memberCount: 4,
            prizeNow: '1233.480561266277444141',
          )
          ..members = [member(other, 2), member(third, 1)],
      );
      await pumpPot(tester, state);
      expect(
        find.textContaining('2 more members did not check in.'),
        findsOneWidget,
      );
      expect(find.textContaining('not checked in yet'), findsNothing);
    });

    testWidgets('members the list does not show yet: how many, and why', (
      tester,
    ) async {
      final state = await makeState(
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 0, memberCount: 3)
          ..members = [],
      );
      await pumpPot(tester, state);
      expect(
        find.text(
          '3 members have joined. They show here once they open the app.',
        ),
        findsOneWidget,
      );

      final one = await makeState(
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 0, memberCount: 1)
          ..members = [],
      );
      await pumpPot(tester, one);
      expect(
        find.text(
          '1 member has joined. They show here once they open the app.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a member whose own days are not read yet sees no amount, '
        'and the list keeps their days', (tester) async {
      final gate = Completer<void>();
      final chain = SlowRoundChain(
        gate: gate.future,
        isMember: true,
        daysOf: 2,
        totalCheckIns: 3,
      );
      // The server's /me cannot answer either (its body is not JSON).
      final server = FakeServer()
        ..round = roundJson(totalCheckIns: 3)
        ..me = {'member': Object()}
        ..members = [member(testAddress, 2), member(other, 1)];
      final state = await pumpReading(tester, chain: chain, server: server);

      // Known to be in the round (from the chain's membership check), not
      // yet known how many days.
      expect(state.isMember, isTrue);
      expect(state.yourDaysKnown, isFalse);
      expect(find.byKey(const Key('pot-hero-skeleton')), findsOneWidget);
      expect(find.byKey(const Key('pot-amount')), findsNothing);
      expect(find.byKey(const Key('pot-nudge')), findsNothing);
      expect(find.textContaining('check-ins is yours'), findsNothing);
      expect(find.textContaining('check-ins are yours'), findsNothing);
      expect(find.textContaining('you\'d get'), findsNothing);
      // The list's own count of this wallet's days stands, not 0.
      expect(rowsOf(tester), [testAddress, other]);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('1,400 USD'), findsOneWidget);
      expect(find.text('nothing yet'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(state.yourDaysKnown, isTrue);
      expect(find.byKey(const Key('pot-hero-skeleton')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('pot-amount'))).data,
        '1,400',
      );
    });

    testWidgets('a member whose days could not be read at all is told so, '
        'with no amount', (tester) async {
      final chain = SlowRoundChain(broken: true, isMember: true);
      final server = FakeServer()
        ..round = roundJson(totalCheckIns: 3)
        ..me = {'member': Object()}
        ..members = [member(testAddress, 2), member(other, 1)];
      final state = await pumpReading(tester, chain: chain, server: server);

      expect(state.isMember, isTrue);
      expect(state.selectedReadOnce, isTrue);
      expect(find.byKey(const Key('pot-hero-skeleton')), findsNothing);
      expect(
        find.text(
          'Your days in this round could not be read yet. Your share shows '
          'here as soon as they are.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pot-amount')), findsNothing);
      expect(find.text('2 days'), findsOneWidget);
    });

    testWidgets('names: friendly, the same every time, "You" for yourself', (
      tester,
    ) async {
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 1, totalCheckIns: 4),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 4)
          ..members = [
            member(other, 2),
            member(testAddress, 1),
            member(third, 1),
          ],
      );
      await pumpPot(tester, state);
      for (final a in [other, third]) {
        expect(find.text(friendlyName(a)), findsOneWidget);
        expect(find.text(shortAddress(a)), findsOneWidget);
      }
      expect(find.text('You'), findsOneWidget);
      expect(find.text(friendlyName(testAddress)), findsNothing);
      expect(
        find.text(
          '1 of 4 check-ins is yours: 25% of the prize and of the token '
          'share.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('while the members are read: still rows, not a spinner', (
      tester,
    ) async {
      final gate = Completer<void>();
      final server = FakeServer()
        ..round = roundJson(totalCheckIns: 3)
        ..members = [member(other, 3)]
        ..membersGate = gate.future;
      final state = AppState(
        store: MemoryStore(key: testKey, onboarded: true),
        chain: FakeChain(),
        api: server.api,
        health: FakeHealth(),
        clock: () => fixedNow,
      );
      await state.init();
      usePhone(tester);
      await tester.pumpWidget(
        inApp(
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (state.round != null)
                  PotSection(state: state, round: state.round!),
              ],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(state.membersRead, isFalse);
      expect(find.byKey(const Key('pot-skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Identicon), findsNothing);
      // What does not need the list is already there.
      expect(find.textContaining('each day shown up'), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(find.byKey(const Key('pot-skeleton')), findsNothing);
      expect(rowsOf(tester), [other]);
    });

    testWidgets('the members could not be read: one sentence and "Try '
        'again"', (tester) async {
      final server = FakeServer()
        ..round = roundJson(totalCheckIns: 3)
        ..members = [member(other, 3)]
        ..membersDown = 'could not read the round on chain; try again';
      final state = await makeState(server: server);
      await pumpPot(tester, state);

      expect(
        find.text('could not read the round on chain; try again'),
        findsOneWidget,
      );
      expect(find.byType(Identicon), findsNothing);
      expect(find.byKey(const Key('pot-skeleton')), findsNothing);

      server.membersDown = null;
      await tester.tap(find.bySemanticsLabel('Try again'));
      await settle(tester);
      expect(find.textContaining('could not read'), findsNothing);
      expect(rowsOf(tester), [other]);
    });

    testWidgets('a list read before stays when a later read fails', (
      tester,
    ) async {
      final server = FakeServer()
        ..round = roundJson(totalCheckIns: 3)
        ..members = [member(other, 3)];
      final state = await makeState(server: server);
      await pumpPot(tester, state);
      expect(rowsOf(tester), [other]);

      server.membersDown = 'could not read the round on chain; try again';
      await state.refresh();
      await settle(tester);
      expect(rowsOf(tester), [other]);
      expect(find.textContaining('could not read'), findsNothing);
    });

    testWidgets('320 by 568 with large text: long amounts and fifty members '
        'fit', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final members = [for (var i = 0; i < 49; i++) member(wallet(i), 400 - i)]
        ..insert(20, member(testAddress, 380));
      final total = members.fold<int>(0, (a, m) => a + (m['daysOf'] as int));
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 380, totalCheckIns: total),
        server: FakeServer()
          ..round = roundJson(
            name: 'A very long round name that goes on and on',
            totalCheckIns: total,
            memberCount: 1234,
            checkInGoal: 50000,
            prizeNow: '987654321.987654321',
          )
          ..members = members,
      );
      await pumpPot(tester, state, size: const Size(320, 568));
      expect(tester.takeException(), isNull);

      // Nothing is wider than the screen, and the amount is on one line.
      final amount = find.byKey(const Key('pot-amount'));
      expect(tester.getRect(amount).right, lessThanOrEqualTo(320));
      for (final row in find.byType(ShareTicks).evaluate()) {
        final box = row.renderObject! as RenderBox;
        final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
        expect(right, lessThanOrEqualTo(320 - 20));
        expect(box.size.width, greaterThan(40));
      }

      // Opened, and scrolled to its end.
      await tester.ensureVisible(find.byKey(const Key('pot-everyone')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('pot-everyone')));
      await settle(tester);
      expect(rowsOf(tester), hasLength(50));
      await tester.ensureVisible(find.text('Invite someone'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // The words under the list wrap inside the screen.
      final note = find.textContaining('more members have not checked in');
      expect(tester.getRect(note).right, lessThanOrEqualTo(320 - 20));
    });

    testWidgets('a screen reader hears each row whole and can open the '
        'list', (tester) async {
      final semantics = tester.ensureSemantics();
      final members = [
        member(other, 4),
        member(testAddress, 2),
        for (var i = 0; i < 6; i++) member(wallet(i), 1),
      ];
      final state = await makeState(
        chain: FakeChain(isMember: true, daysOf: 2, totalCheckIns: 12),
        server: FakeServer()
          ..round = roundJson(totalCheckIns: 12, memberCount: 8)
          ..members = members,
      );
      await pumpPot(tester, state);

      expect(
        find.bySemanticsLabel(
          'You, 2 days, 16.6% of all check-ins, 350 USD if it launched now',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('If it launched now, you\'d get 350 test USD'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Show everyone')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasExpandedState: true,
        ),
      );
      // The control is tall enough to press.
      expect(
        tester.getSize(find.byKey(const Key('pot-everyone'))).height,
        greaterThanOrEqualTo(44),
      );
      semantics.dispose();
    });
  });
}
