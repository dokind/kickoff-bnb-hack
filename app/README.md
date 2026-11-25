# Cypher Run app

Flutter app (web, iOS and Android) for Cypher Run.

**A discipline app with money on it.** You pay a deposit to join and check in
every day you move. Everyone's check-ins fill one bar. When it is full, a
token launches on [Flap](https://flap.sh), and the deposits and the token are
shared by how many days each person showed up. A sponsor is optional.

Everything on chain is BSC testnet (chain id 97) with Flap's free-mint test
USD. Nothing has real value.

## One round, in the app's words

| Step | What the person does | What happens on chain |
|---|---|---|
| Join | "Join for 1,000 USD": get test dollars, then pay the deposit | the wallet calls `mint(address,uint256)` on the test USD token for the deposit amount, then `approve` and `CheckInLauncher.join()` |
| Check in | "Check in today", once per UTC day | the steps go to our server, which answers with the attester's signature; the app sends `checkIn(dayIndex, attesterSignature)` |
| Launch | "Launch the token", open to anyone once the bar is full | `CheckInLauncher.launch()`: the Flap Portal creates the token, the pool gets the sponsor money plus the launch share of the deposits, the vault gets the prize and half the supply |
| Claim | "Claim your share", again whenever trading tax has arrived | `StreakVault.claim()` |
| Refund | "Take your deposit back", if the deadline passes with no launch | `CheckInLauncher.refund()` |
| Sponsor (optional) | "Sponsor the launch pool" | mint if needed, `approve`, `sponsor(amount)`; earns no share, comes back if the round does not launch |

**"Get test dollars" is a visible step on purpose.** It is labelled "Testnet:
free test dollars. On mainnet this step is paying with a stablecoin." The
server's faucet sends test BNB for network fees only, never test USD.

**What our server (the attester) can and cannot do.** It signs that a wallet
moved enough on a day: from phone health data, or self-reported in a browser.
It cannot launch early, block a launch, choose who is paid beyond signing
daily check-ins, or move funds. **Check-ins are attested, not proven.** The
app says this on the second onboarding step, in "How it works" on Home and in
About on the Account screen.

## Screens

The app is exactly these, in a centred 480px column on wide screens.

| Screen | Where | File | What it does |
|---|---|---|---|
| Onboarding | `/onboarding` | `lib/screens/onboarding_screen.dart` | Shown once. Step 1: a hero line, one sentence, one button. The wallet is made silently when the button is pressed and the faucet is asked in the background. Step 2: connect Apple Health / Health Connect ("Allow access", "Not now"); in a browser, a note that the check-in there is self-reported |
| Home | `/` | `lib/screens/home_screen.dart` | The streak as the hero numeral ("7 days"), today's state, the last seven days, and ONE primary action (table below). Under it: the bar (a tick gauge of `totalCheckIns` of `checkInGoal`), the prize so far in dot-matrix numerals beside the launch pool, the members (address, days, streak) and "How it works". Reads the round again every 20 seconds |
| Join | sheet over Home | `lib/screens/join_sheet.dart` | The deposit, its split into prize and launch pool (from `liquidityBps`), what happens if the bar fills or does not, then two steps with progress: "Get test dollars" and "Pay deposit". Waits for the faucet's gas first and says "Preparing your wallet" |
| Check-in | sheet over Home | `lib/screens/checkin_sheet.dart` | Phone: today's steps from the health store against the minimum. Browser: a number field labelled "Self-reported, testnet only". Then the transaction link |
| Sponsor | sheet over Home | `lib/screens/sponsor_sheet.dart` | An amount, prefilled with what the launch pool is short of |
| Result | `/result` | `lib/screens/result_screen.dart` | After the launch: the token address with links to testnet.bscscan.com and `https://flap.sh/bnb-testnet/<token>`, your days, your share (tokens and test USD), Claim. Opens only once the round is launched |
| Account | `/account` | `lib/screens/account_screen.dart` | Address, balances, "Back up key" (shown only after "Show private key"), "Import a key", a small "Start a new round" form, and About with "Built on Flap" |

Home's one primary action (`AppState.stage` in `lib/app_state.dart`):

| State | Action | Notes |
|---|---|---|
| not a member | **Join for 1,000 USD** | opens the join sheet |
| member, not checked in today | **Check in today** | opens the check-in sheet |
| member, checked in today | **Checked in** (disabled) | "Come back tomorrow. The next day starts in 5 h 12 min." |
| bar full, before the deadline | **Launch the token** | anyone, member or not. If the launch pool is under Flap's floor the button is disabled, the hint says how much is missing and "Sponsor the launch pool" appears. A member who has not checked in today also gets "Check in first" |
| launched, you have days | **Claim your share** | opens the result |
| launched, no days | **See the result** | |
| deadline passed, money in the round | **Take your deposit back** | |
| deadline passed, nothing owed | **Round ended** (disabled) | |
| no round on the server | a card with "Look again" | |
| server unreachable | one sentence and "Retry" | |

Membership, days, today's check-in, the deposit, `launched`, `totalCheckIns`
and the launch pool are read from the round's contract; if the chain cannot
be read the server's numbers stand in. The streak, the list of days and the
members list come from the server.

### Starting a round

Account has "Start a new round" for whoever creates rounds: name, deposit,
launch pool share, check-in goal, deadline. The app mines the launch salt
(the token address must end in `7777`), calls `Portal.newLauncher` with the
`CheckInLauncherFactory` and the Portal's 0.005 tBNB salt lock fee, and shows
the new round's address to copy. **It does not tell the server.** Whoever
runs the server sets the current round there (`POST /admin/round` in
`../verifier`); the app then shows it.

Flap will not open a pool under its floor (1,500 test USD today,
`AppConfig.launchPoolFloor`). With a 1,000 USD deposit and a 30% launch share
that is five members, or fewer members plus a sponsor. The form's summary
says so for the numbers picked.

### When something goes wrong

Every failure is one sentence with a way to try again: "Retry" on the card
when the round cannot be loaded, and inside a sheet the sentence appears
above the button, which becomes "Retry". No screen shows a raw exception, a
URL or a host name: `VerifierApi` turns any network failure into "Could not
reach Cypher Run's server. Check your connection and try again.", and
`friendlyError` in `lib/util/format.dart` lets through only sentences written
by this app or by the server.

A check-in the server has signed but the chain has not recorded (the tab was
closed, the transaction failed) is kept on the device for that day; the sheet
then offers "Finish check-in" and does not ask the server twice.

## Look

Rebuilt in Flutter after the teammate's SwiftUI prototype (not a line of its
code is used): the same screens, layout, type, spacing, motion and parts.

