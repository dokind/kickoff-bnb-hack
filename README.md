# Cypher Run

Cypher Run is a discipline app with money on it. You pay a deposit to join and check in
every day you move, and everyone's check-ins fill one bar. When the bar is full, a token launches on
[Flap](https://flap.sh) Pool Launch, and the deposits and the token are shared by how many days each
person showed up; a sponsor is optional. The working name was "Showup": the deployed contracts keep
it in their on-chain description, and the first testnet round is named after it.

Built at BNB Hack Bangkok (November 2026) for Flap's track "invent a new way to launch a token on
Flap Pool Launch". BNB Smart Chain testnet only (chain 97): test BNB and Flap's free-mint test USD.
Nothing here has real value.

**What is new about the launch.** Money alone does not launch the token. The launch opens only when
the members have shown up often enough together, counted on chain, and then **anyone** can send the
launch transaction: no operator, no admin, not our server. If the group never shows up, there is no
token and everyone takes their money back.

## How a round works

One Launcher contract is one round. It is created through the Flap Portal with our own Launcher
Factory (`Portal.newLauncher` with `CheckInLauncherFactory`).

| Step | What happens | Contract call |
|---|---|---|
| **Join** | A wallet pays the round's fixed deposit once, in test USD, and becomes a member. | `CheckInLauncher.join()` |
| **Sponsor** (optional) | Anyone may add test USD. It goes to the launch pool only and earns no share. | `sponsor(amount)` |
| **Check in** | A member checks in once per UTC day. Each check-in needs our server's signature for that wallet and day, and adds 1 to the member's days and to the bar. | `checkIn(day, signature)` |
| **Launch** | Once the bar is full (`totalCheckIns >= checkInGoal`) and before the deadline, anyone calls it, once. The pool gets all sponsor money plus 30% of the deposits (`liquidityBps`) and half the token supply; Flap burns the LP. The other 70% of the deposits, the prize, and the other half of the supply go to the round's vault. The token has a 3% buy and 5% sell tax; 80% of the tax flows to the vault and 20% is burned. | `launch()` |
| **Claim** | A member with `d` days receives `d / totalCheckIns` of the reserved tokens, once, and the same fraction of the test USD the vault has received (prize plus trading tax), again whenever more tax has arrived. A member with no days gets nothing. There is no settle step and no list. | `StreakVault.claim()` |
| **Refund** | If the deadline passes without a launch, each member takes the full deposit back and each sponsor their contribution. | `refund()` |

An example with the numbers the tests use: three members at 1,000 test USD, 30% to the pool. The
pool would get 900, under the 1,500 test USD floor Flap's Portal enforces today, so a sponsor adds
600. At launch the pool gets 1,500 and the vault gets the 2,100 prize and 500,000 tokens. With days
3, 2 and 1 the members receive 3/6, 2/6 and 1/6 of the tokens and of the prize plus tax.

## Enforced on chain, and attested by our server

| Enforced by the contracts | Attested by our server |
|---|---|
| Who is a member, and that everyone paid the same deposit once | **That a wallet moved enough on a given day.** The server signs a daily check-in after it accepts a report: steps from the phone's health data, or a number typed in on the web (self-reported, testnet demo only). |
| One check-in per wallet per UTC day, for today or yesterday only, members only, closed at launch | |
| The count: `daysOf[wallet]`, `totalCheckIns`, the goal, the deadline | |
| Launch only with a full bar, only before the deadline, only once, callable by anyone | |
| The split: sponsor money plus `liquidityBps` of the deposits to the pool, the rest to the vault | |
| Claims in proportion to days; refunds in full after a missed deadline | |
| Nobody can withdraw from the Launcher or the vault: not the attester, a sponsor, the creator or the deployer | |

The attester is one address, fixed when the round is created: the key of our server.

- **Check-ins are attested, not proven.** The contract cannot see anyone's activity and takes the
  signature as given. The server can sign for a member who did not move, or refuse to sign for one
  who did, and it cannot verify a step count a client sends. Members rely on the operator of that
  server for this, and for nothing else.
- **What the attester cannot do.** It cannot launch early (the bar needs `checkInGoal` check-ins,
  each from a wallet that paid a deposit, at most one per wallet per day). It cannot block or delay
  a launch once the bar is full (`launch()` is open to anyone). It cannot choose who is paid other
  than by signing or not signing daily check-ins. It cannot move funds: it has no function on
  either contract and receives nothing.
- **If it stops signing**, the bar never fills, and after the deadline everyone is refunded.
- Flap's Guardian can upgrade the Launcher and vault implementations, as in Flap's own example.

## Parts

```
 web / phone app (Flutter) ──signed daily report──►  server (Node, Hono): the attester
        │                  ◄──attester signature, round, streaks, gas faucet──
        │
        │ join, sponsor, checkIn(day, signature), launch, claim, refund
        ▼
  CheckInLauncher ──launch(), anyone──► Flap Portal ──► token + pool + StreakVault
```

| Part | Folder | What it does |
|---|---|---|
| Contracts | [`contracts/`](contracts) | `CheckInLauncherFactory`, `CheckInLauncher`, `StreakVaultFactory`, `StreakVault` (Solidity 0.8.26, Foundry), forked from Flap's Crowd launcher and vault example. They hold the deposits, the sponsor money, the reserved tokens and the tax, and apply the rules above. |
| Server | [`verifier/`](verifier) | HTTP server (Hono, viem). Accepts a member's daily report and signs the check-in; relays what the chain says about the current round; keeps streaks and the members it has seen; sends a new wallet 0.03 test BNB once for gas. It sends no transaction to the Launcher or the vault. |
| App | [`app/`](app) | One Flutter app, our own UI. Web build (main): onboarding with a silent device wallet, Home with one action that follows the round (join, check in, launch, claim, refund), sponsor, result, account. Phone build: the same, plus steps from Apple Health / Health Connect. |
| Scripts | [`scripts/`](scripts) | `deploy-testnet.sh` deploys the factories and prints the app build commands. `run-round.ts` runs one whole round on testnet. |

Each part's README has the full reference: [`contracts/README.md`](contracts/README.md),
[`verifier/README.md`](verifier/README.md), [`app/README.md`](app/README.md).

## Deployed on BSC testnet

Deployed 25 November 2026 from `0xc1bD6aC9311b9345ae8023201875518429c8BF58`; the record is
[`contracts/deployments/bsc-testnet.json`](contracts/deployments/bsc-testnet.json).

| Contract | Address | Deployment transaction |
|---|---|---|
| `CheckInLauncherFactory` (our Launcher Factory) | [`0x2A872200B83dD025977d785cDE05356d23eA4153`](https://testnet.bscscan.com/address/0x2A872200B83dD025977d785cDE05356d23eA4153) | [`0x827f9b4e404217a35e75fbef0f9ea0012f1c3e0d490ac87a88e31c44079c094c`](https://testnet.bscscan.com/tx/0x827f9b4e404217a35e75fbef0f9ea0012f1c3e0d490ac87a88e31c44079c094c) |
| `StreakVaultFactory` | [`0x0652AAD1d659344f6EdB9572723479aaece144Be`](https://testnet.bscscan.com/address/0x0652AAD1d659344f6EdB9572723479aaece144Be) | [`0x19a6d3aa23f2d6e5458965070462f1411a62256d67403f8127232b4fa1deb2a6`](https://testnet.bscscan.com/tx/0x19a6d3aa23f2d6e5458965070462f1411a62256d67403f8127232b4fa1deb2a6) |

| Fixed address | |
|---|---|
| Attester (our server's key; also the faucet wallet) | `0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7` |
| Flap Portal | `0x000042108465206185A077Edc3F3fd2b49060000` |
| Test USD (quote token, 18 decimals, anyone can mint) | `0x190C989D5665a0e404B444b53CAE9AbCfb600157` |

Two rounds have been opened with these factories on testnet: one complete ("Bangkok Showup",
Launcher `0xe1c165C295ED8bC0abA2a81c2a524564689BCeAB`) and one left open for the demo ("Demo Day",
Launcher `0x378d729aE7122e5Cf7d6f4ed8797710d2503EDb5`). Every address and transaction is in
[PROOF.md](PROOF.md).

## What the three parts agree on

Checked by tests on each side and by the fork run described under "Status".

- **Round config.** `Portal.newLauncher(factory, abi.encode(config))`, where `config` is one tuple
  `(string name, string symbol, string meta, bytes32 salt, uint256 deposit, uint256 liquidityBps, uint256 checkInGoal, uint256 deadline, address attester)`.
  The same 480-byte vector is pinned in `contracts/test/CheckInLauncher.t.sol` and
  `app/test/services_test.dart` and equals `cast abi-encode` of the tuple. The salt is mined from a
  random start so the token address ends in `0x7777`.
- **Check-in signature.** `inner = keccak256(abi.encode(uint256 chainId, address launcher, address wallet, uint256 day))`
  with `day = unix time / 86400`; the attester signs `inner` with personal_sign (EIP-191), 65 bytes.
  One worked vector is pinned in the contracts' test, reproduced byte for byte by
  `verifier/test/attest.test.ts`, and the app's `checkIn(day, signature)` calldata for it equals
  `cast calldata`.
- **Texts a member signs** (personal_sign): `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>` and
  `Cypher Run faucet <address>`. The app writes addresses in lower case; the server accepts lower case
  or checksummed. The product name is one constant in the server and one in the app
  (`verifier/src/product.ts`, `app/lib/config.dart`); renaming it changes the signed texts on both
  sides. `contracts/src/Product.sol` still says "Showup": it is only used in the description the
  deployed contracts report, and they were not redeployed.
- **API.** `GET /round`, `GET /me/:address`, `GET /members`, `POST /checkin`, `POST /faucet`,
  `POST /admin/round`, each also under `/api`. Amounts are decimal strings in whole tokens. The web
  build calls the API on its own origin under `/api`.
- **Days are UTC** everywhere. The server signs for today only; the contract also accepts yesterday.
- **Transactions** are legacy type at 1 gwei with explicit gas limits, from the app, the server and
  the scripts. Fee estimation on this testnet answers 1 wei and such transactions are never mined.
  `launch()` uses about 5,000,000 gas; the limit is 7,000,000.
- **Flap's pool floor.** The Portal refuses a launch whose pool is under 1,500 test USD today (Flap
  can change it). `poolQuoteNow()` shows what the pool would get; below the floor `launch()` reverts
  and nothing changes, so a sponsor can top up and anyone can call it again.

## Setup

You need [Foundry](https://getfoundry.sh), Node.js 22 or newer, and Flutter 3.41 or newer. Never put
a real key in a file that is committed: each part has a `.env.example` with placeholder names, and
`.env` is git-ignored. Use throwaway testnet keys only.

```sh
# Contracts
cd contracts
./install-deps.sh        # forge-std, OpenZeppelin and solady at pinned commits into lib/
cp .env.example .env     # BSC_TESTNET_RPC_URL; PRIVATE_KEY only when deploying
forge test               # 63 unit tests; the fork suite is skipped when BSC_TESTNET_RPC_URL is empty
BSC_TESTNET_RPC_URL=https://bsc-testnet-rpc.publicnode.com forge test   # 68, with 5 fork tests

# Server
cd verifier
npm install
cp .env.example .env     # RPC_URL, ATTESTER_PRIVATE_KEY, ADMIN_TOKEN; see the comments in the file
npm run dev              # http://localhost:8787 (the same routes also under /api)
npm test && npm run typecheck

# App
cd app
flutter pub get
flutter analyze && flutter test
flutter run -d chrome --dart-define=VERIFIER_URL=http://localhost:8787
```

## Deploy

The factories are already deployed (addresses above). To deploy again:

```sh
scripts/deploy-testnet.sh --dry-run   # simulates the deploy; sends nothing, writes nothing
scripts/deploy-testnet.sh             # asks, then deploys the two factories (about 0.014 test BNB)
scripts/deploy-testnet.sh --print     # prints the app commands for the last deploy again
```

It runs `forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast --slow --legacy
--with-gas-price 1000000000` from `contracts/`, checks that both factories have code, and prints the
app build commands. The web build that is hosted:

```sh
cd app
flutter build web --release \
  --dart-define=CHECKIN_LAUNCHER_FACTORY=0x2A872200B83dD025977d785cDE05356d23eA4153 \
  --dart-define=STREAK_VAULT_FACTORY=0x0652AAD1d659344f6EdB9572723479aaece144Be \
  --dart-define=ATTESTER_ADDRESS=0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7
```

`ATTESTER_ADDRESS` must be the address of the server's key (`ATTESTER_PRIVATE_KEY`, or the earlier
name `VERIFIER_PRIVATE_KEY`, in `verifier/.env`). A round created with another attester cannot get
check-ins signed by this server. Phone builds also take `--dart-define=VERIFIER_URL=https://<site>/api`.

Hosting (the web build and the server on one HTTPS address, `/` and `/api/`) is described in
[HOSTING.md](HOSTING.md). The server needs `ALLOW_SELF_REPORTED=true` for check-ins typed in a
browser and `FAUCET_ENABLED=true` for the gas faucet.

## Demo

**A whole round by script.** With the server running (hosted or `npm run dev`) and
`ALLOW_SELF_REPORTED=true`:

```sh
cd verifier && VERIFIER_URL=https://<host>/api npx tsx ../scripts/run-round.ts
```

It opens a round with the deployer key, points the server at it, funds three throwaway members who
join with 1,000 test USD each, sponsors the 600 the pool is short of, checks two of them in through
the server (source "self"), launches from a member wallet, trades on the pool so tax reaches the
vault, and claims. The member who never checked in is shown to get nothing. Settings and the
two-day variant (`CHECKIN_GOAL=3`, a 2 : 1 : 0 split) are at the top of
[`scripts/run-round.ts`](scripts/run-round.ts). The step counts it reports are made up by the
script and sent as self-reported; everything on chain is real.

**Live in a browser.** Leave a round one check-in short and finish it in the app:

1. `CHECKIN_GOAL=3 ... npx tsx ../scripts/run-round.ts` stops with the bar at 2 of 3.
2. Open the hosted site. Onboarding makes a wallet on the device and the faucet sends it gas.
3. **Join**: "Get test dollars" (the wallet mints the deposit; on mainnet this step is paying with a
   stablecoin), then "Pay deposit".
4. **Check in today**: type a step count (self-reported on the web). The bar fills.
5. **Launch the token**, from this ordinary wallet. The result screen shows the token and your share.
6. **Claim your share.** Run the script again for the trading and the other members' claims.

A round can also be opened from the app (Account, "Start a new round"); the server is then pointed
at the new address with `POST /api/admin/round`.

Things to know before a demo: days are UTC, so a new day starts at 07:00 in Bangkok and one wallet
can check in once per day; the pool must reach 1,500 test USD (five members at 1,000, or fewer plus
a sponsor); the phone build counts steps since 00:00 UTC against the server's `MIN_STEPS` (1,000).

## Status

Checked on 25 November 2026.

Done and checked:

- **Contracts.** 68 tests pass with a BSC testnet RPC (5 of them whole rounds against the live
  Portal on a fork), 63 pass without one with the fork suite skipped. The two factories are deployed
  on BSC testnet; both addresses have code and the Launcher factory reads back its paired vault
  factory, the Portal and the test USD token.
- **Server.** 83 tests in 7 files pass and the strict typecheck passes.
- **App.** `flutter analyze` is clean, 114 tests pass (one more, the fork test below, is skipped
  unless it is given a fork), and the web release build succeeds with the deployed addresses.
- **All three together, on a local fork of BSC testnet taken after the deploy** (so the deployed
  factories themselves, the real server code with its real key, no mocks; nothing sent to the real
  testnet):
  - `scripts/run-round.ts` ran a whole round: open through the Portal, three joins, a 600 sponsor,
    two check-ins signed by the server and accepted by the contract, `launch()` refused while the
    bar was short and then sent by a member (4.64M gas), a claim straight after launch, trading,
    37.17 test USD of tax to the vault, and final claims of 1,068.59 test USD and 250,000 tokens
    each for the two members who checked in. The Launcher was left holding nothing.
  - A second round was left one check-in short and finished by the app's own state and service code
    (`app/test/fork_e2e_test.dart`): a new wallet got gas from the server's faucet, minted the
    deposit, joined, checked in, launched and claimed, and the numbers from the server and from the
    chain agreed at every step. The script then picked the round up again for trading and claims.

- **Two rounds on the real testnet, against the hosted server** ([PROOF.md](PROOF.md)). Round 1
  ran from open to the last claim: three joins at 500 test USD, a 1,050 sponsor, three check-ins
  (days 2, 1 and 0), `launch()` sent by a member (4.64M gas), 183.48 test USD of trading tax to the
  vault, and claims of 2/3 and 1/3. The server's `/api/round` and `/api/me` matched the chain at
  each of nine stages. Round 2 is open with the bar at 2 of 5 and is the round the hosted app
  shows. The trading tax was dispatched to the vault by an outside account within a few blocks of
  each sale; the script did not have to call `dispatch()`.

Not done or not checked:

- The check-ins in both testnet rounds were self-reported test entries from throwaway wallets made
  by `scripts/run-round.ts`, and one of them (round 1, for the day before) was signed by the script
  with the attester key and not through the server. [PROOF.md](PROOF.md) says which.
- The fork test drives the app's state and services, not the screens. The screens were looked at in
  a browser against a stand-in server only. Nobody has clicked through the hosted web app against a
  real round.
- The phone builds were not run after the rewrite, and reading steps from Apple Health / Health
  Connect was not tried on a device. iOS needs `pod install` first.
- The faucet has not sent a transaction on the real testnet (only on the fork).
- Step counts are whatever the client sends, signed by the member's key. The server cannot check
  that they came from health data, and on the web they are typed in.
- **The app's link to a token's page on Flap is wrong.** It uses `https://flap.sh/bnb-testnet/<token>`,
  which answers "page not found". Flap's testnet site is `abc.flap.sh`: the round 1 token opens at
  `https://abc.flap.sh/bnb-testnet/<token>`. Until `app/lib/config.dart` is changed, setting
  `FLAP_TOKEN_URL=https://abc.flap.sh/bnb-testnet/{token}` on the server makes the app use the
  right address (the app prefers the server's `flapUrl`). Neither has been done.
- Whether Flap takes a protocol fee out of the tax before the 80 / 20 split was not measured.
- Hosting is a temporary tunnel whose address changes when it restarts.
- The Chinese text in the Launcher's on-chain description was not reviewed by a native reader.
- [DEMO.md](DEMO.md) and [PROOF-club-season.md](PROOF-club-season.md) describe the earlier design
  (running club seasons) and are kept as a record; `scripts/run-season.ts` is the script behind
  that proof.
- No audit. Testnet tokens only.

## Credit

- The contracts are a fork of the Crowd launcher and vault example in
  [flap-sh/FlapPoolLaunchVaultExample](https://github.com/flap-sh/FlapPoolLaunchVaultExample)
  (commit `29334f689774f6b3a39720b3fc802ab0d6a61718`). Everything under `contracts/src/flap/` is
  copied from that repository unmodified. Details are in [`contracts/README.md`](contracts/README.md).
- The look of the app follows a teammate's (Delgersaikhan's) earlier SwiftUI prototype, used as the
  visual reference: its screens, layout, type and motion were rebuilt in Flutter. None of its code
  is used.
- The app shows Flap's logo once, small and unchanged, next to "Built on Flap"; Cypher Run is not run or
  endorsed by Flap. Sources and the media kit's rules are in
  [`app/assets/brand/README.md`](app/assets/brand/README.md).
- Built at BNB Hack Bangkok, November 2026.
