# Scripts

Operator scripts for BSC testnet (chain 97). Test assets only: test BNB for gas and Flap's free-mint
test USD, neither has any value.

| File | What it does | Sends transactions |
|---|---|---|
| `refund-proof.ts` | Runs the "group falls short" ending on chain: a full bar, no launch, 100% back after the deadline. | Yes, 7, from the deployer |
| `run-round.ts` | With `CREATE_ONLY=true`: opens and sponsors a real round (a Season squad), then stops. Without it: a whole test round end to end. | Yes |
| `preflight.sh` | Read-only check before a live demo (API host, Flap factory status, faucet, rounds). | No |
| `deploy-testnet.sh` | Deploys the two factories (asks before sending). | Yes |
| `run-season.ts` | Archive of the earlier product's run. Targets contracts and routes that no longer exist. | Cannot run today |

## Before you run anything

- Run the TypeScript scripts from the `verifier` folder, because viem comes from `verifier/node_modules`:
  `cd verifier && npx tsx ../scripts/<script>.ts`.
- **Keys.** The deployer key is `PRIVATE_KEY` in `contracts/.env`. `run-round.ts` also reads `ADMIN_TOKEN` and,
  if `ATTESTER_ADDRESS` isn't set, derives the attester's address from the key in `verifier/.env`. Keys stay in
  memory and are never printed or written to any file.
- **One sender at a time.** Every script here sends from the same deployer key, so don't send from two of them at
  the same moment: the nonces would clash. A clash only costs a rerun, because each script continues from its file.
  There is one safe overlap: `refund-proof.ts` sends nothing while it says `waiting for a block after …`.
- **Transactions.** Each one is a legacy transaction at 1 gwei with an explicit gas limit. Fee estimation on this
  testnet can return 1 wei, and such transactions are never mined. `refund-proof.ts` dry-runs every transaction
  with `eth_call` before it sends it; `run-round.ts` dry-runs only the opening `Portal.newLauncher` call (and shows
  some refusals, such as a launch below the floor, by dry run without sending).
- **Output files are git-ignored.** `.gitignore` ignores `scripts/*-run.json` and `scripts/*-result.json` as local
  run state. To publish the refund proof, copy the hashes into PROOF.md or run `git add -f scripts/refund-result.json`.
  It holds only public chain data: addresses, hashes, balances, and the check-in signature that is in the calldata.
- **Deployer balance** at 26 Nov 2026, 12:23 UTC: 0.394 test BNB and 0 test USD. The scripts mint the test USD they
  need. Both jobs below together spend about 0.012 test BNB, about 0.005 of it per round being the Portal's salt
  lock fee.

## 1. Refund proof (P0)

```sh
cd verifier && npx tsx ../scripts/refund-proof.ts
```

It needs no server, never touches the featured round, and takes about 12 minutes. Most of that is waiting for the
round's 10-minute deadline. The deployer plays every part:

- **Creator:** opens a round through our factory with deposit 100 test USD, `liquidityBps` 3000, goal 1 check-in,
  and a deadline 10 minutes after the opening block.
- **Attester:** the round names the deployer, not our server's key. So our server can't sign for it and leaves it
  out of `GET /rounds` and `/stats`.
- **Member:** `join()`, which pays 100.
- **Sponsor:** `sponsor(50)`.

What happens:

1. Mint 150 test USD and approve the Launcher. Then `join()` and `sponsor(50)`.
2. One check-in, signed by hand over the contract's own `checkInDigest(wallet, day)`. The bar is full (1 of 1).
3. `eth_call launch()` reverts with Flap's floor error (selector `0xa32ef056`, `(80, 1500)` test USD): the shop would
   get 50 + 30% of 100 = 80. This was dry-run on 26 Nov with a state override, and the Portal answered
   `(900, 1500)` for a 900 shop, so the floor is 1,500 today. Nothing is sent.
4. `eth_call refund()` before the deadline gives `RefundUnavailable`. Nothing is sent.
5. The script waits for a block whose timestamp is past the deadline. It uses the chain's clock, not the computer's.
6. `refund()`: the deployer gets back exactly 150 (100 deposit + 50 sponsor money). After it, `isMember` is false and
   `refundable()` is 0.
7. `eth_call refund()` again gives `NothingToRefund`.

The 7 transactions are `newLauncher` (with the 0.005 test BNB salt lock fee), mint, approve, `join`, `sponsor`,
`checkIn` and `refund`. The script stops before sending anything if the deployer holds less than about 0.0121 test BNB.

**Output: `scripts/refund-result.json`.** The script writes it as it goes.

- `ok: true` means all 9 checks passed. The exit code is 1 otherwise.
- `links.launcher` and `links.refundTx` are BscScan links.
- `steps.<step>.tx` and `transactions[]` hold every hash with its block.
- `balances.deployerTestUsd` holds the balances read at the block before the refund and at the refund's block.
- `checks[]` holds each check with its detail.

Quick look:

```sh
jq '{ok, status, launcher: .addresses.launcher, refund: .links.refundTx, balances, checks: [.checks[] | {name, pass}]}' scripts/refund-result.json
```

**Running it again.**