- **Background.** Deep ink (`#0A0E11` / `#05080A`) with a drifting aurora:
  nine soft lights on a 3 by 3 grid whose middle points move on 30, 40 and 60
  second waves, under a faint film grain (`AuroraBackground`). Four moods:
  ink (Home, Account, first step), steel (second onboarding step, sheets),
  volt (the result, a finished sheet), danger. It stands still when the
  system or the browser asks for reduced motion, like every other loop.
- **Glass.** Cards blur what is behind them, with a faint white fill and a
  1px rim brightest at the top left; 28px corners, 40px on sheets
  (`GlassSurface`, `GlassCard`).
- **One accent, volt `#D4FF3A`.** Money actions (join, pay, launch, claim),
  the last tick of a gauge, today in the week strip, "You" in the members
  list, the selected tab.
- **Type.** Headlines are Barlow Condensed ExtraBold Italic in capitals
  ("RUN THE STAKES."), titles Barlow Condensed SemiBold, figures light
  tabular Barlow, labels small tracked capitals. Money is set in dot-matrix
  LED numerals (`DotMatrixText`). Fonts come from Google Fonts at run time;
  the app waits up to two seconds for them at start.
- **Parts.** Pill buttons 58 high in four kinds (white, volt with a glow,
  glass, danger) that shrink to 97% when pressed; tick-mark gauges; a week of
  day pills; identicon orbs for addresses; a status badge with a pulsing dot;
  a floating glass tab bar with two round buttons (Home, Account); a glass
  banner that drops from the top for messages.

## Layout

