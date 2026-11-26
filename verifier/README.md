# Cypher Run verifier

The server side of Cypher Run, which turns showing up into a community, and a community into a
launch. A group puts in equal deposits and checks in each day they move; everyone's check-ins fill
one bar. There are two endings. If the round has not launched by its deadline (the bar never filled,
the pool was below Flap's floor, or nobody pressed Launch), every wallet takes back 100% of what it
paid in. If the bar fills and someone presses Launch, the group's own coin launches through Flap's
Pool Launch, and the piggy bank (the round's `StreakVault`) is split by days shown up, not by
dollars. BSC testnet and test USD only.

This server does six things (a round is one `CheckInLauncher`):

- **Finds the rounds.** Every round created through our `CheckInLauncherFactory` is found in the
  factory's creation events on chain. `GET /rounds` is the app's public list of them; see "Rounds:
  how they are found and listed".
- **Signs check-ins.** A member reports today's steps; if the report passes the rules below, the
  server answers with the attester's signature, and the member's own wallet sends
  `CheckInLauncher.checkIn(day, signature)`. For the rounds of a Season it signs on the Season's
  days only; see "Seasons".
- **Remembers the accepted days**, for streaks, per round.
- **Relays what the chain says** about a round and about one wallet, so the app needs one request
  instead of many reads.
- **Runs a gas faucet** that sends a new wallet a little test BNB once (0.03 by default; off by
  default).
- **Announces where it can be reached.** With `ORIGIN_REGISTRY` set it writes its current public
  host to the `OriginRegistry` contract whenever that host changes, and the apps read it from there;
  see "Origin announcer".

Every route about a round exists twice: `/rounds/:launcher/...` names the round, and the older
`/round`, `/me/:address`, `/members` and `/checkin` are the same routes for the **featured round**,
the one set with `CURRENT_LAUNCHER` or `POST /admin/round`.

TypeScript, [Hono](https://hono.dev), viem. Runs on Node 22, locally or in Docker. BSC testnet
(chain 97) only; it refuses to start on any other chain.

## What this server is trusted for

Be clear about this when describing the product.

**It attests that a wallet moved enough on a day.** The contract accepts a check-in only with the
signature of the round's attester, and this server holds that key. It signs when a member of the
round reports at least `MIN_STEPS` steps for today.

**Check-ins are attested, not proven.** The step count comes from the member's phone (Apple Health
or Health Connect), or is typed in by the member on the web when `ALLOW_SELF_REPORTED=true`. Either
way it is a number the client sends, signed with the member's key. The server checks the signature
and the limits; it cannot check that the steps were walked. A modified client can report any number
within the limits. Typed-in reports are stored flagged as self-reported, but they count the same on
chain.

### Trust

The attester key is bounded as follows; each point is checked against
`../contracts/src/CheckInLauncher.sol`, `../contracts/src/StreakVault.sol` and `src/app.ts`.

- **What it can do.** Sign, or refuse to sign, a check-in for a wallet. This server signs for
  today (UTC) only, only for a wallet that is a member of the round (`isMember`), and, for a round
  in a Season, only on the Season's days (see "Seasons"). On chain,
  `checkIn(day, signature)` accepts a signature only for the current UTC day or the one before it,
  once per wallet per day, only from a wallet that joined (paid the deposit), only before the launch
  and the deadline, and the wallet itself sends the transaction (`msg.sender` is the member). Since
  the prize, half the token supply and 80% of the trading tax are shared by days shown up
  (`daysOf / totalCheckIns`), signing for a member who did not move, or refusing one who did, changes
  shares. That is the one thing members rely on the operator for.
- **It cannot move funds.** No function of the Launcher or the vault pays out to the attester or
  lets any address withdraw. Test USD leaves the Launcher only to the Flap pool and the vault at
  `launch()`, or back to the wallet that paid it in through `refund()`; the vault pays only through
  `claim()`. Both are beacon proxies: Flap's Guardian can upgrade their code
  (`upgradeVaultImplementation` in `CheckInLauncherFactory.sol` and `StreakVaultFactory.sol`). This
  server's key cannot, and we hold no owner key.
- **It cannot launch early.** `launch()` reverts until `totalCheckIns >= checkInGoal`, and every
  check-in is a transaction from a member's own wallet. The attester has no launch function of its
  own.
- **It cannot block a launch.** Once the bar is full, `launch()` is open to any wallet until the
  deadline. If the attester stops signing, the bar may never fill, and then every member takes the
  full deposit back with `refund()` after the deadline.
- **It cannot pay anyone who did not deposit.** `daysOf` only grows through `checkIn`, which
  requires `isMember`, which only `join()` sets, and `join()` takes the deposit. `claim()` pays by
  `daysOf`. Sponsors, the creator and the attester receive nothing from the prize, the tokens or the
  tax in those roles; a refund gives each wallet back only what it paid in.

The same key also writes the `OriginRegistry` (see "Origin announcer"). That value only tells the
apps which host to send requests to; it holds no funds, and no round reads it.

Other things to know:

- **This server sends no transaction to the round's contracts.** Members send `join`, `checkIn`,
  `launch`, `refund` and `claim` from their own wallets. If this server is down, nobody can get a
  new check-in signed; everything else keeps working on chain.
- **The faucet's wallet.** With `FAUCET_ENABLED=true` the server sends test BNB to wallets that ask.
  It pays from `FAUCET_PRIVATE_KEY` when that is set, so the attester key then only signs check-ins
  and sends `setOrigin`; otherwise it pays from the attester's wallet. It is limited (see
  `POST /faucet`); run it with test funds only.
- **Streaks and the member list are this server's own records.** They are for display. Shares are
  decided by `daysOf` on chain, which the app can read directly.
- Addresses and the days each one checked in are readable by anyone through `GET /me` and
  `GET /members`, for every round, listed or not. Step counts are stored but not returned by any
  route.
- **The public list is only a list.** Which rounds `GET /rounds` shows is decided here (see "Rounds:
  how they are found and listed") and changes nothing on chain. A round that is left out, by its
  creator's choice or by this server, can still be found by anyone with its link or by reading the
  chain, and can still be joined.

## Setup

```bash
cd verifier
npm install
cp .env.example .env      # then edit
npm run dev               # http://localhost:8787
```

Other commands: `npm test` (vitest), `npm run typecheck`, `npm run build` then `npm run serve`
(plain Node, no tsx; this is what the Docker image runs), and `npm run e2e:fork` (see "Checking
against the real contracts").

### Environment

| Variable | Purpose |
| --- | --- |
| `PORT` | Port to listen on, default 8787. |
| `RPC_URL` | BSC testnet RPC. Required. |
| `CHAIN_ID` | `97` or unset. Anything else stops the server at start. |
| `ATTESTER_PRIVATE_KEY` | The key that signs check-ins and sends `setOrigin`. It must be the key of the address the round was created with as `attester`, and the `OriginRegistry`'s announcer. Its wallet also pays the faucet unless `FAUCET_PRIVATE_KEY` is set. Without it the read routes work, `POST /checkin` answers `503 attester_disabled` and nothing is announced. Never commit it. `VERIFIER_PRIVATE_KEY`, the earlier name for the same key, is read when this one is not set. |
| `CURRENT_LAUNCHER` | Address of the featured round's `CheckInLauncher`: the one `/round`, `/me`, `/members` and `/checkin` serve, and the first in `GET /rounds`. Empty: no featured round until `POST /admin/round` sets one. A round set through that route is stored in `DATA_FILE` and wins over this variable from then on. |
| `CURRENT_ROUND_NAME` | Optional display name for `CURRENT_LAUNCHER`. Default: the name stored in the Launcher. |
| `ADMIN_TOKEN` | Shared secret for `POST /admin/round`. Without it that route answers `503 admin_disabled`. |
| `MIN_STEPS` | Steps needed for a check-in, default `1000` (1 to 80000). |
| `ALLOW_SELF_REPORTED` | `true` also accepts `source: "self"` (a typed-in count). For the testnet demo on the web. Default off. |
| `FAUCET_ENABLED` | `true` switches `POST /faucet` on. Needs `FAUCET_PRIVATE_KEY` or `ATTESTER_PRIVATE_KEY`. Default off. |
| `FAUCET_PER_IP_PER_HOUR` | Wallets one network address may get funded in any hour, default `5` (1 to 1000). A room of people on one Wi-Fi shares one address; raise it for an event. |
| `FAUCET_DRIP_BNB` | Test BNB sent per wallet, as a decimal, default `0.03` (above 0, at most 1). |
| `FAUCET_PRIVATE_KEY` | Optional. A separate key the faucet pays from, with its own transaction queue. When set, the attester key only signs check-ins and sends `setOrigin`. Fund this wallet with test BNB. Never commit it. |
| `TRUST_PROXY` | `true` when a reverse proxy sits in front: the faucet's per-IP limit then uses the last address in `X-Forwarded-For`. Leave it off when clients reach this server directly, or the header could be forged. |
| `FLAP_TOKEN_URL` | Optional. Address of a token's page on Flap with `{token}` in it. Used for `flapUrl` in `GET /round` after the launch. Unset: `flapUrl` is always `null`. |
| `DATA_FILE` | JSON file for storage, default `./data/store.json` (`/data/store.json` in the Docker image). |
| `LAUNCHER_FACTORY` | Address of the `CheckInLauncherFactory` whose rounds are listed. Default: the one deployed on BSC testnet, `0x2A872200B83dD025977d785cDE05356d23eA4153`. |
| `FACTORY_FROM_BLOCK` | The block that factory was deployed in; the scan for rounds starts there. Default `144816444`. |
| `LOG_CHUNK_BLOCKS` | Blocks asked for in one `eth_getLogs` call, default `10000`. A range the RPC refuses is halved and asked again, so a value that is too high only costs a few extra calls. |
| `ROUNDS_REFRESH_SECONDS` | How often the server looks for newly created rounds, default `10` (2 to 3600). |
| `ORIGIN_REGISTRY` | Address of the `OriginRegistry` to announce this server's host to. Unset: nothing is announced. On BSC testnet: `0xb9aD45Dc177C801f10670F2aac03B467f1C367d2`. Needs `ATTESTER_PRIVATE_KEY`. |
| `ORIGIN_HOST` | The public host, when it is fixed: a plain hostname such as `api.example.com` (no scheme, port or path; anything else stops the server at start). Unset: the host is read from `ORIGIN_SOURCE_URL`. |
| `ORIGIN_SOURCE_URL` | Where the host is read when `ORIGIN_HOST` is not set, default `http://tunnel:20241/quicktunnel` (cloudflared's metrics server, which answers `{"hostname":"<name>.trycloudflare.com"}`). |
| `ORIGIN_CHECK_SECONDS` | How often the host is checked, default `60` (10 to 3600). |
| `SEASON_LAUNCHERS` | The Season's rounds (squads): `CheckInLauncher` addresses separated by commas. Check-ins for them are signed on the Season's days only (see "Seasons"). Unset or empty: no Season, no round is gated, and the other `SEASON_*` values are not read. |
| `SEASON_NAME` | The Season's name as members read it, such as `Season 1` (at most 80 characters). Default `Season`. |
| `SEASON_START` | The first check-in day, `YYYY-MM-DD`, a UTC day (it starts at 07:00 in Bangkok). Required with `SEASON_LAUNCHERS`. |
| `SEASON_END` | The last check-in day, included, fewer than 90 days after `SEASON_START`. Required with `SEASON_LAUNCHERS`. |
| `SEASON_JOIN_UNTIL` | The last day the app offers Join, included, from `SEASON_START` to `SEASON_END`. Passed on to the app only: joining is not gated here, and the contract takes joins until the launch or the deadline. Required with `SEASON_LAUNCHERS`. |
| `SEASON_SQUAD_SIZE` | The member count at which the app stops offering Join, default `10` (1 to 1000). Passed on to the app only; the contract has no cap. |

None of the four factory variables (`LAUNCHER_FACTORY` to `ROUNDS_REFRESH_SECONDS`) needs to be set for the deployed factory. To make a round the
featured one on a running server:

```bash
curl -X POST http://localhost:8787/admin/round \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"launcher":"0x…","name":"November round"}'
```

## Rules for a check-in

A report is accepted, and the check-in signed, when all of these hold:

- it is signed by the member's own wallet (see "Signatures");
- it is for **today** in UTC. The day is not sent; it is part of the signed text, and the server
  only tries today's date. `GET /round` returns `today` so the app does not depend on the phone's
  clock;
- the wallet is a member of the round (`isMember` on chain);
- `steps` is a whole number, at least `MIN_STEPS` (default 1000) and at most 80000;
- `source` is `healthkit` or `healthconnect`, or `self` when `ALLOW_SELF_REPORTED=true`;
- the round has not launched and its deadline has not passed;
- the round's `attester` is this server's key;
- for a round in the Season (`SEASON_LAUNCHERS`), today is one of the Season's days (see "Seasons").

One accepted check-in per wallet per day. Asking again on the same day returns the same signature
(for example when the transaction failed) and keeps the first accepted report. The contract itself
takes a signed day while it is today or yesterday on chain, so a signature issued just before
midnight UTC still works a little later.

**Streak**: consecutive UTC days with an accepted check-in, ending today, or ending yesterday while
today is still open. A full day without one ends it. `bestStreak` is the longest run in the round.

## Seasons

A Season is one event with one set of dates, made of squads. Each squad is its own round (one
`CheckInLauncher`: one bar, one piggy bank, one coin), and every squad has the Season's dates, so
everyone starts on the same day, at 0 days.

**A rule of this server, not of the contract.** `CheckInLauncher` has no start date: it takes a
check-in on any day from a member's join until the launch or the deadline. So for a launcher listed
in `SEASON_LAUNCHERS` this server signs **no check-in before `SEASON_START` and none after
`SEASON_END`**. Days are UTC days, as the contract counts them; a day starts at 07:00 in Bangkok.
Disclose this rule like the 1,000-step minimum. A member who joins before the start holds a deposit
at 0 days until then. The refusal comes after the round's own checks (signature, membership,
launched, deadline) and before anything is stored or signed:

| Status | `error` | `message` (Season 1) |
| --- | --- | --- |
| 409 | `season_not_started` | `Season 1 check-ins open Tue 1 Dec (07:00 in Bangkok). Everyone starts at 0.` |
| 409 | `season_over` | `Season 1 check-ins have ended. The last day was Wed 30 Dec.` |

The app shows the server's `message` as the error, so app builds made before Seasons already say why.

Nothing else changes. A launcher that is not in `SEASON_LAUNCHERS` is not touched (the stage demo
round keeps working as before), and without `SEASON_LAUNCHERS` the server behaves exactly as it did
before Seasons. Joining is not gated here: `joinUntil` and `squadSize` are passed on in `season` for
the app, which stops offering Join after `joinUntil` or at `squadSize` members. A join sent straight
to the contract still works until the launch or the deadline.

**What the rule cannot do.** It limits only what this server signs. Anyone may launch as soon as the
bar is full, whatever the Season's last day (a squad of 10 with a goal of 240 can fill on day 24 at
the earliest), and a round that has launched or passed its deadline answers `round_launched` or
`round_closed` first. The attester's limits under "Trust" are unchanged.

Season 1, as set on the hosted server once Squad A existed (26 November 2026), then the server
restarted:

```bash
SEASON_NAME="Season 1"
# Squad A; more squads comma-separated as they open. Never the stage demo round.
SEASON_LAUNCHERS=0xa60e2f022d891dd394415a594c9e33614c019153
SEASON_START=2026-12-01
SEASON_END=2026-12-30
SEASON_JOIN_UNTIL=2026-12-07
SEASON_SQUAD_SIZE=10
```

At start the server logs `Season 1: 1 round(s); check-ins signed from Tue 1 Dec to Wed 30 Dec (UTC
days) only.` A `SEASON_*` value it cannot use stops it at start with an error that names the variable,
like every other setting, so read the log after the restart. It warns, and keeps running, when other
`SEASON_*` values are set but `SEASON_LAUNCHERS` is empty (then no round is gated), and when
`CURRENT_LAUNCHER` is one of the Season's rounds. Quotes around a `SEASON_*` value are removed
(`docker run --env-file` keeps them). Keep comments on their own lines: that reader also keeps an
inline `# …` as part of the value. `.env.example` has the six lines, empty, with Season 1's values
in a comment above them. After the restart, check the Season:

```bash
curl -s https://<host>/api/rounds/<squad A> | jq -c .season
# {"name":"Season 1","start":"2026-12-01","end":"2026-12-30","joinUntil":"2026-12-07",
#  "startDay":20788,"endDay":20817,"joinUntilDay":20794,"day":0,"days":30,"squadSize":10}
curl -s https://<host>/api/round | jq .season      # the featured stage demo round: null
```

Never list the stage demo round ("Bangkok Demo Run",
`0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876`) or any other round that is not a Season squad in
`SEASON_LAUNCHERS`: its check-ins would be refused outside the Season's days. Do not make a Season
round the featured round (`CURRENT_LAUNCHER` or `POST /admin/round`) while a live demo checks in on
the featured round: `/checkin` serves the featured round, and before the Season's first day every
check-in there is refused. For BNB Hack Bangkok, "Bangkok Demo Run" stays the featured round through
judging, a Season squad is never the demo's backup round, and Season 1 is featured only after
judging, as the upcoming flagship (join now, check-ins from Tue 1 Dec).

## API

JSON in, JSON out. Errors are `{ "error": "<code>", "message": "..." }`. Addresses are returned
lower-case. Amounts are decimal strings in whole tokens (`"2137.17"`), using each token's own
`decimals()`; where a `raw` object is present it holds the same amounts in the token's smallest
units, as decimal strings. Times are unix seconds.

Every route is served at the root (`/round`) and again under `/api` (`/api/round`). The web app
calls its own origin under `/api`, so a reverse proxy can pass `/api/*` to this server unchanged;
stripping the prefix works as well.

Every response carries `Access-Control-Allow-Origin: *`. An `OPTIONS` preflight on any path is
answered with `204`, `Access-Control-Allow-Methods: GET,POST,OPTIONS` and
`Access-Control-Allow-Headers: Content-Type`. `Authorization` is not on that list on purpose: the
admin route is an operator call (curl), not something a browser page should send.

Routes that read a round answer `503 chain_unavailable` when the chain could not be read, and
`404 no_round` when there is no such round: no featured round is set (`/round`, `/me`, `/members`,
`/checkin`), or the launcher in the path was not created by our factory (`/rounds/:launcher/...`).

| Route | What it is |
| --- | --- |
| `GET /rounds` | The public list. |
| `POST /rounds` | The creator puts a round on the public list or keeps it off. |
| `GET /rounds/:launcher` | One round, by address. |
| `GET /rounds/:launcher/me/:address` | One wallet in that round. |
| `GET /rounds/:launcher/members` | That round's members. |
| `POST /rounds/:launcher/checkin` | A daily report for that round. |
| `GET /round`, `GET /me/:address`, `GET /members`, `POST /checkin` | The same four for the featured round. |
| `GET /stats`, `GET /stats/:address` | Totals across every round, listed or not; with an address, that wallet's own. |
| `POST /faucet`, `POST /admin/round` | Gas for a new wallet; the operator sets the featured round. |
| `GET /faucet` | For the operator: how many more wallets the faucet can fund. |
| `GET /health` | For the operator: the attester, the faucet's wallet and the origin announcer's state. |

### Signatures

`personal_sign` (EIP-191) by the member's wallet over these exact strings:

```
Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>
Cypher Run faucet <address>
Cypher Run round <launcher> <listed|unlisted>
```

The third one is signed by the wallet that created the round, not by a member; see `POST /rounds`.
`<launcher>` and `<address>` may be lower-case or checksummed (the app writes lower case). `<YYYY-MM-DD>` is today in UTC.
`<steps>` is the same text that is sent in the body: a plain whole number such as `5000`.
The name `Cypher Run` comes from one constant, `PRODUCT_NAME` in `src/product.ts`; the app must use the
same one.

### `GET /`

`{ "service": "cypher-run-verifier", "ok": true }`

### `GET /health`

```json
{
  "service": "cypher-run-verifier", "ok": true,
  "attester": "0x2f2a…", "faucetWallet": "0x…",
  "origin": {
    "registry": "0xb9ad45dc177c801f10670f2aac03b467f1c367d2",
    "host": "name.trycloudflare.com", "onChain": "name.trycloudflare.com",
    "lastTx": "0x…", "lastTxHost": "name.trycloudflare.com", "lastTxAt": 1795900000,
    "pending": false, "checkedAt": 1795900060, "lastError": null
  }
}
```

| Field | Meaning |
| --- | --- |
| `attester` | This server's attester address; `null` without a key. |
| `faucetWallet` | The wallet the faucet pays from; `null` while the faucet is off. |
| `origin` | `null` unless the origin announcer runs. `host` is this server's public host as last found; `onChain` is `origin()` as last read; `lastTx` is the last `setOrigin` this server sent (`null` if none since the start) and `pending` is `true` until it has a receipt. `lastError` is the code of what stopped the last check: `source_unavailable`, `bad_host`, `registry_unavailable`, `not_announcer`, `send_failed`, `tx_reverted` or `tx_dropped`. |

### Origin announcer

The server is reached through a Cloudflare quick tunnel whose host changes whenever the tunnel
restarts. No build has that host in it: the apps read it from the `OriginRegistry` contract
(`../contracts/src/OriginRegistry.sol`), and this server keeps it current. With `ORIGIN_REGISTRY`
set, every `ORIGIN_CHECK_SECONDS` (default 60) it

1. finds its public host: `ORIGIN_HOST` when set, otherwise `GET ORIGIN_SOURCE_URL` (cloudflared's
   `/quicktunnel`, default `http://tunnel:20241/quicktunnel`). Anything that is not a plain hostname
   is refused and nothing is sent;
2. reads `origin()` from the registry (and, once, `announcer()`: when it is not this server's
   attester address nothing is ever sent);
3. when they differ, sends `setOrigin(host)` from the attester key, through the same one-at-a-time
   queue as every other transaction of that wallet, and logs the host and the transaction hash.

While a `setOrigin` has no receipt, no second one is sent; one with no receipt after ten minutes is
treated as dropped and may be sent again. A failed step is logged once (without the error's own
text, which can contain the RPC's address) and tried again on the next check. The checks run on a
timer of their own, so no request waits for them. `GET /health` shows the state.

Each `setOrigin` costs the attester's wallet gas (at most 200,000 gas at 1 gwei, 0.0002 test BNB),
so that wallet needs a little test BNB even when the faucet has a key of its own.

### Rounds: how they are found and listed

**Found on chain.** Every round is one Launcher created through our factory, and the factory emits
`CheckInLauncherCreated(launcher, creator, launchSalt)` for each. The server reads those events from
the factory's deployment block to the head, `LOG_CHUNK_BLOCKS` blocks per `eth_getLogs` call (public
RPCs refuse wide ranges; a refused range is halved and asked again). What it found and how far it
got is kept in `DATA_FILE`, so a restart continues from there. It looks again every
`ROUNDS_REFRESH_SECONDS`, and at once when a route is asked about a launcher it has not seen. Every
scan reads the last 64 blocks again, in case the RPC answered from a node that was slightly behind.
`creator` is the wallet that called the Flap Portal to create the round.

**Listed.** A round our factory created is in `GET /rounds` when

- its creator registered it as listed (`POST /rounds`, `unlisted: false`), or
- nobody registered it and it was created at least **three minutes** ago. The wait is there so that
  a round whose creator's app is about to register it as unlisted is never shown in between.

A round registered as unlisted is left out of `GET /rounds`.

**What "unlisted" means.** It means the round is not shown in the app's public list. Anyone with
its link, or anyone reading the chain, can still find it: the round, its members and their
check-ins are on chain like any other round's, `GET /rounds/:launcher` and the other per-round
routes answer for anyone who has the address, and anyone who has the address can join. It is a
choice about one list, not access control.

Two more things decide what is in the list:

- **Rounds this server cannot sign for are left out.** A round created with another attester can
  never get a check-in signed here, so nobody could fill its bar from this app. It still answers by
  address, with `attesterReady: false`. (A server started without a key lists every round.)
- **The featured round** is first in the list and skips the three-minute wait and the attester
  check, because the operator chose it. Its creator's choice still applies: registered as unlisted,
  it is not in `GET /rounds`, while `GET /round` keeps serving it.

### `GET /rounds`

```json
{
  "rounds": [
    {
      "launcher": "0x378d…", "name": "Demo Day",
      "deposit": "500", "liquidityBps": 3000,
      "checkInGoal": 5, "totalCheckIns": 4, "memberCount": 6, "totalSponsored": "1500",
      "prizeNow": "2100", "poolQuoteNow": "2400",
      "deadline": 1795883661, "launched": false, "token": null, "vault": null,
      "season": null,
      "state": "open", "featured": true
    }
  ]
}
```

Listed rounds only. Every field except `state` and `featured` is the field of the same name in
`GET /round`, with amounts as decimal strings in whole tokens. `totalSponsored` and `season` are
there so a card can tell a sponsored Season squad (`liquidityBps` 0, sponsor money, a `season`) from
other rounds without reading each round on its own.

| Field | Meaning |
| --- | --- |
| `state` | `"launched"` once the token has launched; otherwise `"open"` up to and including the deadline and `"expired"` after it (refunds are open). |
| `featured` | This is the featured round, the one `GET /round` serves. At most one. |

Order: the featured round; then open rounds, nearest deadline first; then launched rounds, newest
(by creation) first; then expired rounds, most recently expired first.

The list answers from memory for a few seconds: an open round is read from the chain again after
4 seconds, a launched or expired one after 60. `GET /rounds/:launcher` always reads the chain. If a
round cannot be read, the list shows what it read last for up to five minutes. `503
chain_unavailable` means nothing could be read at all; an empty list is `200 {"rounds": []}`.

### `POST /rounds`

Body `{ launcher, unlisted, signature }`. The creator of a round says whether it is on the public
list. `unlisted` is `true` or `false`; `signature` is the creator's `personal_sign` over
`Cypher Run round <launcher> listed` or `Cypher Run round <launcher> unlisted`, with the launcher
in lower case.

```json
{ "launcher": "0x…", "unlisted": true }
```

The creator is read from the factory's creation event, so nobody else can register a round, and
nothing is sent to the chain. The creator may call it again to change the choice. The app should
call it right after the creation transaction: until it does, the three-minute rule applies. If the
RPC this server reads from does not show the new round yet, the server looks again twice, 1.5
seconds apart, before it answers `404`; a client that still gets `404` can simply send the same
request again.

The signed text has no date in it. Someone who has seen a creator's signature (the creator sends it
only to this server) could send it again later and set that same choice again; they cannot produce
a choice the creator never signed.

| Status | `error` | Meaning |
| --- | --- | --- |
| 400 | `bad_launcher`, `bad_unlisted` | Malformed body. |
| 401 | `bad_signature` | Not the creator's signature over this launcher and this choice. |
| 404 | `no_round` | Our factory did not create a round at this address. |
| 503 | `chain_unavailable` | The factory's events could not be read, so the creator is not known. Nothing was stored. |

### `GET /rounds/:launcher`

The same object as `GET /round` below, for any round our factory created, listed or not, plus
`"unlisted": true|false` (the creator's registered choice; `false` when nobody registered one).
`400 bad_launcher` when the path is not an address, `404 no_round` when our factory did not create
it. The featured round is the one exception: it answers here whichever factory created it, because
the operator chose it.

### `GET /rounds/:launcher/me/:address`, `GET /rounds/:launcher/members`, `POST /rounds/:launcher/checkin`

The per-round forms of `GET /me/:address`, `GET /members` and `POST /checkin` below: the same
bodies, the same rules, the same answers and errors, and the same signed text (it already names the
launcher). Accepted check-ins and the member list are kept per Launcher. A check-in for a round
created with another attester is refused with `503 attester_mismatch`.

### `GET /round`

The featured round, read from the chain.

```json
{
  "launcher": "0x…", "name": "Morning Movers",
  "quoteToken": "0x190c989d5665a0e404b444b53cae9abcfb600157",
  "deposit": "1000", "liquidityBps": 3000,
  "checkInGoal": 6, "totalCheckIns": 4, "memberCount": 3,
  "totalDeposits": "3000", "totalSponsored": "600",
  "poolQuoteNow": "1500", "prizeNow": "2100",
  "deadline": 1796342400, "launched": false, "token": null, "vault": null,
  "minSteps": 1000, "flapUrl": null,

  "today": "2026-11-25", "dayIndex": 20782,
  "canLaunch": false, "refundOpen": false,
  "allowSelfReported": true,
  "attester": "0x…", "attesterReady": true,
  "quoteDecimals": 18,
  "season": null,
  "raw": { "deposit": "1000000000000000000000", "totalDeposits": "…", "totalSponsored": "…", "poolQuoteNow": "…", "prizeNow": "…" }
}
```

For a round in the Season, `season` is an object instead of `null`:

```json
"season": {
  "name": "Season 1", "start": "2026-12-01", "end": "2026-12-30", "joinUntil": "2026-12-07",
  "startDay": 20788, "endDay": 20817, "joinUntilDay": 20794,
  "day": 0, "days": 30, "squadSize": 10
}
```

| Field | Meaning |
| --- | --- |
| `name` | The display name given with the round, otherwise the name stored in the Launcher. |
| `checkInGoal`, `totalCheckIns` | The bar: `launch()` opens when `totalCheckIns >= checkInGoal`. |
| `memberCount` | Wallets that joined (paid the deposit), those with 0 days included. `totalCheckIns / memberCount` is the average member's days; both numbers freeze at the launch. In a round with `liquidityBps` 0 (the pool is sponsor money only) that launches, a member whose days are at least that average can claim at least the deposit in test USD from the piggy bank: the Keep-Up Guarantee. Coins and tax come on top and are not part of it. |
| `totalSponsored` | Sponsor money in the round. It goes only to the pool at the launch, and back to each sponsor with `refund()` if the round does not launch. |
| `poolQuoteNow` | What `launch()` would put in the pool: all sponsor money plus `liquidityBps` of the deposits. Flap's Portal refuses a launch below its own floor (1,500 test USD when this was written); the app should show this number next to that floor. |
| `prizeNow` | Before the launch: what `launch()` would send to the vault (the rest of the deposits). After it: everything the vault has received so far, the prize plus trading tax. |
| `token`, `vault`, `flapUrl` | `null` until the launch. `flapUrl` stays `null` unless `FLAP_TOKEN_URL` is set. |
| `today`, `dayIndex` | Today in UTC as the server sees it, and the contract's number for it (unix time / 86400). |
| `canLaunch` | The Launcher's own `canLaunch()`: bar full, not launched, before the deadline. It does not know the Portal's floor. |
| `refundOpen` | The deadline has passed and the round has not launched. |
| `attesterReady` | This server's key is the round's attester. `false` means check-ins are refused. |
| `season` | `null` unless the round is in the Season (`SEASON_LAUNCHERS`). `start`, `end` and `joinUntil` are UTC days as `YYYY-MM-DD`, and `startDay`, `endDay` and `joinUntilDay` the same days as the contract numbers them. `day` is today in the Season: `0` before the first day, `1` on it, `days` on the last day, `days + 1` after it; check-ins are signed only while `day` is from 1 to `days`. `joinUntil` and `squadSize` are for the app's Join button; this server does not enforce them. See "Seasons". |

### `GET /me/:address`

One wallet in the featured round.

```json
{
  "address": "0x…", "member": true,
  "daysOf": 2, "checkedInToday": true,
  "streak": 2, "bestStreak": 2, "days": ["2026-11-24", "2026-11-25"],
  "claimableTokens": "0", "claimableQuote": "0", "claimedTokens": "0",

  "claimedQuote": "0", "attestedToday": true, "refundable": "0",
  "raw": { "claimableTokens": "0", "claimableQuote": "0", "claimedTokens": "0", "claimedQuote": "0", "refundable": "0" }
}
```

| Field | From | Meaning |
| --- | --- | --- |
| `member` | chain | `isMember(address)`. It is `false` again after a refund. |
| `daysOf` | chain | Days checked in on chain. This is what the share is computed from. |
| `checkedInToday` | chain | Today's check-in is on chain. |
| `attestedToday` | this server | Today's check-in was signed here. `true` with `checkedInToday: false` means the transaction still has to be sent; `POST /checkin` hands the signature out again. |
| `streak`, `bestStreak`, `days` | this server | From the check-ins accepted here. A day signed here whose transaction was never sent is in `days` but not in `daysOf`. |
| `claimableTokens`, `claimableQuote` | chain | `StreakVault.claimable(address)`; zero before the launch. `claimableQuote` grows as trading tax arrives. |
| `claimedTokens`, `claimedQuote` | chain | What the wallet has claimed so far. |
| `refundable` | chain | What `refund()` would pay right now: zero unless the deadline passed without a launch. |

### `GET /members`

One list for the bar screen, sorted by `daysOf`, then `streak`:

```json
[
  { "address": "0x…", "daysOf": 2, "streak": 2, "checkedInToday": false },
  { "address": "0x…", "daysOf": 2, "streak": 1, "checkedInToday": true }
]
```

`daysOf` and `checkedInToday` are read from the chain; `streak` is this server's. The Launcher keeps
no list of members that can be read, so the list holds the wallets this server has seen as members:
a wallet appears after its first `GET /me/:address` or `POST /checkin` as a member. A wallet that
joined on chain and never opened the app is counted in `memberCount` of `GET /round` but is not in
this list.

### `GET /stats`, `GET /stats/:address`

Every round our factory created added up, listed or not (and the featured round, when it is not one
of them). The answer is numbers only: no round is named, so an unlisted round is counted without
being shown. Rounds created with another attester are left out by the same rule as `GET /rounds`:
their check-ins, deposits, launch and members are not counted, unless the round is the featured one.
(A server started without a key counts every round.)

```json
{
  "rounds": 3,
  "people": 7,
  "checkIns": 12,
  "deposited": "5500",
  "launched": 1,
  "complete": true,
  "raw": { "deposited": "5500000000000000000000" }
}
```

| Field | From | Meaning |
| --- | --- | --- |
| `rounds` | chain | Rounds counted. |
| `people` | this server | Wallets seen as a member of any of them, each counted once (see `GET /members` for who is seen). A wallet that joined on chain and never opened the app is not in it, so this is never more than the truth. |
| `checkIns` | chain | `totalCheckIns` of every round, added. |
| `deposited` | chain | `totalDeposits` of every round, added, in whole quote tokens. A deposit taken back after a missed deadline is no longer in it. |
| `launched` | chain | Rounds whose token launched. |
| `complete` | | `false` when a round could not be read: the totals leave it out and are lower than the truth. |

`GET /stats/:address` is the same object plus `you`, that wallet across the rounds this server has
seen it join:

```json
{ "you": { "address": "0x…", "rounds": 2, "days": 4, "claimed": "300", "raw": { "claimed": "300000000000000000000" } } }
```

`days` is `daysOf` on chain, added over those rounds; `claimed` is `claimedQuote` in the vaults of
the launched ones. `you` is `null` when one of those rounds could not be read: no figure rather
than a low one. A wallet never seen as a member answers zeros.

The rounds are read the way `GET /rounds` reads them, with the same memory, and the sum is kept for
10 seconds; a sum with a round missing is not kept. `you` costs at most two chain reads per round
the wallet joined and is kept for 4 seconds. `503 chain_unavailable` when nothing could be read;
`400 bad_address` for an address that is not one.

### `POST /checkin`

Body `{ address, steps, source, signature }`.

- `steps`: a whole number (JSON number or string of digits).
- `source`: `"healthkit"`, `"healthconnect"` or `"self"`.
- `signature`: the member's `personal_sign` over `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>`
  for today (UTC).

```json
{ "day": "2026-11-25", "dayIndex": 20782, "attesterSignature": "0x…", "repeat": false }
```

The app then sends `CheckInLauncher.checkIn(dayIndex, attesterSignature)` from the member's wallet
(legacy transaction, 1 gwei, gas limit 200,000). `repeat` is `true` when this day was already
accepted and the same signature is returned again.

| Status | `error` | Meaning |
| --- | --- | --- |
| 400 | `bad_address`, `bad_steps`, `bad_source` | Malformed body. |
| 401 | `bad_signature` | Not the member's signature over exactly what was sent. |
| 403 | `not_a_member` | The wallet has not joined the round on chain. |
| 404 | `no_round` | No round is set. |
| 409 | `already_checked_in` | Today's check-in is already on chain. |
| 409 | `round_launched` | The round has launched; check-ins are closed. |
| 409 | `round_closed` | The round's deadline has passed. |
| 409 | `season_not_started` | A Season round before the Season's first day. Nothing was stored or signed. See "Seasons". |
| 409 | `season_over` | A Season round after the Season's last day. Nothing was stored or signed. |
| 422 | `not_enough_steps` | Fewer than `minSteps`. |
| 422 | `implausible_steps` | More than 80000. |
| 422 | `self_report_disabled` | `source: "self"` while `ALLOW_SELF_REPORTED` is not `true`. |
| 422 | `wrong_day` | Signed for yesterday or tomorrow (a request around midnight UTC, or a clock that is off). Sign again for `today` from `GET /round`. |
| 503 | `attester_disabled` | The server has no key. |
| 503 | `attester_mismatch` | The round was created with another attester. |
| 503 | `chain_unavailable` | The round could not be read. Nothing was accepted. |

#### The attester's signature

```
day    = floor(unix time / 86400)
inner  = keccak256(abi.encode(uint256 97, address launcher, address wallet, uint256 day))
digest = keccak256("\x19Ethereum Signed Message:\n32" ++ inner)
```

That is `personal_sign` of the 32 raw bytes of `inner`, returned as 65 bytes `r ++ s ++ v` with
`v` 27 or 28. The chain id and the Launcher's address are part of it, so a signature is good for
one wallet, one day, one round, one chain. `test/attest.test.ts` pins the worked vector from
`contracts/test/CheckInLauncher.t.sol` (same key, same inputs, same 65 bytes).

### `POST /faucet`

Body `{ address, signature }` (signature over `Cypher Run faucet <address>`). Sends
`FAUCET_DRIP_BNB` test BNB (**0.03** by default) from the faucet's wallet (`FAUCET_PRIVATE_KEY`, or
the attester's when that is not set), for gas. It does not send test USD: getting test dollars for the deposit
is a step the member takes in the app.

```json
{ "funded": true, "bnbTx": "0x…" }
{ "funded": false, "bnbTx": null, "reason": "already_funded", "message": "…" }
```

The answer is `200` in both cases. `funded: true` means the transfer was **submitted**; wait for the
`bnbTx` receipt before sending a transaction from the wallet. Reasons for `funded: false`, checked
in this order:

| `reason` | Meaning |
| --- | --- |
| `faucet_disabled` | `FAUCET_ENABLED` is not `true`, or there is no key for the faucet. |
| `already_funded` | This address was funded before. Once per address, for good. |
| `cap_reached` | 200 wallets have been funded in total. The faucet stays closed. |
| `rate_limited` | `FAUCET_PER_IP_PER_HOUR` requests (5 by default) from this IP reached the sending step in the last hour. |
| `chain_unavailable` | The balances could not be read. Nothing was sent; ask again. |
| `has_funds` | The address already holds 0.002 test BNB or more. This does not use up its one payout. |
| `faucet_empty` | The faucet's wallet would drop below 0.05 test BNB, which it keeps back. |
| `send_failed` | The transfer could not be submitted. The address may ask again. |

`400 bad_address` and `401 bad_signature` use the normal error shape. The faucet works with no
round set. Requests are handled one at a time, so two requests at once cannot be paid twice. Payout
records include the caller's IP address (see `TRUST_PROXY`).

Budget at the defaults: 200 wallets x 0.03 = 6 test BNB plus gas. Top the faucet's wallet up
accordingly, or the faucet answers `faucet_empty` long before the cap.

The hosted server at BNB Hack Bangkok runs the faucet from its own wallet,
`0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8` (`FAUCET_PRIVATE_KEY`, not the attester's), with
`FAUCET_DRIP_BNB=0.012` and `FAUCET_PER_IP_PER_HOUR=100`.

### `GET /faucet`

For the operator before a demo. No per-wallet data.

```json
{ "enabled": true, "wallet": "0x…", "dripWei": "12000000000000000", "reserveWei": "50000000000000000",
  "perIpPerHour": 100, "funded": 10, "capLeft": 190, "balance": "451916000000000000", "walletsLeft": 33 }
```

`walletsLeft` is `(balance - 0.05) / drip`, rounded down, and never more than `capLeft`: how many
more wallets get paid before `faucet_empty` or `cap_reached`. It is an upper bound, since each
transfer's gas also comes out of the balance. `balance` and `walletsLeft` are `null` when the chain
cannot be read; `walletsLeft` is `0` when the faucet is off. `scripts/preflight.sh` reads it (and
falls back to the wallet's balance on a server without it).

### `POST /admin/round` (admin)

Header `Authorization: Bearer <ADMIN_TOKEN>`. Body `{ launcher, name }`; `name` is optional (up to
80 characters). Makes a round the featured one and answers with the same body as `GET /round`. It
sends nothing to the chain. The other rounds stay reachable through `/rounds/:launcher/...`.

| Status | `error` | Meaning |
| --- | --- | --- |
| 400 | `bad_launcher`, `bad_name` | Malformed body. |
| 401 | `unauthorized` | Missing or wrong token. |
| 409 | `attester_mismatch` | That round's attester is not this server's key. Nothing was changed. |
| 503 | `admin_disabled` | `ADMIN_TOKEN` is not configured. |
| 503 | `chain_unavailable` | The address could not be read as a `CheckInLauncher`. Nothing was changed. |

Accepted check-ins and the member list are kept per Launcher, so switching rounds does not mix them.

## Transactions

The only transactions this server sends are the faucet's transfers (gas limit 21,000) and
`OriginRegistry.setOrigin` (gas limit 200,000). They are legacy transactions at a gas price of
1 gwei with an explicit gas limit: fee estimation on this testnet answers 1 wei, and such
transactions are never mined. Each wallet's transactions go through one queue, one at a time, each
with an explicit nonce, because a load-balanced public RPC can report a stale pending count. With
`FAUCET_PRIVATE_KEY` the faucet's wallet has a queue of its own; without it the faucet and
`setOrigin` share the attester's.

## Checking against the real contracts

`npm test` runs on a fake chain. `npm run e2e:fork` runs this server against the compiled contracts
on a local fork of BSC testnet, so nothing is sent to the real testnet:

```bash
(cd ../contracts && forge build)
anvil --fork-url https://bsc-testnet-rpc.publicnode.com --chain-id 97 --port 8546   # other terminal
npm run e2e:fork            # FORK_RPC_URL=http://127.0.0.1:8546 by default
```

It deploys the two factories on the fork, opens a round through Flap's live Portal code, checks
that the round is found in the factory's event and that only its creator can list or unlist it, and
walks three members through join, `POST /checkin` followed by their own `checkIn` transaction with the
returned signature, `launch()` from a wallet with no role, and `claim()`, comparing `GET /round`,
`GET /me` and `GET /members` with what it expects after each step. It uses anvil's public test keys
only.

## Running in Docker

```bash
cd verifier
docker build -t cypher-run-verifier .
docker run -d --name cypher-run-verifier --restart unless-stopped \
  --env-file .env -v cypher-run-data:/data -p 127.0.0.1:8787:8787 cypher-run-verifier
```

- The image is `node:22-slim`, runs as the unprivileged `node` user, has production dependencies
  only and starts `node dist/server.mjs` on `PORT` (default 8787).
- State is the JSON file `/data/store.json`; keep the `/data` volume or the featured round, the
  accepted check-ins (streaks), the faucet record and the creators' listed/unlisted choices are
  lost. Check-ins already on chain are not affected, and the rounds themselves are found on chain
  again. If the choices are lost, a round registered as unlisted is listed again (three-minute
  rule) until its creator registers it once more. An `.env` that says
  `DATA_FILE=./data/store.json` lands on the same volume.
- No secret is in the image. `.env` is excluded from the build context; pass it with `--env-file`
  (no quotes around values in that file) or your orchestrator's secrets.
- Bind the port to `127.0.0.1` and put a reverse proxy in front for TLS. Proxy the site's `/api/`
  to `http://127.0.0.1:8787` (with or without the `/api` prefix, both are served) and set
  `TRUST_PROXY=true`, making sure the proxy appends the client address to `X-Forwarded-For`.

**Coming from the earlier club-season server.** The same key works under its old name
(`VERIFIER_PRIVATE_KEY`). A data file written by that server is read for its faucet record only, so
wallets funded before are not funded again; its seasons, goals, runs and World Club records are not
loaded and are left out of the file the first time this server writes it. Copy the file first if
you want to keep them. All routes about clubs, seasons, the World Club, leaderboards, kickoff,
settle and Merkle proofs are gone and answer `404`.

## Layout

```
src/product.ts   PRODUCT_NAME and the texts members sign
src/attest.ts    the attester's check-in signature (what the contract verifies)
src/rules.ts     what a daily report must look like (pure)
src/season.ts    Seasons: the SEASON_* settings, which days a Season round gets check-ins signed,
                 and the `season` object of the round views (pure)
src/days.ts      UTC days and streaks (pure)
src/faucet.ts    faucet amount and limits (pure)
src/origin.ts    origin announcer: finds the public host, writes it to the OriginRegistry
src/store.ts     Store interface + in-memory / JSON-file store
src/chain.ts     viem reads of the Launcher and the vault; the factory's creation events; the
                 OriginRegistry; the faucet's transfers and setOrigin, one at a time per wallet
src/rounds.ts    which rounds exist: the scan of the factory's events, in chunks, kept in the store
src/stats.ts     totals across every round, and one wallet's own (pure)
src/app.ts       HTTP routes
src/config.ts    builds the app from environment variables
src/server.ts    entry; looks for new rounds every ROUNDS_REFRESH_SECONDS and starts the origin
                 announcer
test/            vitest: the contracts' signature vector, check-in rules, streaks across day
                 boundaries, GET /round, /me and /members on a fake chain, the admin route, faucet
                 limits, the /api base path, the data file, and the ABI fragments against
                 ../contracts/abi. test/rounds.test.ts: discovery and its store, the list's order
                 and states, the three-minute rule, registration by the creator only, the
                 per-round routes against the single-round ones, a launcher from another factory.
                 test/stats.test.ts: the totals, an unlisted round counted and never named, one
                 wallet's own numbers, the short memory, a round that cannot be read, a round
                 with another attester left out. test/origin.test.ts: the announcer (unchanged
                 host, changed host, pending, dropped and reverted transactions, bad hosts, the
                 source or the RPC down), GET /health and the ORIGIN_* settings.
                 test/faucet.test.ts also covers FAUCET_* settings and the separate faucet key.
                 test/season.test.ts: Season 1's day numbers, SEASON_* parsing and its errors, the
                 SEASON_* lines of .env.example (empty, and Season 1's values in the comment), the
                 rule at days 20787, 20788, 20817 and 20818, other launchers untouched, the view.
                 The Season on the routes: check-ins refused before 1 Dec and after 30 Dec with
                 nothing stored or signed, other rounds untouched (test/checkin.test.ts); `season`
                 on /round, /rounds/:launcher and the /rounds items (test/round.test.ts); the
                 SEASON_* environment (test/config.test.ts)
test/e2e-fork.ts the full round against the real contracts on a local fork (npm run e2e:fork),
                 including discovery from the factory's event and POST /rounds
Dockerfile       node:22-slim image, see "Running in Docker"
```

## Not checked

- The rounds run on the real testnet through the hosted server are recorded in `../PROOF.md` and
  the top-level README's "Hosting" section, not here. What this folder checks on chain is checked on a local fork
  (`npm run e2e:fork`): there the contract accepted this server's signatures and the API matched the
  chain through creation, listing, join, check-in, launch and claim.
- The multi-round routes were read against the real BSC testnet on 26 November 2026 from a local
  copy of this server with no key (reads only): `GET /rounds` returned the three rounds the factory
  had created ("Demo Day" featured, "morning movers" open, "Bangkok Showup" launched), and
  `GET /rounds/:launcher`, `.../me/:address` and `.../members` for "Demo Day" equalled `GET /round`,
  `GET /me/:address` and `GET /members`. That copy was not the hosted server. The hosted server
  has run the multi-round routes since the same day (see `../PROOF.md`), and on 26 November 2026 at
  13:25 UTC its `GET /health` answered `"ok": true` with the attester
  `0x2f2ab3da0b824f9ca3edd2580443ca0b271efdd7`, the faucet wallet
  `0xac33de0fe7c7a2e779a9ba9c116c1ffe0acd19f8` and `origin.host` equal to `origin.onChain`.
- Real check-ins signed by the hosted server have been sent on the real testnet (`../PROOF.md`,
  rounds 1 and 2, and "Bangkok Demo Run" at 3 of 12), and rounds have been started from the app
  ("morning movers", and "Night Owls" with the unlisted switch). Which of them went through
  `POST /rounds` and `POST /rounds/:launcher/checkin` rather than the older single-round routes was
  not recorded call by call.
- The faucet runs from its own wallet, `0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8`
  (`FAUCET_PRIVATE_KEY`, `FAUCET_DRIP_BNB` 0.012 test BNB at the event): the hosted `GET /health`
  names it, and on 26 November 2026 at 10:49 UTC its nonce read 6 and its balance 0.4279 test BNB
  (funded with 0.5). Its payouts were not checked transaction by transaction.
- The origin announcer has sent a real `setOrigin`: the attester wrote the tunnel host on
  25 November 2026 at 20:55 UTC
  ([`0x2919b1d9…1c11e`](https://testnet.bscscan.com/tx/0x2919b1d9b83c28cfc11c203998a2459eb6212893a112e264ea8644312f51c11e)),
  and on 26 November at 13:25 UTC `origin()` read `reviews-resume-tunes-advisors.trycloudflare.com`,
  the same host `GET /health` reports. Reading `/quicktunnel` from the tunnel container needs
  cloudflared's metrics server on `0.0.0.0:20241` (`--metrics`, as in `../deploy/docker-compose.yml`).
- The address pattern of a token's page on Flap for testnet tokens is not known here, which is why
  `FLAP_TOKEN_URL` has no default.
- The Season rule (`SEASON_*`) is checked on the fake chain only: refusing a check-in needs the
  attester key. On 26 November 2026 a local copy of this server with no key started from
  `.env.example`'s `SEASON_*` lines and read the real BSC testnet: with the lines empty there was no
  Season and every round's `season` was `null`; with Season 1's values and one existing round
  ("morning movers") standing in for Squad A, that round carried the Season (`day` 0) and every
  other round, "Bangkok Demo Run" included, `null`. The rule now runs on the hosted server for Season
  1 Squad A (`0xa60e2f022d891dd394415a594c9e33614c019153`, created 26 November 2026): at 13:25 UTC
  `GET /rounds/<Squad A>` carried `season` (name "Season 1", 2026-12-01 to 2026-12-30, joinUntil
  2026-12-07, squadSize 10, `day` 0) and "Bangkok Demo Run" `null`. A refused check-in (`409`
  `season_not_started`) on the hosted server was not tried, because Squad A has no members yet.