- It refuses if the file already records a success, and sends nothing.
- `--again` runs a new round; the old result is kept under `previousRuns`.
- If a run stops (Ctrl-C, RPC error, laptop asleep), the same command continues the same round where it stopped,
  the wait for the deadline included.

**For PROOF.md:** the launcher address, the 7 transaction hashes, the refund block, the deployer's test USD before and
after (+150), and the three `eth_call` refusals (`launch` below the floor, `refund` before the deadline, a second
`refund`). It ran on 26 Nov 2026 (13:12 to 13:22 UTC; all 9 checks passed), and PROOF.md, "Refund on testnet",
carries these values.

**Refund without us.** Any member of a round that didn't launch can do this, from one second after its deadline,
with no app and no server:

```sh
cast send <launcher> "refund()" --legacy --gas-price 1gwei --gas-limit 150000 \
  --rpc-url https://bsc-testnet-rpc.publicnode.com --interactive
```

## 2. Season 1 Squad A (P1): create only

**Don't feature it before judging.** The command below never does: Bangkok Demo Run stays the featured round.

**Order.** The server signs check-ins for any round created with its key. Until it restarts with Squad A in
`SEASON_LAUNCHERS`, it would sign a pre-season day for Squad A. So do steps 2 and 3 back to back.

1. Deploy the server code that has the Season gate, with every `SEASON_*` empty. Check in once on the demo round
   (Bangkok Demo Run).
2. Create Squad A with the command under "Create" below. It prints the launcher address. `GET /rounds/<launcher>`
   answers at once. The app's list (`GET /rounds`) shows the round 180 seconds after its creation
   (`LISTING_DELAY_SECONDS`).
3. Right away, within about 3 minutes, add the Season to the server's environment and restart it:

   ```sh
   SEASON_NAME="Season 1"
   SEASON_LAUNCHERS=<launcher>
   SEASON_START=2026-12-01
   SEASON_END=2026-12-30
   SEASON_JOIN_UNTIL=2026-12-07
   SEASON_SQUAD_SIZE=10
   ```

4. Check `.season`, read-only (`VERIFIER_URL` as in "Server address" below), then run the DEMO.md checklist:

   ```sh
   curl -s "$VERIFIER_URL/rounds/<launcher>" | jq .season
   curl -s "$VERIFIER_URL/round" | jq .season
   ```

   Until 1 Dec the first shows `"name": "Season 1"`, `"start": "2026-12-01"`, `"end": "2026-12-30"`,
   `"joinUntil": "2026-12-07"`, `"day": 0`, `"days": 30` and `"squadSize": 10`. The second, the featured demo
   round, shows `null`: the gate leaves it alone.