```
lib/
  config.dart               the product name, chain id, RPC URLs, API base, gas price and limits, build values
  main.dart, router.dart    app entry, go_router routes, onboarding redirect
  app_state.dart            one ChangeNotifier: wallet, gas wait, the round, this wallet's place in it, every action
  services/
    chain_service.dart      all chain reads and writes (web3dart): legacy transactions at 1 gwei with explicit gas limits
    verifier_api.dart       all server calls, the texts the device signs and the models they return
    abi.dart                minimal ABI fragments for the functions used
    health_service.dart     the interface; picks one of the two files below at compile time
    health_service_io.dart    phones: today's steps from Apple Health / Health Connect (health package)
    health_service_stub.dart  web: no health store, `available` is false
    wallet_store.dart       device key, onboarding flag and a pending check-in in flutter_secure_storage
  screens/                  onboarding, home, join / check-in / sponsor sheets, result, account
  theme/                    colour and size tokens (dark only), type roles, ThemeData
  widgets/
    aurora.dart             AuroraBackground and its moods, the track on the first screen, the wordmark
    glass.dart              GlassSurface, GlassCard
    controls.dart           PillButton, chips, toggle, glass field, rows
    dot_matrix.dart         DotMatrixText and its font
    gauges.dart             TickGauge, MarkerScale, DayTrack, StatTile
    identicon.dart          Identicon, StatusBadge
    tab_bar.dart, main_tabs.dart   the floating tab bar
    common.dart             the centred column, the banner, sheets, ErrorRetry, LinkRow
    brand.dart              "Built on Flap" and the logo slot
  util/format.dart          amounts, dates, UTC days, friendlyError
assets/brand/               Flap's official logo and its usage notes
web/                        web shell (index.html, manifest, icons)
test/
  services_test.dart        ABI encodings pinned, salt mining, signed texts, VerifierApi against a mock client, config
  state_test.dart           every Home stage, the gas wait, join, check-in (and its retry), claim, refund
  home_test.dart            a widget test for each Home state, plus the bar, prize, members, no round, unreachable
  flow_test.dart            join sheet steps, check-in on web and phone, onboarding and routing, result, account
  design_test.dart          formats, dot-matrix font, gauges, aurora, pills, banner, banned words
  wallet_key_test.dart      the key is always 64 hex characters
```

