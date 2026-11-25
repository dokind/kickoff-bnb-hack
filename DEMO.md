# Cypher Run demo (earlier design, under the first working name Pacepact): one real season on BSC testnet in about an hour

> **Out of date.** This walk-through is for the earlier design (running club seasons) and does not
> match the current app, server or contracts. The current demo is in the "Demo" section of
> [README.md](README.md) and at the top of `scripts/run-round.ts`.

The shortest full season: open, fill, warm-up, launch through Flap, trade, settle, claim. Two iPhones
and one browser, three wallets, test tokens only.

**Status: this script has not been run end to end yet.** Every step is covered by tests (the
contract steps against the live testnet Portal in a fork, the verifier and app steps with fakes), but
no transaction has been sent and the iPhone build has not been run on a device. Do one full rehearsal
before recording. Where a step is likely to bite, it says so.

## Who is who

| Role | Device | Wallet | What they do |
|---|---|---|---|
| Operator | laptop terminal | deployer key, verifier key, trader key | deploys, runs the verifier, starts the season, trades, settles |
| Captain | Chrome on the laptop | made by the web app | opens the season, joins, **cannot sync runs** (a browser has no health data), so misses the goal |
| Runner A | iPhone A, Pacepact app | made by the app | joins, walks, syncs, reaches the goal, claims |
| Runner B | iPhone B, Pacepact app | made by the app | joins, walks, syncs, reaches the goal, claims |

Three members, two finishers, one miss. The two finishers split the vault half and half; the captain
gets nothing from it. That shows every rule in one season.

Who decides what, said plainly on camera: the contracts hold the money. **Our server, the verifier,
decides when the club has run its warm-up and who reached their goal.** The contract takes its word
for both.

## Numbers for the demo

| Setting | Value | Why |
|---|---|---|
| Join fee | 500 test USD | form default |
| Target raise | 1,500 test USD (3 places) | Flap's testnet Portal will not launch a pool below 1,500 |
| Goals measured in | Steps | steps show up in Apple Health within a minute of walking; distance indoors is unreliable |
| Club warm-up | steps both phones show today, added up, **plus 200** | so the first sync is just short and a short walk in the room finishes it (see "Before you start") |
| Runner A and B goal | own steps today **plus 150** | reached during the same walk |
| Captain goal | 5000 steps | never reached: the browser cannot sync |
| Last day to join | open time + 30 minutes | the season must be started (kickoff) by then, or it turns into refunds |
| Season ends | open time + 45 minutes | settle is possible from this minute |

Why "steps today plus": a sync sends the phone's whole-day step count for today, not only the steps
since joining. That is how the daily summaries work, and it is why the targets are set relative to
what the phones already show.

