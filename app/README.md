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
| Join | "Join Demo Day · 1,000 USD": get test dollars, then pay the deposit | the wallet calls `mint(address,uint256)` on the test USD token for the deposit amount, then `approve` and `CheckInLauncher.join()` |
| Check in | "Check in · Demo Day", once per UTC day | the steps go to our server, which answers with the attester's signature; the app sends `checkIn(dayIndex, attesterSignature)` |
| Launch | "Launch Demo Day", open to anyone once the bar is full | `CheckInLauncher.launch()`: the Flap Portal creates the token, the pool gets the sponsor money plus the launch share of the deposits, the vault gets the prize and half the supply |
| Claim | "Claim · Demo Day", again whenever trading tax has arrived | `StreakVault.claim()` |
| Refund | "Deposit back · Demo Day", if the deadline passes with no launch | `CheckInLauncher.refund()` |
| Sponsor (optional) | "Sponsor the token pool" | mint if needed, `approve`, `sponsor(amount)`; earns no share, comes back if the round does not launch |

**"Get test dollars" is a visible step on purpose.** It is labelled "Testnet:
free test dollars. On mainnet this step is paying with a stablecoin." The
server's faucet sends test BNB for network fees only, never test USD.

**What our server (the attester) can and cannot do.** It signs that a wallet
moved enough on a day: from phone health data, or self-reported in a browser.
It cannot launch early, block a launch, choose who is paid beyond signing
daily check-ins, or move funds. **Check-ins are attested, not proven.** The
app says this on the second onboarding step, in "How it works" on Home and in
About, a sheet opened from the Wallet screen.

## Many rounds

Anyone can start a round, so there are several at once. **Home shows every
round as a card in a slider at the top**, and the card in view is the
selected round: the streak, the days, the one primary action, the prize and
the members under it are all about that round.

- **Which rounds.** Every round in the server's public list (`GET /rounds`),
  plus any round this device opened by its link or started itself, listed or
  not. Those extra rounds are kept on the device (`showup.rounds` in the
  wallet storage) with the round last chosen.
- **Order.** The server's featured round first, then the rounds this wallet
  has joined, then open rounds by nearest deadline, launched ones, ended
  ones. "Joined" is read from each round's contract (`isMember`).
- **It moves by itself** to the next card every 5 seconds, and from the last
  back to the first, **but only until the person first touches Home** (a
  tap, a scroll, a swipe, a mouse wheel or a trackpad scroll, anywhere on
  the screen). From that touch on the cards stay where the person leaves
  them until the app is opened again (in a browser: until the page is
  loaded again). A card that had just begun to slide in when the touch came
  goes back. Before any touch it also stays put while a sheet, a dialog or
  another screen is over Home, while a transaction is being sent, while a
  mouse rests on the cards, and when the cards are scrolled out of view. It
  never moves by itself when the app was opened from a round's link
  (`/r/<launcher>`, or a link pasted under + > Open an invite link), with
  reduced motion (the system setting, or `prefers-reduced-motion` in a
  browser) or with a screen reader. Dots under the cards show where you
  are; a tap on a dot goes there, and a mouse can drag the cards. See "The
  action is for the round it names" below for why.
- **One round** is a plain card: nothing to swipe, no dots.
- **Remembered.** The round the person chose (a swipe, a dot, a link, a new
  round) is selected again at the next launch. A card that came by itself is
  not remembered.

### Round links

Every round has a link: `<web address>/#/r/<launcher>`, for example
`https://your-site.example/#/r/0x378d…edb5`. Opening it opens the app with
that round selected. A first-time visitor goes through the two onboarding
steps first and lands on the round after them. A link to an address that is
not one of our rounds says "That link does not lead to a round."

"Invite" on a round's card (and "Invite someone" under its members) opens a
sheet with the link, "Copy link" and a QR code of the same link.

Phone builds have no web address unless `WEB_BASE_URL` is set; without it the
sheet hands out the round's address instead. Phone builds also do not catch
`https://` links from other apps (no universal links are set up), so a link
or an address is pasted under **+ > Open an invite link** (the "+" in the
tab bar opens "Add a round").

### Unlisted rounds

