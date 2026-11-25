# Cypher Run verifier

The server side of Cypher Run: a discipline app with money on it. You pay a deposit to
join and check in every day you move. Everyone's check-ins fill one bar. When it is full, a token
launches on Flap, and the deposits and the token are shared by how many days each person showed up.

This server does five things (a round is one `CheckInLauncher`):

- **Finds the rounds.** Every round created through our `CheckInLauncherFactory` is found in the
  factory's creation events on chain. `GET /rounds` is the app's public list of them; see "Rounds:
  how they are found and listed".
- **Signs check-ins.** A member reports today's steps; if the report passes the rules below, the
  server answers with the attester's signature, and the member's own wallet sends
  `CheckInLauncher.checkIn(day, signature)`.
- **Remembers the accepted days**, for streaks, per round.
- **Relays what the chain says** about a round and about one wallet, so the app needs one request
  instead of many reads.
- **Runs a gas faucet** that sends a new wallet 0.03 test BNB once (off by default).

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

What whoever runs this server and holds the attester key **can** do:

- sign a check-in for a member without a real report, or refuse to sign for a member who moved.
  Since the prize and the reserved tokens are shared by days checked in, that changes shares. This
  is the one thing members rely on the operator for.

What it **cannot** do, because the contracts do not allow it:

- launch early: `launch()` needs the bar to be full, and anyone may call it then;
- block a launch: once the bar is full, any wallet can call `launch()` before the deadline;
- choose who is paid in any way other than by signing or not signing daily check-ins: there is no
  list of winners to post and no settle step; `StreakVault.claim()` pays by `daysOf / totalCheckIns`;
- record a check-in for a wallet that has not joined, for a day other than today or yesterday, or
  twice for one day;
- move, withdraw or redirect funds: no address, including the attester, the creator and a sponsor,
  can take anything out of the Launcher or the vault other than through `refund()` and `claim()`;
- stop refunds: if the round has not launched by its deadline, each member takes the full deposit
  back and each sponsor their contribution.

Other things to know:

- **This server sends no transaction to the round's contracts.** Members send `join`, `checkIn`,
  `launch`, `refund` and `claim` from their own wallets. If this server is down, nobody can get a
  new check-in signed; everything else keeps working on chain.
- **The faucet spends the attester's wallet.** With `FAUCET_ENABLED=true` the server sends test BNB
  from the attester address to wallets that ask. It is limited (see `POST /faucet`) and it is the
  same key, so run it with test funds only.
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
| `ATTESTER_PRIVATE_KEY` | The key that signs check-ins and pays the faucet. It must be the key of the address the round was created with as `attester`. Without it the read routes work, `POST /checkin` answers `503 attester_disabled` and the faucet is off. Never commit it. `VERIFIER_PRIVATE_KEY`, the earlier name for the same key, is read when this one is not set. |
| `CURRENT_LAUNCHER` | Address of the featured round's `CheckInLauncher`: the one `/round`, `/me`, `/members` and `/checkin` serve, and the first in `GET /rounds`. Empty: no featured round until `POST /admin/round` sets one. A round set through that route is stored in `DATA_FILE` and wins over this variable from then on. |
| `CURRENT_ROUND_NAME` | Optional display name for `CURRENT_LAUNCHER`. Default: the name stored in the Launcher. |
| `ADMIN_TOKEN` | Shared secret for `POST /admin/round`. Without it that route answers `503 admin_disabled`. |
| `MIN_STEPS` | Steps needed for a check-in, default `1000` (1 to 80000). |
| `ALLOW_SELF_REPORTED` | `true` also accepts `source: "self"` (a typed-in count). For the testnet demo on the web. Default off. |
| `FAUCET_ENABLED` | `true` switches `POST /faucet` on. Needs `ATTESTER_PRIVATE_KEY`. Default off. |
| `TRUST_PROXY` | `true` when a reverse proxy sits in front: the faucet's per-IP limit then uses the last address in `X-Forwarded-For`. Leave it off when clients reach this server directly, or the header could be forged. |
| `FLAP_TOKEN_URL` | Optional. Address of a token's page on Flap with `{token}` in it. Used for `flapUrl` in `GET /round` after the launch. Unset: `flapUrl` is always `null`. |
| `DATA_FILE` | JSON file for storage, default `./data/store.json` (`/data/store.json` in the Docker image). |
| `LAUNCHER_FACTORY` | Address of the `CheckInLauncherFactory` whose rounds are listed. Default: the one deployed on BSC testnet, `0x2A872200B83dD025977d785cDE05356d23eA4153`. |
| `FACTORY_FROM_BLOCK` | The block that factory was deployed in; the scan for rounds starts there. Default `144816444`. |
| `LOG_CHUNK_BLOCKS` | Blocks asked for in one `eth_getLogs` call, default `10000`. A range the RPC refuses is halved and asked again, so a value that is too high only costs a few extra calls. |
| `ROUNDS_REFRESH_SECONDS` | How often the server looks for newly created rounds, default `10` (2 to 3600). |

None of the four variables above needs to be set for the deployed factory. To make a round the
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
- the round's `attester` is this server's key.

One accepted check-in per wallet per day. Asking again on the same day returns the same signature
(for example when the transaction failed) and keeps the first accepted report. The contract itself
takes a signed day while it is today or yesterday on chain, so a signature issued just before
midnight UTC still works a little later.