Test funds per wallet: about 0.02 tBNB for gas (gas is 0.1 gwei on testnet today, so this is far more
than needed; the captain also pays the Portal's 0.005 tBNB salt lock fee) and 1,000 test USD from
"Get test funds". Faucet: https://www.bnbchain.org/en/testnet-faucet

## Before you start (once, about 30 minutes)

Do these in order. Nothing here is part of the recording.

### 1. Three operator keys

Make three throwaway testnet keys and fund each with a little tBNB. Never reuse a key that holds
anything real, and never paste a key into a file that is committed.

```sh
cast wallet new        # run three times: deployer, verifier, trader
```

- Deployer key: `PRIVATE_KEY` in `contracts/.env` (0.01 tBNB is plenty).
- Verifier key: `VERIFIER_PRIVATE_KEY` in `verifier/.env` (0.01 tBNB; it pays for kickoff, about
  5 million gas, and for settle).
- Trader key: kept in the shell only (step 7). 0.01 tBNB.

Write down the **verifier address** (the address, not the key). You need it for the app builds:

```sh
cast wallet address --interactive     # paste the verifier key at the hidden prompt
```

### 2. Deploy the factories

```sh
scripts/deploy-testnet.sh --dry-run   # simulates, sends nothing
scripts/deploy-testnet.sh             # asks, then sends 2 transactions
```

It writes `contracts/deployments/bsc-testnet.json` and prints the app commands.
**Save: the two deployment transaction hashes** (in the forge output).

### 3. Start the verifier where the phones can reach it

In `verifier/.env`: `ADMIN_TOKEN` (any long random text), `RPC_URL=https://bsc-testnet-rpc.publicnode.com`,
`SKIP_CHAIN_CHECKS=false`, `VERIFIER_PRIVATE_KEY` (the verifier key).

```sh
cd verifier && npm install && npm start      # http://localhost:8787
ngrok http 8787                              # second terminal: gives an https address
```

The phones use the https address ngrok prints. (On a network where the phones can reach the laptop
directly, `http://<laptop LAN address>:8787` also works; the iPhone build allows plain http on the
local network only.) The captain's browser runs on the laptop and uses `http://localhost:8787`, which
avoids the warning page a free ngrok address can put in front of browser requests.

```sh
export VERIFIER_URL=http://localhost:8787          # for the terminal and the captain's browser
export PHONE_VERIFIER_URL=https://<your-ngrok-address>
export ADMIN_TOKEN=<the same text as in verifier/.env>
curl $VERIFIER_URL/                # {"service":"pacepact-verifier","ok":true}
curl $PHONE_VERIFIER_URL/          # the same, through the tunnel
```

### 4. Build the app for the browser and for the phones

```sh
# Captain's browser
VERIFIER_ADDRESS=0x<verifier address> VERIFIER_URL=$VERIFIER_URL WEB_BASE_URL=http://localhost:8080 \
  scripts/deploy-testnet.sh --print
# The two iPhones: same addresses, the tunnel as verifier
VERIFIER_ADDRESS=0x<verifier address> VERIFIER_URL=$PHONE_VERIFIER_URL WEB_BASE_URL=http://localhost:8080 \
  scripts/deploy-testnet.sh --print
```

Run what it prints, in `app/`:

- Captain's browser: the `flutter run -d chrome` command from the first print (add `--web-port=8080`).
- Each iPhone: plug it in and run the `--dart-define` values from the second print with
  `flutter run --release -d <device id>` (`flutter devices` lists the ids). `flutter build ipa` is
  the route for installing without a cable. The first run asks for Xcode signing and, on the phone,
  for the developer to be allowed in Settings.

**`VERIFIER_ADDRESS` must be the address of the key the server runs with.** If it is not, the server
can never start the season and the only way out is the refund after the deadline.

`WEB_BASE_URL` only decides what the join QR says. The phones scan the QR from inside the app
("Scan a join code"), which reads the season from the link, so the web app does not need to be hosted
for this demo.

### 5. Fund the three app wallets

On each device: finish the three onboarding steps, open the wallet screen, copy the address, send it
tBNB from the faucet (or from the deployer with
`cast send <address> --value 0.02ether --rpc-url https://bsc-testnet-rpc.publicnode.com --interactive`),
then tap **Get test funds** (1,000 test USD). On the phones allow Apple Health access for steps.

### 6. Read the phones' steps

Open the Health app on each phone and read "Steps" for today. Example: A shows 4,200 and B shows
3,100. Then for this demo:

- Club warm-up = 4,200 + 3,100 + 200 = **7500**
- A's goal = 4,200 + 150 = **4350**, B's goal = 3,100 + 150 = **3250**

Do this right before step 1 below and keep the phones still until the walk.

## The season, step by step

Times are minutes after the captain opens the season (T).

### T+0. Captain opens the season (browser)

Home, **Start a season**: club name, token symbol, join fee 500, target 1500, **Steps**, club warm-up
`7500` (your number), last day to join = today, time now + 30 minutes, season ends = today, time
now + 45 minutes. Tap **Open season**. The browser searches for the launch salt for a few seconds,
then sends `Portal.newLauncher` with our `ClubLauncherFactory`.

The screen shows the join QR. Copy the launcher address from the verifier:

```sh
curl -s $VERIFIER_URL/leaderboard          # "launcher":"0x..."
export LAUNCHER=0x<launcher>
cd verifier && npm run demo:season -- $LAUNCHER     # phase: filling, 0 of 3 places
```

**Save: the open-season transaction hash** (testnet.bscscan.com, the captain's address, newest
transaction).

### T+2. Three joins: filling

- Captain: **Join it yourself**, goal `5000`, join.
- Runner A, then Runner B: Home, **Scan a join code**, scan the QR on the laptop screen, set the goal
  from step 6, join. Each join is an approve and a `contribute()` of 500 test USD.

After the third join Home shows **Warm-up** on all three devices. Say it: the raise is full and
nothing has launched. There is no token yet.

```sh
cast call $LAUNCHER "filled()(bool)" --rpc-url https://bsc-testnet-rpc.publicnode.com     # true
cast call $LAUNCHER "launched()(bool)" --rpc-url https://bsc-testnet-rpc.publicnode.com   # false
cast call $LAUNCHER "token()(address)" --rpc-url https://bsc-testnet-rpc.publicnode.com   # zero address
```

**Save: the three join transaction hashes.** The third one carries the `Filled` event.

### T+6. Warm-up: the server says "not yet"

On both phones tap **Sync today**. Home shows about "7,300 of 7,500 steps". Ask the server to start
the season. It refuses and sends nothing:

```sh
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $VERIFIER_URL/seasons/$LAUNCHER/kickoff
# 409 {"error":"club_total_short", ... "clubTotal":7300,"kickoffTarget":7500,"calldata":null}
```

### T+8. The club walks

Both runners walk about 150 steps each around the room, phone in hand. Open the Health app on each
phone until the new steps show (it can take up to a minute), then tap **Sync today** again. Home
shows the warm-up reached, and both runners are past their own goals.

### T+12. Kickoff: the token launches (the new part)

```sh
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" "$VERIFIER_URL/seasons/$LAUNCHER/kickoff?dryRun=true"
# {"ready":true,"reason":"ready", ...}
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $VERIFIER_URL/seasons/$LAUNCHER/kickoff
# {"ready":true, ... "txHash":"0x...","sent":true}
```

The server sends `ClubLauncher.kickoff()`. In that one transaction the Flap Portal creates the club
token, seeds the PancakeSwap pool with the 1,500 test USD and half the supply, and creates the
GoalVault holding the other half. Home turns to **Live**.

```sh
RPC=https://bsc-testnet-rpc.publicnode.com
export TOKEN=$(cast call $LAUNCHER "token()(address)" --rpc-url $RPC)
export VAULT=$(cast call $LAUNCHER "vault()(address)" --rpc-url $RPC)
echo $TOKEN $VAULT
```

**Save: the kickoff transaction hash.** It is the Flap launch, the most important one. Also note the
launcher, token and vault addresses.

If kickoff must be done by hand (the server has no key): the response's `calldata` (`0x` plus 8 hex
digits) is sent to the launcher from the verifier address:
`cast send $LAUNCHER "kickoff()" --rpc-url $RPC --interactive --gas-limit 7000000`.