The new-round screen has an **Unlisted** switch under "More options". Its
helper line is the whole
truth of it: "Not shown in the public list. Anyone with the link can still
join, and the chain is public."

Unlisted is not a secret and not private data. The round is a public
contract on a public chain: anyone who reads the factory's events finds it,
and anyone who has the link can open it, join it and pass the link on. The
only thing the switch changes is whether the server puts the round in
`GET /rounds`.

After the round is created the app tells the server the choice with
`POST /rounds`, signed by the wallet that created the round. On the device
that started the round, the invite sheet keeps the switch, so the creator
can change it later. If the server did not save the choice (it has not found
the round on chain yet, or it is an older server), the form says so with
"Save again", the choice stays on the device, and the app asks again by
itself each time it reads the rounds. Until an unlisted choice is saved the
server may show the round: it lists a round nobody registered three minutes
after its creation.

## Screens

The app is exactly these, in a centred 480px column on wide screens.

| Screen | Where | File | What it does |
|---|---|---|---|
| Onboarding | `/onboarding` | `lib/screens/onboarding_screen.dart` | Shown once. Step 1: a hero line, one sentence, one button. The wallet is made silently when the button is pressed and the faucet is asked in the background. Step 2: connect Apple Health / Health Connect ("Allow access", "Not now"); in a browser, a note that the check-in there is self-reported |
| Home | `/` (and `/r/<launcher>`) | `lib/screens/home_screen.dart`, `lib/widgets/round_slider.dart` | At the top the round cards: name, a state chip (Open, Bar full, Launched, Ended), the bar (a tick gauge of `totalCheckIns` of `checkInGoal`), prize so far, members, the deadline, "You're in" for a member, "Unlisted" where it applies, and "Invite". Under the selected card: the streak as the hero numeral ("7 days"), today's state, the last seven days, the prize so far in dot-matrix numerals beside the token pool, the members (address, days, streak) and "How it works". ONE primary action (table below) floats at the bottom on a scrim that is opaque behind it. Reads the rounds again every 20 seconds |
| Invite | sheet over Home | `lib/screens/invite_sheet.dart` | The round's link, "Copy link" and a QR code of it. On the device that started the round: the "Unlisted" switch |
| Join | sheet over Home | `lib/screens/join_sheet.dart` | The round's name over the title. The deposit, its split into prize and token pool (from `liquidityBps`), what happens if the bar fills or does not, then two steps with progress: "Get test dollars" and "Pay deposit". Waits for the faucet's gas first and says "Preparing your wallet" |
| Check-in | sheet over Home | `lib/screens/checkin_sheet.dart` | The round's name over the title. Phone: today's steps from the health store against the minimum. Browser: a number field labelled "Self-reported, testnet only". Then the transaction link |
| Sponsor | sheet over Home | `lib/screens/sponsor_sheet.dart` | The round's name over the title. An amount, prefilled with what the token pool is short of |
| Result | `/result` | `lib/screens/result_screen.dart` | After the launch: the round's name over the title, the token address with links to testnet.bscscan.com and `https://flap.sh/bnb-testnet/<token>`, your days, your share (tokens and test USD), Claim. Opens only once the round is launched |
| Wallet | `/account` (also `/wallet`) | `lib/screens/account_screen.dart` | Your money and your key, nothing about rounds. The balance card first (test USD in dot-matrix numerals, test BNB for network fees, "Get test dollars"), then one list: "Address" (press to copy), "Back up your key" (a sheet; the key shows only after "Show key" and is hidden again each time the sheet opens), "Use another wallet" (a sheet: paste a key) and "About" (a sheet with "Built on Flap") |
| Add a round | sheet, from the "+" in the tab bar | `lib/screens/add_round_sheet.dart` | Two rows: "Start a round" (opens `/new`) and "Open an invite link" (the sheet becomes one field for a link or an address; on success the app goes Home with that round selected). The "+" is an action, not a place: it is never the selected tab |
| New round | `/new` | `lib/screens/new_round_screen.dart` | A full screen with a back control and no tab bar. Name, deposit, goal, how long it runs; the token pool's share and the "Unlisted" switch under "More options"; "The deal" (the choices in money, line by line); "Start round" pinned at the bottom. After it the same screen says "Round started" with the round's name, "Invite people", "Go to round" and whether the server saved the listing |

