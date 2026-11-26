// Share this round: the Share button on Your round, the "Share card" chip
// beside "Invite someone" on Home, the card in the sheet (name, the bar,
// the deposit, the QR, the Season badge, "Every deposit is prize" only when
// none of the deposits goes to the shop), Copy link, and Share through an
// injected sharer so no platform channel is reached.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/screens/home_screen.dart';
import 'package:pacepact/screens/round_screen.dart';
import 'package:pacepact/screens/share_sheet.dart';
import 'package:pacepact/services/card_sharer.dart';
import 'package:pacepact/widgets/common.dart';
import 'package:pacepact/widgets/share_card.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support.dart';

/// The link every test round has: the site's address, as no WEB_BASE_URL
/// is set in tests.
const roundLink =
    'https://dokind.github.io/kickoff-bnb-hack/#/r/'
    '0x1000000000000000000000000000000000000001';

class FakeSharer implements CardSharer {
  FakeSharer({this.outcome = ShareOutcome.shared, this.fail = false});
  final ShareOutcome outcome;
  final bool fail;
  final shares =
      <({Uint8List png, String fileName, String text, Rect? origin})>[];
  final saves = <String>[];

  @override
  bool canSave = false;

  @override
  Future<ShareOutcome> share({
    required Uint8List png,
    required String fileName,
    required String text,
    Rect? origin,
  }) async {
    if (fail) throw Exception('no share sheet');
    shares.add((png: png, fileName: fileName, text: text, origin: origin));
    return outcome;
  }

  @override
  Future<bool> save(Uint8List png, String fileName) async {
    saves.add(fileName);
    return true;
  }
}

Finder pill(String label) =>
    find.byWidgetPredicate((w) => w is PillButton && w.label == label);

Future<void> pumpRound(WidgetTester tester, AppState state) async {
  usePhone(tester);
  await tester.pumpWidget(inApp(RoundScreen(state: state, launcher: launcher)));
  await settle(tester);
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('round-share')));
  await settle(tester, 12);
}

/// Captures what goes on the clipboard.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