**Done on 26 Nov 2026.** Squad A is
[`0xA60e2f022D891Dd394415A594c9e33614c019153`](https://testnet.bscscan.com/address/0xA60e2f022D891Dd394415A594c9e33614c019153),
opened and sponsored at 13:13 UTC (`scripts/season1-a-run.json`; every hash is in PROOF.md, "Season 1 Squad A"),
and the server runs with the gate on: at 13:25 UTC `GET /rounds/<Squad A>` showed the Season and the featured demo
round `null`. The no-code fallback (creating the squad just after 00:00 UTC on 1 Dec) was not needed.

**Create.**

```sh
cd verifier && CREATE_ONLY=true ROUND_NAME="Season 1 Squad A" DEPOSIT_USD=100 LIQUIDITY_BPS=0 \
  CHECKIN_GOAL=240 DEADLINE_AT=2026-12-31T23:59:59Z SPONSOR_USD=1500 \
  ATTESTER_ADDRESS=0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7 \
  STATE_FILE=../scripts/season1-a-run.json npx tsx ../scripts/run-round.ts
```

**Server address.** The API host is in the OriginRegistry (read-only):

```sh
VERIFIER_URL="https://$(cast call --rpc-url https://bsc-testnet-rpc.publicnode.com \
  0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 'origin()(string)' | tr -d '"')/api"
```

Add `VERIFIER_URL` to the "Create" command, and the script first checks, with a read-only `GET /health`, that the
live server signs as `ATTESTER_ADDRESS`. Without it, the script does not contact the server at all.

**What it does.** It sends 4 transactions from the deployer: `Portal.newLauncher` (with the 0.005 test BNB salt
lock fee), mint 1,500 test USD, approve, and `sponsor(1500)`.

- The new round has:
  - deposit 100;
  - `liquidityBps` 0, so every deposit is prize and the shop is the sponsor's 1,500, Flap's floor at our 1x;
  - goal 240 (10 × 30 × 0.8);
  - deadline `1798761599` (Thu 31 Dec 2026, 23:59:59 UTC);
  - attester = the server's key.
- It needs at least about 0.0115 test BNB. The script checks this before sending.
- It prints the launcher and BscScan link, then a JSON read-back of the round from the chain.

**What it does not do.**

- No `POST /admin/round`: the featured round is unchanged.
- No throwaway members, no check-ins.
- A state file started with `CREATE_ONLY` refuses to continue without it.
- `CREATE_ONLY` only accepts `true` or `false`. A typo stops the script instead of running the full flow, which
  would feature the round.
- `SPONSOR_USD` is the deployer's total, so a rerun never sponsors twice.

**Output: `scripts/season1-a-run.json`** (git-ignored).

- `done.open.launcher` and `done.open.tx` are the creation.
- `done.sponsor.tx` is the sponsoring.
- `done.created` is the read-back from the chain.
- `txs[]` holds every hash.

Quick look: `jq '.done.created' scripts/season1-a-run.json`.

**Check it on chain** (read-only):

```sh
L=<launcher>; R=https://bsc-testnet-rpc.publicnode.com
for f in 'name()(string)' 'deposit()(uint256)' 'liquidityBps()(uint256)' 'checkInGoal()(uint256)' \
         'deadline()(uint256)' 'attester()(address)' 'poolQuoteNow()(uint256)' 'memberCount()(uint256)'; do
  echo "$f = $(cast call --rpc-url $R $L "$f")"; done
# expect: "Season 1 Squad A", 100e18, 0, 240, 1798761599, 0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7, 1500e18, 0
```

**Next, for other owners.**

- The server's `SEASON_*` values: step 3 of "Order" above.
- PROOF.md gets the creation and sponsor hashes.
- The deck's `links` slide gets the BscScan link.
- Feature the round only after judging (`POST /admin/round`, see DEMO.md).

**Two facts to keep honest.**

- *"Earliest 24 Dec"* holds for a squad of 10 checking in every day from 1 Dec. The contract has no member cap, so
  joins made straight on the contract beyond 10 let the bar fill sooner: 11 members, 22 Dec; 12 members, 20 Dec.
- **Token symbol.** `ROUND_SYMBOL` defaults to `CYPHER`, the same symbol the earlier test rounds used. Set another
  one if the squad's coin should have its own. It only matters if the squad launches.

## 3. A full test round (`run-round.ts` without `CREATE_ONLY`)

```sh
cd verifier && VERIFIER_URL=https://<host>/api npx tsx ../scripts/run-round.ts
```

**Warning:** this POSTs `/admin/round`, which **changes the featured round**. Then it funds and joins three
throwaway members, checks in with typed (self-reported) steps, launches, trades and claims. Don't run it before
judging. The full list of settings is in the header of `run-round.ts`. These were added for the final build:

- `CREATE_ONLY`;
- `DEADLINE_AT` (an ISO time with a zone, overriding `DEADLINE_HOURS`);
- `CHECKIN_GOAL` up to 1,000,000;
- empty values count as unset.

## 4. Checks (no transactions)

**Contract tests**, offline. The fork suite needs an RPC and is skipped here.

```sh
cd contracts && forge test --no-match-path 'test/*.fork.t.sol'
```

That's 75 tests: 44 CheckInLauncher, 17 StreakVault, 6 OriginRegistry, 2 Salt and 6 KeepUpGuarantee.

`test/KeepUpGuarantee.t.sol` plays whole rounds on the real contracts:

- 1 to 20 members;
- 0 to 30 days each;
- late joiners and 0-day members;
- any deposit;
- a sponsor at or above the floor;
- test USD sent straight to the Launcher;
- up to 1e30 wei of tax with claims in between.

Every member whose days × members ≥ all check-ins gets:

- at least the whole deposit back in test USD when `liquidityBps` is 0;
- at least 70% of it when `liquidityBps` is 3000;
- at least `deposit × (10000 − liquidityBps) / 10000` for any share.

There are 1,024 random rounds per property in every `forge test`, and 10,000 per property in a one-off deep run
on 26 Nov (the inline `fuzz.runs` raised in a scratch copy), with no failure.
It also pins the stage numbers:

- Squad A at 6×30 + 3×20 + 1×0 days pays 125 / 83.33 / 0.
- Round 1 at 0% pays 1,000 / 500 / 0.
- The honest edge: a launch before your day-30 check-in leaves you 96.99, under the deposit but at least 29/30 of it.

**Typecheck the scripts** without running them. This writes a temporary tsconfig with the verifier's strict
settings:

```sh
cd verifier && D=$(node -e '
const fs = require("fs"), p = require("path"), os = require("os");
const nm = p.resolve("node_modules"), s = p.resolve("../scripts");
const dir = fs.mkdtempSync(p.join(os.tmpdir(), "scripts-tsc-"));
fs.writeFileSync(p.join(dir, "tsconfig.json"), JSON.stringify({
  compilerOptions: { target: "ES2022", module: "ESNext", moduleResolution: "Bundler", strict: true,
    noUncheckedIndexedAccess: true, skipLibCheck: true, noEmit: true, types: ["node"], typeRoots: [nm + "/@types"],
    paths: { "viem": [nm + "/viem/_types/index.d.ts"], "viem/accounts": [nm + "/viem/_types/accounts/index.d.ts"],
      "viem/chains": [nm + "/viem/_types/chains/index.d.ts"] } },
  files: [s + "/run-round.ts", s + "/refund-proof.ts"] }));
console.log(dir);') && npx tsc -p "$D/tsconfig.json" && echo "scripts typecheck: ok"
```