Home's one primary action, for the selected round (`AppState.stage` in
`lib/app_state.dart`). Every action that does something names its round,
here "Demo Day":

| State | Action | Notes |
|---|---|---|
| not a member | **Join Demo Day · 1,000 USD** | opens the join sheet |
| member, not checked in today | **Check in · Demo Day** | opens the check-in sheet |
| member, checked in today | **Checked in** (disabled) | "Come back tomorrow. The next day starts in 5 h 12 min." |
| bar full, before the deadline | **Launch Demo Day** | anyone, member or not. If the token pool is under Flap's floor the button is disabled, the hint says how much is missing and "Sponsor the token pool" appears. A member who has not checked in today also gets "Check in first" |
| launched, you have days | **Claim · Demo Day** | opens the result |
| launched, no days | **See the result · Demo Day** | |
| deadline passed, money in the round | **Deposit back · Demo Day** | |
| deadline passed, nothing owed | **Round ended** (disabled) | |
| no round anywhere | a card with "Look again" | |
| server unreachable | one sentence and "Retry" | |

For the selected round, membership, days, today's check-in, the deposit,
`launched`, `totalCheckIns` and the token pool are read from the round's
contract; if the chain cannot be read the server's numbers stand in. The
streak, the list of days and the members list come from the server. The
other cards show the server's numbers, and "You're in" from one `isMember`
read per round.

**The action is for the round it names.** The cards used to keep moving
while a person was about to press the action, so a press meant for one
round could land on the next. Three things stop that
(`test/safe_action_test.dart` holds each):

1. The cards move by themselves only until the first touch on Home in this
   session (above). `AppState.autoAdvance` is the switch; it is not stored.