**Streak**: consecutive UTC days with an accepted check-in, ending today, or ending yesterday while
today is still open. A full day without one ends it. `bestStreak` is the longest run in the round.

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
| `POST /faucet`, `POST /admin/round` | Gas for a new wallet; the operator sets the featured round. |

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
      "checkInGoal": 5, "totalCheckIns": 4, "memberCount": 6,
      "prizeNow": "2100", "poolQuoteNow": "2400",
      "deadline": 1795883661, "launched": false, "token": null, "vault": null,
      "state": "open", "featured": true
    }
  ]
}
```

Listed rounds only. Every field except `state` and `featured` is the field of the same name in
`GET /round`, with amounts as decimal strings in whole tokens.

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
  "raw": { "deposit": "1000000000000000000000", "totalDeposits": "…", "totalSponsored": "…", "poolQuoteNow": "…", "prizeNow": "…" }
}
```

| Field | Meaning |
| --- | --- |
| `name` | The display name given with the round, otherwise the name stored in the Launcher. |
| `checkInGoal`, `totalCheckIns` | The bar: `launch()` opens when `totalCheckIns >= checkInGoal`. |
| `poolQuoteNow` | What `launch()` would put in the pool: all sponsor money plus `liquidityBps` of the deposits. Flap's Portal refuses a launch below its own floor (1,500 test USD when this was written); the app should show this number next to that floor. |
| `prizeNow` | Before the launch: what `launch()` would send to the vault (the rest of the deposits). After it: everything the vault has received so far, the prize plus trading tax. |
| `token`, `vault`, `flapUrl` | `null` until the launch. `flapUrl` stays `null` unless `FLAP_TOKEN_URL` is set. |
| `today`, `dayIndex` | Today in UTC as the server sees it, and the contract's number for it (unix time / 86400). |
| `canLaunch` | The Launcher's own `canLaunch()`: bar full, not launched, before the deadline. It does not know the Portal's floor. |
| `refundOpen` | The deadline has passed and the round has not launched. |
| `attesterReady` | This server's key is the round's attester. `false` means check-ins are refused. |

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

Body `{ address, signature }` (signature over `Cypher Run faucet <address>`). Sends **0.03 test BNB**
from the attester's wallet, for gas. It does not send test USD: getting test dollars for the deposit
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
| `faucet_disabled` | `FAUCET_ENABLED` is not `true`, or there is no key. |
| `already_funded` | This address was funded before. Once per address, for good. |
| `cap_reached` | 200 wallets have been funded in total. The faucet stays closed. |
| `rate_limited` | 5 requests from this IP reached the sending step in the last hour. |
| `chain_unavailable` | The balances could not be read. Nothing was sent; ask again. |
| `has_funds` | The address already holds 0.002 test BNB or more. This does not use up its one payout. |
| `faucet_empty` | The attester's wallet would drop below 0.05 test BNB, which it keeps back. |
| `send_failed` | The transfer could not be submitted. The address may ask again. |

`400 bad_address` and `401 bad_signature` use the normal error shape. The faucet works with no
round set. Requests are handled one at a time, so two requests at once cannot be paid twice. Payout
records include the caller's IP address (see `TRUST_PROXY`).

Budget: 200 wallets x 0.03 = 6 test BNB plus gas. Top the attester's wallet up accordingly, or the
faucet answers `faucet_empty` long before the cap.

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

The only transactions this server sends are the faucet's transfers. They are legacy transactions at
a gas price of 1 gwei with a gas limit of 21,000: fee estimation on this testnet answers 1 wei, and
such transactions are never mined. They go through one queue, one at a time, each with an explicit
nonce, because a load-balanced public RPC can report a stale pending count.

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
src/days.ts      UTC days and streaks (pure)
src/faucet.ts    faucet amount and limits (pure)
src/store.ts     Store interface + in-memory / JSON-file store
src/chain.ts     viem reads of the Launcher and the vault; the factory's creation events; the
                 faucet's transfers, one at a time
src/rounds.ts    which rounds exist: the scan of the factory's events, in chunks, kept in the store
src/app.ts       HTTP routes
src/config.ts    builds the app from environment variables
src/server.ts    entry; looks for new rounds every ROUNDS_REFRESH_SECONDS
test/            vitest: the contracts' signature vector, check-in rules, streaks across day
                 boundaries, GET /round, /me and /members on a fake chain, the admin route, faucet
                 limits, the /api base path, the data file, and the ABI fragments against
                 ../contracts/abi. test/rounds.test.ts: discovery and its store, the list's order
                 and states, the three-minute rule, registration by the creator only, the
                 per-round routes against the single-round ones, a launcher from another factory
test/e2e-fork.ts the full round against the real contracts on a local fork (npm run e2e:fork),
                 including discovery from the factory's event and POST /rounds
Dockerfile       node:22-slim image, see "Running in Docker"
```

## Not checked

- The rounds run on the real testnet through the hosted server are recorded in `../PROOF.md` and
  `../HOSTING.md`, not here. What this folder checks on chain is checked on a local fork
  (`npm run e2e:fork`): there the contract accepted this server's signatures and the API matched the
  chain through creation, listing, join, check-in, launch and claim.
- The multi-round routes were read against the real BSC testnet on 26 November 2026 from a local
  copy of this server with no key (reads only): `GET /rounds` returned the three rounds the factory
  had created ("Demo Day" featured, "morning movers" open, "Bangkok Showup" launched), and
  `GET /rounds/:launcher`, `.../me/:address` and `.../members` for "Demo Day" equalled `GET /round`,
  `GET /me/:address` and `GET /members`. That copy was not the hosted server. The hosted server
  runs this build since the same day; what was checked there is in `../HOSTING.md`.
- `POST /rounds` has not been called with a real creator's signature outside the tests and the
  fork, and `POST /rounds/:launcher/checkin` has not been followed by a real `checkIn` transaction
  on the real testnet.
- The faucet has not sent a real transaction with the new amount.
- The address pattern of a token's page on Flap for testnet tokens is not known here, which is why
  `FLAP_TOKEN_URL` has no default.