The Dart package is still called `pacepact` (the first working name) in
`pubspec.yaml`, in test imports and in the iOS and Android identifiers.
Nobody sees it. The name people see is `AppConfig.productName` (the first
screen's line is `AppConfig.heroLine`), plus four
files that cannot read a Dart constant: `web/index.html`,
`web/manifest.json`, `ios/Runner/Info.plist` and
`android/app/src/main/AndroidManifest.xml`. The texts the device signs for
the server start with the same name, so the server must change with it.

## Setup

Requirements: Flutter 3.41 or newer (Dart 3.11), Xcode 16+ for iOS (deployment
target 15.0), Android SDK with minSdk 26.

```sh
cd app
flutter pub get
flutter analyze
flutter test
```

### Build values

Addresses and URLs are build-time values. Nothing is edited in the source.
They are public addresses, not keys; no private key is ever passed to a
build.

| `--dart-define` | What it is | Default |
|---|---|---|
| `CHECKIN_LAUNCHER_FACTORY` | deployed CheckInLauncherFactory (`../contracts`), our Flap Launcher Factory | zero address (placeholder) |
| `STREAK_VAULT_FACTORY` | deployed StreakVaultFactory. Not called by the app; kept with the other addresses | zero address (placeholder) |
| `ATTESTER_ADDRESS` | address of the server's signing key. A round started from the app names it as the attester | zero address (placeholder) |
| `VERIFIER_URL` | the server's base URL. **Phone builds need it.** The web build does not | web: page origin + `/api`; phones: none |
| `WEB_BASE_URL` | where the web build is served, for "Copy invite link" | the page's own address on the web; none on phones |

The three addresses are only needed for "Start a new round". While any of
them is the placeholder, that form shows "This build cannot start a round
yet." with the missing names; joining, checking in, launching and claiming
work without them, because the round's address comes from the server.

```sh
# the static site that gets hosted
flutter build web --release \
  --dart-define=CHECKIN_LAUNCHER_FACTORY=0x... \
  --dart-define=STREAK_VAULT_FACTORY=0x... \
  --dart-define=ATTESTER_ADDRESS=0x...
# output: build/web  (add --base-href /sub/path/ when not served from the root)
```

The two factory addresses are written to
`../contracts/deployments/bsc-testnet.json` by the contracts' deploy script
(`checkInLauncherFactory`, `streakVaultFactory`).

### The server

**Web: nothing to set.** The web build calls the API on the origin it is
served from, under `/api` (`https://your-site.example/api/round`). Host the
server behind that path and the browser needs no CORS and no other host
name. A `VERIFIER_URL` passed to a web build is used instead, except that a
value pointing at `localhost` is ignored unless the page itself is served
from `localhost` (`AppConfig.apiBaseFor`).

**Phones: pass `VERIFIER_URL`.** A phone build made without it shows "This
build has no server address yet."

```sh
flutter run -d chrome --dart-define=VERIFIER_URL=http://localhost:8787
flutter run --dart-define=VERIFIER_URL=https://your-site.example/api
flutter run --dart-define=VERIFIER_URL=http://10.0.2.2:8787   # Android emulator
```

What the app calls (`lib/services/verifier_api.dart`; the tests in
`test/services_test.dart` hold both sides to it):

| Call | Used for |
|---|---|
| `GET /round` | the current round. 404 `{error: "no_round"}` is "no round", not an error. Amounts are read as decimal strings in whole units ("1000", "356.2"); a whole number of 16 digits or more is taken as base units |
| `GET /me/:address` | `streak`, `bestStreak`, `days`, and stand-ins for membership, days and the share when the chain cannot be read. The address is sent in lower case |
| `GET /members` | the members list, a plain JSON array (an object with `members` is also read) |
| `POST /checkin` | `{address, steps, source, signature}`. `source` is `healthkit`, `healthconnect` or `self`. `signature` is personal_sign of `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>` with the launcher in lower case and the day in UTC. The answer is `{day, dayIndex, attesterSignature}` |
| `POST /faucet` | `{address, signature}` with personal_sign of `Cypher Run faucet <address>`, address in lower case. Gas only |

An error answer `{error, message}` shows `message` when it is a sentence; a
bare code is never shown.

### Transactions

Every transaction is a legacy one at 1 gwei with an explicit gas limit
(`GasLimit` in `lib/config.dart`). Fee estimation on BSC testnet answers 1
wei, and a transaction sent at that price is never mined.

| Call | Gas limit |
|---|---|
| `mint` (test USD) | 150,000 |
| `approve` | 100,000 |
| `join` | 250,000 |
| `sponsor` | 200,000 |
| `checkIn` | 200,000 |
| `launch` | 7,000,000 |
| `refund` | 200,000 |
| `claim` | 500,000 |
| `Portal.newLauncher` | 1,000,000 (plus 0.005 tBNB salt lock fee) |

Before each one the app makes sure the wallet holds enough test BNB
(`AppState.ensureGas`): 0.001 for the small ones, 0.0075 before `launch`
(the whole limit must be in the wallet), about 0.0065 before starting a
round. If it does not, it asks the faucet and waits up to 45 seconds for the
transfer, showing "Preparing your wallet".

### Days are UTC

The contract counts a day as `block.timestamp / 86400` and the server accepts
check-ins for today in UTC. The app follows: the phone build reads the steps
recorded since the current UTC day began, the week strip and the "next day
starts in" hint are in UTC days. In Bangkok the day turns at 07:00.

### Web and phone

- **Web** needs https (or `localhost`): the wallet storage only works in a
  secure context. The key is kept in the browser's storage for that site,
  encrypted with a key stored next to it (`flutter_secure_storage` on the
  web). That is weaker than a phone keystore, and clearing site data deletes
  the wallet. Testnet only. Routes live after the `#`, so any static host
  works with no rewrite rules.
- **Web check-in is self-reported.** A browser cannot read health data. The
  server accepts `source: "self"` only when it runs with
  `ALLOW_SELF_REPORTED=true`, and stores those check-ins flagged.
- **Phones** read steps through the `health` package, leaving out manual
  entries. iOS: open `ios/Runner.xcworkspace` once, pick a team under Signing
  and make sure the HealthKit capability is on. Android: Health Connect
  (built in on Android 14+) and an app that writes steps to it.
- The search for a launch salt runs on a background isolate on a phone and in
  short chunks on the page in a browser: about 5 seconds, sometimes 15.

## Not checked

- No transaction has been sent by this build: the new factories are not
  deployed and the new server is not running yet. The chain calls are held to
  the contracts by pinned encodings and by a read-only simulation of the test
  USD mint, not by a mined transaction.
- The iOS and Android builds were not run after this rewrite. The camera
  plugin was removed, so iOS needs `pod install` once.
- Screens were looked at in a browser against stand-in data (phone width and
  1280px), not against a live round.