2. The label names the round. A long name is cut short with an ellipsis
   inside the label and the words around it stay ("Join The Saturday
   Morni… · 500 USD"), so the label is always one line (`PillButton.shrink`).
   A screen reader gets the whole label. The join, check-in and sponsor
   sheets and the result show the name over their title (`RoundLabel`).
3. The press is for the round the label named. The round's address is taken
   where the label is made and handed to the sheet or to the action
   (`AppState.payDeposit(launcher:)`, `checkIn`, `sponsor`, `launch`,
   `refund`, `claim`), never read again from the selection later. A sheet
   shows and acts on its own round for as long as it is open, whatever card
   is in view behind it. The button itself is a new button for each round,
   so a press that began on one round's button is dropped if the round
   under it changes before the finger lifts.

**The floating action.** The hint line and the button sit over the scrolling
content. Behind them is a scrim (`BottomFade`) in the background colour that
is clear at its top edge and fully opaque 48px lower, where the hint line
starts, so nothing shows through the text. The content's bottom padding is
the measured height of the floating area plus 16px, so the last card scrolls
fully above it whatever the area holds (it is taller when "Sponsor the
token pool" is there).

### Starting a round

The "+" in the tab bar opens "Add a round"; "Start a round" there opens the
new-round screen (`/new`): name, deposit, check-in goal, how long it runs,
and under "More options" the token pool's share and the "Unlisted" switch. The app mines the launch salt
(the token address must end in `7777`), calls `Portal.newLauncher` with the
`CheckInLauncherFactory` and the Portal's 0.005 tBNB salt lock fee, and then:

1. puts the new round on this device's slider at once and selects it, from
   the values just sent to the chain (it does not wait for the server);
2. registers it with the server: `POST /rounds {launcher, unlisted,
   signature}`, signed by the creating wallet;
3. opens the invite sheet with the new round's link.

Nobody has to set anything on the server for the round to show: the server
finds every round our factory created from the chain. Which round is
*featured* (first on everyone's slider, and the one the old single-round
calls answer for) is still set on the server (`POST /admin/round` in
`../verifier`).

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
  ink (Home, Wallet, first step), steel (second onboarding step, sheets),
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
  a floating glass tab bar with three round buttons (Home, "+", Wallet; the
  "+" is an action and is never the selected one); a glass
  banner that drops from the top for messages.

## Layout

```
lib/
  config.dart               the product name, chain id, RPC URLs, API base, gas price and limits, build values
  main.dart, router.dart    app entry, go_router routes, onboarding redirect, round links (/r/<launcher>)
  app_state.dart            one ChangeNotifier: wallet, gas wait, the rounds and their order, the selected round, this wallet's place in it, every action
  services/
    chain_service.dart      all chain reads and writes (web3dart): legacy transactions at 1 gwei with explicit gas limits
    verifier_api.dart       all server calls, the texts the device signs and the models they return
    abi.dart                minimal ABI fragments for the functions used
    health_service.dart     the interface; picks one of the two files below at compile time
    health_service_io.dart    phones: today's steps from Apple Health / Health Connect (health package)
    health_service_stub.dart  web: no health store, `available` is false
    wallet_store.dart       device key, onboarding flag, a pending check-in, and the rounds this device knows with the one last chosen, in flutter_secure_storage
  screens/                  onboarding, home, join / check-in / sponsor / invite / add-a-round sheets, new round, result, wallet (account_screen.dart)
  theme/                    colour and size tokens (dark only), type roles, ThemeData
  widgets/
    aurora.dart             AuroraBackground and its moods, the track on the first screen, the wordmark
    glass.dart              GlassSurface, GlassCard
    controls.dart           PillButton, chips, toggle, glass field, rows
    dot_matrix.dart         DotMatrixText and its font
    gauges.dart             TickGauge, MarkerScale, DayTrack, StatTile
    identicon.dart          Identicon, StatusBadge
    round_slider.dart       RoundSlider (the cards, the dots, moving on by itself) and RoundCard
    tab_bar.dart, main_tabs.dart   the floating tab bar
    common.dart             the centred column, the banner, sheets, the bottom scrim, ErrorRetry, LinkRow
    brand.dart              "Built on Flap" and the logo slot
  util/format.dart          amounts, dates, UTC days, friendlyError
assets/brand/               Flap's official logo and its usage notes
web/                        web shell (index.html, manifest, icons)
test/
  services_test.dart        ABI encodings pinned, salt mining, signed texts, VerifierApi against a mock client, config
  state_test.dart           every Home stage, the gas wait, join, check-in (and its retry), claim, refund
  rounds_test.dart          the /rounds calls, the pinned registration text and signatures, invite link text, the slider's order, selection and what is remembered, rounds opened by link, starting and listing a round, the fallback to a single-round server
  slider_test.dart          the cards and dots, moving on every 5 seconds until a touch (fake timers), reduced motion, the invite sheet and its QR, the scrim and the room under the content
  safe_action_test.dart     the action is for the round it names: no moving on after the first touch, with a sheet or dialog open, from a round link or with reduced motion; the round's name on the action (and cut short when long) and over the sheets' titles; a sheet keeps its round when the selection changes behind it
  home_test.dart            a widget test for each Home state, plus the bar, prize, members, no round, unreachable
  flow_test.dart            join sheet steps, check-in on web and phone, onboarding and routing, /r/<launcher> with and without a wallet, result, Wallet and its sheets, the "+" and "Add a round", the new-round screen (the deal, the "Unlisted" switch, the registration call, the done state)
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
| `WEB_BASE_URL` | where the web build is served: the start of every round's invite link (`<WEB_BASE_URL>/#/r/<launcher>`) | the page's own address on the web; none on phones (the invite sheet then hands out the round's address) |

The three addresses are only needed to start a new round (`/new`). While any of
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
`test/services_test.dart` and `test/rounds_test.dart` hold both sides to it):

| Call | Used for |
|---|---|
| `GET /rounds` | the public list: `{rounds: [...]}`, each entry with `launcher`, `name`, `deposit`, `liquidityBps`, `checkInGoal`, `totalCheckIns`, `memberCount`, `prizeNow`, `poolQuoteNow`, `deadline`, `launched`, `token`, `vault`, `state` and `featured`. Amounts are read as decimal strings in whole units ("1000", "356.2"); a whole number of 16 digits or more is taken as base units. The app orders the cards itself and works out open / launched / ended from `launched` and `deadline` |
| `GET /rounds/:launcher` | one round in full, listed or not, with `minSteps` and `unlisted`. Asked for the selected round and for every round this device knows that the list leaves out. 404 `{error: "no_round"}` means our factory did not create it |
| `GET /rounds/:launcher/me/:address` | `streak`, `bestStreak`, `days`, and stand-ins for membership, days and the share when the chain cannot be read. Addresses are sent in lower case |
| `GET /rounds/:launcher/members` | the members list, a plain JSON array (an object with `members` is also read) |
| `POST /rounds/:launcher/checkin` | `{address, steps, source, signature}`. `source` is `healthkit`, `healthconnect` or `self`. `signature` is personal_sign of `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>` with the launcher in lower case and the day in UTC. The answer is `{day, dayIndex, attesterSignature}` |
| `POST /rounds` | `{launcher, unlisted, signature}` with personal_sign of `Cypher Run round <launcher> <listed|unlisted>` (launcher in lower case) by the wallet that created the round. The answer is `{launcher, unlisted}`. Sent after "Start round" and when the creator flips the switch in the invite sheet |
| `POST /faucet` | `{address, signature}` with personal_sign of `Cypher Run faucet <address>`, address in lower case. Gas only |

**An older server.** A server from before `/rounds` answers 404 to
`GET /rounds`. The app then uses that server's single-round calls instead
(`GET /round`, `GET /me/:address`, `GET /members`, `POST /checkin`, same
bodies and the same signed text) and Home is one plain card, as before. It
asks `GET /rounds` again on every read, so the same build moves to the
per-round calls as soon as the server has them; a build can ship before or
after the server. While the server is the older one, a round started from
the app still shows on its creator's device (with the chain's numbers), its
listing is registered once the server is updated, and a check-in for any
round but the server's current one says the server cannot sign it yet.

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