It has to happen before "last day to join" (T+30). After that the contract refuses and members take
their join fee back.

### T+15. Trading tax reaches the vault (operator, trader key)

Buys pay 3% tax and sells 5%; 80% of it goes to the vault once the token's tax processor has sold it
into test USD and someone calls `dispatch()`. In the fork test one 1,000 USD buy plus one
sell-and-rebuy round sent about 37 test USD to the vault.

```sh
RPC=https://bsc-testnet-rpc.publicnode.com
USD=0x190C989D5665a0e404B444b53CAE9AbCfb600157
ROUTER=0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3        # PancakeSwap V2 router the Portal uses on testnet
read -s TRADER_KEY                                       # paste the trader key; it is not shown or saved
TRADER=$(cast wallet address --private-key $TRADER_KEY)
send() { cast send --rpc-url $RPC --private-key $TRADER_KEY "$@"; }
swap() { send $ROUTER "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" \
  "$3" 0 "[$1,$2]" $TRADER $(($(date +%s) + 600)); }
bal()  { cast call $1 "balanceOf(address)(uint256)" $2 --rpc-url $RPC | cut -d' ' -f1; }
MAX=$(cast max-uint)

send $USD "mint(address,uint256)" $TRADER 1000ether
send $USD "approve(address,uint256)" $ROUTER $MAX
send $TOKEN "approve(address,uint256)" $ROUTER $MAX
swap $USD $TOKEN 1000ether                                    # buy
swap $TOKEN $USD $(echo "$(bal $TOKEN $TRADER) * 30 / 100" | bc)   # sell 30%
swap $USD $TOKEN $(echo "$(bal $USD $TRADER) * 90 / 100" | bc)     # buy again

PROC=$(cast call $TOKEN "taxProcessor()(address)" --rpc-url $RPC)
cast call $PROC "feeQuoteBalance()(uint256)" --rpc-url $RPC   # above zero: the tax has been sold
send $PROC "dispatch()"
cast call $USD "balanceOf(address)(uint256)" $VAULT --rpc-url $RPC   # test USD now in the vault
```