/// The card's text with [key].
String cardText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  late CardSharer original;
  setUp(() => original = cardSharer);
  tearDown(() {
    cardSharer = original;
    bannerNote.value = null;
  });

  group('Your round', () {
    testWidgets('has a Share button in its top bar', (tester) async {
      final semantics = tester.ensureSemantics();
      final state = await makeState();
      await pumpRound(tester, state);

      final share = find.byKey(const Key('round-share'));
      expect(share, findsOneWidget);
      expect(find.bySemanticsLabel('Share this round'), findsOneWidget);
      // In the top bar, level with Back, at the right edge.
      final back = tester.getRect(find.byKey(const Key('round-back')));
      final rect = tester.getRect(share);
      expect(rect.center.dy, closeTo(back.center.dy, 1));
      expect(rect.right, closeTo(390 - 20, 1));
      semantics.dispose();
    });

    testWidgets('opens the sheet with the round\'s card', (tester) async {
      final state = await makeState();
      await pumpRound(tester, state);
      await openSheet(tester);

      expect(find.byType(ShareSheet), findsOneWidget);
      expect(find.text('Share this round'), findsOneWidget);
      expect(find.byType(ShareCard), findsOneWidget);
      expect(cardText(tester, 'share-card-name'), 'Morning Movers');
      expect(cardText(tester, 'share-card-bar'), '2 / 6 check-ins');
      expect(cardText(tester, 'share-card-deposit'), '1,000 test USD');
      expect(cardText(tester, 'share-card-members'), '3');
      final qr = tester.widget<QrImageView>(
        find.byKey(const Key('share-card-qr')),
      );
      expect(qr.size, 84);
      // The QR holds the round's link.
      expect(
        tester.widget<ShareCard>(find.byType(ShareCard)).data.shared,
        roundLink,
      );
      expect(
        cardText(tester, 'share-card-endings'),
        'Fall short: 100% back · Fill it: launch on Flap, split by days',
      );
      expect(cardText(tester, 'share-card-footer'), 'BSC testnet · test money');
      // 30% of each deposit goes to the shop here: no "every deposit".
      expect(find.text('Every deposit is prize'), findsNothing);
      // An ordinary open round: its state, not a Season.
      expect(find.text('Open · join now'), findsOneWidget);
      expect(find.textContaining('Season'), findsNothing);
      // The link in short, under "Scan to join".
      expect(find.text('dokind.github.io'), findsOneWidget);
      expect(find.text('/kickoff-bnb-hack'), findsOneWidget);
      expect(find.text('#/r/0x1000…0001'), findsOneWidget);
      // The actions; Save image is only where files can be saved.
      expect(pill('Share'), findsOneWidget);
      expect(pill('Copy link'), findsOneWidget);
      expect(pill('Save image'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Season squad: the Season badge and "Every deposit is '
        'prize"', (tester) async {
      final server = FakeServer()..round = seasonRoundJson();
      final state = await makeState(
        server: server,
        chain: FakeChain(isMember: true, deposit: 100, pool: 1500),
      );
      await pumpRound(tester, state);
      await openSheet(tester);

      expect(cardText(tester, 'share-card-name'), 'Season 1 Squad A');
      expect(find.text('Season 1 · starts Tue 1 Dec'), findsOneWidget);
      expect(cardText(tester, 'share-card-deposit'), '100 test USD');
      expect(cardText(tester, 'share-card-bar'), '0 / 240 check-ins');
      expect(find.byKey(const Key('share-card-prize')), findsOneWidget);
      expect(find.text('Every deposit is prize'), findsOneWidget);
      expect(find.byKey(const Key('share-card-qr')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Copy link puts the exact link on the clipboard', (
      tester,
    ) async {
      final copied = mockClipboard(tester);
      final state = await makeState();
      await pumpRound(tester, state);
      await openSheet(tester);

      await tester.tap(pill('Copy link'));
      await settle(tester);
      expect(copied, [roundLink]);
      expect(bannerNote.value!.text, 'Link copied.');
    });

    testWidgets('Share hands a PNG of the card and the link to the sharer', (
      tester,
    ) async {
      final sharer = FakeSharer();
      cardSharer = sharer;
      final state = await makeState();
      await pumpRound(tester, state);
      await openSheet(tester);

      await tester.runAsync(() async {
        await tester.tap(pill('Share'));
        for (var i = 0; i < 40 && sharer.shares.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await settle(tester);

      expect(sharer.shares, hasLength(1));
      final shared = sharer.shares.single;
      expect(shared.fileName, 'cypher-run-morning-movers.png');
      expect(shared.text, contains(roundLink));
      expect(shared.text, contains('test USD'));
      expect(shared.text, isNot(contains(r'$')));
      // A PNG, 1080 by 1350: the card at 3x.
      expect(shared.png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final bytes = ByteData.sublistView(shared.png);
      expect(bytes.getUint32(16), 1080);
      expect(bytes.getUint32(20), 1350);
      expect(shared.origin, isNotNull);
      expect(find.byType(ErrorLine), findsNothing);
    });

    testWidgets('a share that fails says so in plain words', (tester) async {
      cardSharer = FakeSharer(fail: true);
      final state = await makeState();
      await pumpRound(tester, state);
      await openSheet(tester);

      await tester.runAsync(() async {
        await tester.tap(pill('Share'));
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (find.byType(ErrorLine).evaluate().isNotEmpty) break;
        }
      });
      await settle(tester);

      expect(
        find.text('Could not share the card. Copy the link instead.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a browser that cannot share images: downloaded, link '
        'copied', (tester) async {
      final copied = mockClipboard(tester);
      final sharer = FakeSharer(outcome: ShareOutcome.downloaded)
        ..canSave = true;
      cardSharer = sharer;
      final state = await makeState();
      await pumpRound(tester, state);
      await openSheet(tester);
      expect(pill('Save image'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(pill('Share'));
        for (var i = 0; i < 40 && copied.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await settle(tester);

      expect(copied, [roundLink]);
      expect(
        bannerNote.value!.text,
        'This browser can\'t share images. The card was downloaded and the '
        'link copied.',
      );

      await tester.runAsync(() async {
        await tester.tap(pill('Save image'));
        for (var i = 0; i < 40 && sharer.saves.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await settle(tester);
      expect(sharer.saves, ['cypher-run-morning-movers.png']);
      expect(bannerNote.value!.text, 'Card image downloaded.');
    });
  });

  testWidgets('Home: "Share card" beside "Invite someone" opens the sheet', (
    tester,
  ) async {
    final state = await makeState();
    usePhone(tester);
    await tester.pumpWidget(inApp(HomeScreen(state: state, showBar: false)));
    await settle(tester);

    final chip = find.byKey(const Key('pot-share-card'));
    await tester.ensureVisible(chip);
    await settle(tester);
    expect(find.text('Share card'), findsOneWidget);
    // Beside "Invite someone", or under it when the line is full (the test
    // font is wide).
    final invite = tester.getRect(find.text('Invite someone'));
    final card = tester.getRect(find.text('Share card'));
    expect(card.left > invite.right || card.top > invite.bottom, isTrue);

    await tester.tap(chip);
    await settle(tester, 12);
    expect(find.byType(ShareSheet), findsOneWidget);
    expect(cardText(tester, 'share-card-name'), 'Morning Movers');
  });

  group('the card\'s words', () {
    test('a short link, a file name, and no ticker', () async {
      final state = await makeState();
      final data = ShareCardData.of(state, state.round!, link: roundLink);
      expect(data.shortLink, [
        'dokind.github.io',
        '/kickoff-bnb-hack',
        '#/r/0x1000…0001',
      ]);
      expect(data.fileName, 'cypher-run-morning-movers.png');
      expect(data.barText, '2 / 6 check-ins');
      expect(data.membersText, '3 members');
      expect(data.message, contains(roundLink));
      for (final words in [data.message, data.description, data.endings]) {
        expect(words, isNot(contains('return')));
        expect(words, isNot(contains('profit')));
      }
      // A build with no web address shares the round's address.
      final bare = ShareCardData.of(state, state.round!, link: '');
      expect(bare.shared, launcher);
    });
  });
}