- **The per-round server calls: reads were checked against the real
  server, writes were not.** On 26 November 2026 the hosted server got the
  build with `/rounds`. This app's own client (`VerifierApi`) then read
  `GET /rounds`, `GET /rounds/:launcher`, `.../me/:address` and
  `.../members` from the real server code against BSC testnet, and every
  field of a list entry equalled the same round read in full. The hosted
  web build, opened at `/#/r/<launcher>` at phone width, showed "3 rounds",
  the linked round's card, the cards moving by themselves and the Invite
  sheet ([../HOSTING.md](../HOSTING.md)); that was the build before "The
  action is for the round it names", and a build since then stays on the
  linked round. Not checked: `POST /rounds` with a
  round creator's key against that server (only a refusal, 401, for a wallet
  that is not the creator), and a check-in through
  `POST /rounds/:launcher/checkin` followed by its transaction. Before that
  day the app's side was held by tests against an in-memory server and a
  stand-in server with five made-up rounds, and against the earlier hosted
  server the build fell back to the single-round calls and showed one card.
- **The action is for the round it names: held by widget tests, not by a
  person's finger.** Stopping at the first touch, the names on the action
  and the sheets, and a sheet keeping its round are in
  `test/safe_action_test.dart` with fake timers. Nobody has tried them by
  hand on a phone or with a real mouse wheel and trackpad in a browser, and
  the cut of a long name was measured with the test font, not with Barlow.
- **No transaction was sent while making this change.** "Start a new round"
  with the switch on, the `POST /rounds` that follows it, joining and
  checking in from a second round were not run on chain; the chain calls are
  the ones the earlier build already used, plus one new read (`isMember`).
- **Phones.** After this change the iOS app was built for the simulator
  (debug) and for a device (release) with the hosted addresses; neither was
  installed or run, and the Android build was not built. A phone build does
  not open `https://.../#/r/...` links from other apps; the link or the
  address is pasted under Account > Open a round.
- **Many rounds at once.** With several rounds the app makes one `isMember`
  read per round every 20 seconds, and reads the selected round again when
  the card changes (at most once every 30 seconds per round when the cards
  move by themselves). This was not measured against the public RPC with
  more than five rounds.
- Wide windows: the scrim under the floating action is as wide as the 480px
  column, so on a wide window it reads as a darker panel with soft sides.