If `feeQuoteBalance()` is still zero, repeat the sell and the buy line once more, then dispatch.
These commands are written from the fork test and have not been run against a live season yet;
rehearse them.

**Save: one swap hash and the dispatch hash.** Show the vault's test USD balance.

### T+45. Season ends, the server settles

Wait until a minute after the season end. Home shows **Over**.

```sh
curl -s -X POST -H "Authorization: Bearer $ADMIN_TOKEN" $VERIFIER_URL/seasons/$LAUNCHER/settle
# {"root":"0x...","count":2, ... "txHash":"0x..."}
```

The server works out who reached their own goal (A and B), and posts the Merkle root of those two
addresses to the GoalVault with `settle(root, 2)`. The list is fixed from this moment.

**Save: the settle transaction hash.**

### T+47. Claim

- Runner A and Runner B: Home, **See result**, **Claim my share**. Each receives half of the reserved
  club tokens (250,000 each) and half of the test USD tax in the vault.
- Captain: **See result** shows that the goal was missed and there is nothing to claim.

**Save: the two claim transaction hashes.**

## Optional second take: the refund

Open another season with "last day to join" 5 minutes away. Join from two devices only (or fill it
and never call kickoff). After the time passes Home shows **Not started** and **Get your join fee
back**; each member gets their 500 test USD back. **Save: one refund hash.**

## What to hand in

| # | What | From |
|---|---|---|
| 1 | GoalVaultFactory and ClubLauncherFactory addresses, 2 deployment hashes | `contracts/deployments/bsc-testnet.json`, forge output |
| 2 | Open season (`Portal.newLauncher` with our Launcher Factory) | captain's address on testnet.bscscan.com |
| 3 | Three joins (`contribute`), the third with `Filled` | each member's address |
| 4 | **Kickoff (`ClubLauncher.kickoff`, the Flap launch)**, plus launcher, token, pool and vault addresses | the kickoff response `txHash` |
| 5 | One swap and `dispatch()` (tax reaches the vault) | trader's address |
| 6 | Settle (`GoalVault.settle`) | the settle response `txHash` |
| 7 | Two claims (`GoalVault.claim`) | Runner A's and B's addresses |
| 8 | Optional: one refund | member's address |

## If something goes wrong

| What you see | Cause | Do this |
|---|---|---|
| Start a season shows "Not configured yet" | the build has no addresses | rebuild with the `--dart-define` values from `scripts/deploy-testnet.sh --print` |
| "The season is on chain, but the verifier did not register it" | the app could not reach `VERIFIER_URL` | fix the address or the tunnel, then register by hand: `curl -X POST -H 'content-type: application/json' -d '{"launcher":"0x...","name":"...","goalUnit":"steps","seasonEnd":<unix seconds>,"kickoffTarget":7500}' $VERIFIER_URL/seasons` |
| Sync says "activity counts once the season is full" | still filling | all three must join first |
| Sync sends the old step count | Apple Health has not caught up | open the Health app, wait for the number to move, sync again |
| Kickoff answers `club_total_short` | warm-up not reached | walk, sync, ask again |
| Kickoff answers `kickoff_closed` | "last day to join" has passed | this season can only be refunded; open a new one with more time |
| Kickoff transaction reverts `NotVerifier` | the app was built with a different `VERIFIER_ADDRESS` | rebuild with the right address and open a new season |
| Settle answers `season_not_over` | too early | wait for the season end, then a few more seconds for the next block |
| Claim fails for a runner | settled before their last sync arrived | the list is fixed at settle; sync before the season end |
