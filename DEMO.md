# Cypher Run demo

Six steps, in the app as it is today, on BSC testnet with test USD. Nothing to install: the web app
is at **https://dokind.github.io/kickoff-bnb-hack/** and makes a wallet in the browser. Everything
here is testnet; nothing has real value.

What the demo shows, in one line: the pot is safe, the launch is the bonus. Two endings, always: the
group misses, everyone gets 100% back; the group launches, you're paid by your days, not by your
deposit.

The scripted run of a whole round (open, join, check in, launch, trade, claim) is described under
"Demo" in [README.md](README.md). Season 1, the upcoming flagship, has its own runbook below. The
walk-through of the earlier design (running club seasons, other contracts) is kept in
[docs/archive/DEMO.md](docs/archive/DEMO.md).

## The six steps

| # | Do | What it shows |
|---|---|---|
| 1 | **Open the site or scan the QR.** https://dokind.github.io/kickoff-bnb-hack/, or a round's invite link `https://dokind.github.io/kickoff-bnb-hack/#/r/<launcher>`. | The app reads the server's current host from OriginRegistry `0xb9aD45Dc177C801f10670F2aac03B467f1C367d2` on chain before its first call, so the site works whatever tunnel host the server has today. An invite link opens with that round selected. |
| 2 | **Get started.** | A wallet is made on the device and its key stays in the browser; Wallet, "Back up your key", is the only way to open it on another device. The server's faucet sends it 0.012 test BNB for network fees, from the faucet's own wallet, when it first needs some ("Preparing your wallet"). In the browser "Get started" goes straight to Home; the check-in sheet says plainly that a browser cannot read health data, so a check-in here is typed in. |
| 3 | **Join a round.** On Home, swipe to the round and press "Join *name* · *deposit*". | The join sheet shows the deposit split: "To the prize" and "Into the shop" (70% and 30% in a default round; "None · a sponsor fills it" when 0% goes to the shop), then "If it launches" and "Last day to launch". Over the button, one line each, come the two endings, "No launch by the deadline: press Refund and your 100 test USD comes back." and "It launches: you're paid by your days, not by your deposit.", then what can be lost ("It launches and you have no check-ins: nothing comes back."; in a default round also "It launches: 30% of your deposit goes into the shop, locked forever."). One press, "Join with test dollars · *deposit*", mints the deposit in Flap's free test USD ("Get test dollars"), then approves and pays it into the round's Launcher ("Pay deposit"). "You're in." When what is left of the goal is no more than the member count (the bar can fill today), the sheet warns "This round can launch before your first check-in. If it does, you get nothing back." and the payment takes a second press, "Join anyway". On "Bangkok Demo Run" (goal 12) this can appear while the judges join: at 8 members and 4 check-ins, for example. |
| 4 | **Check in.** "Check in · *name*", then type today's steps. | The server checks the report (1,000 to 80,000 steps, a server rule) and signs the day; the member's own wallet sends `checkIn(day, signature)`. The bar on the card moves by one. On the web the steps are self-reported, a testnet-only switch on the server (`ALLOW_SELF_REPORTED=true`); the iPhone build reads Apple Health steps instead. One check-in per wallet per UTC day: a new day starts at 07:00 in Bangkok. |
| 5 | **Launch when the bar is full.** "Launch *name*". | Any wallet can press it once the bar is full, members or not. If the shop money is short of the 1,500 test USD Flap asks for today, the button is off ("The bar is full, but the shop money is … short of what Flap needs.") and "Sponsor the shop" is offered instead. The launch is one transaction through Flap Pool Launch: the coin, its shop (the pool) with the LP burned, and the round's piggy bank (the vault) with half the coins and the prize. Home then says "Launched. The coin is live." and the result screen ("Launched on Flap", "THE COIN IS LIVE.") links to BscScan testnet and to Flap. |
| 6 | **Claim.** "Claim · *name*". | The result screen shows your days and your part: your days over all check-ins, of the reserved tokens and of the test USD in the vault. Claim again later for the trading tax that arrived since (tax comes for 30 days, and only when people trade). A wallet with no check-in sees "You have no check-ins in this round": it gets nothing. |

Two more things a judge may try:

- **Start a round** (the "+" button, "Add a round", then "Start a round"): name, deposit, the goal
  (check-ins needed), "Runs for" (1 to 30 days in the app), and under "More options" the "Shop
  money" (the share of each deposit that goes into the shop: 10%, 30% by default, 50% or 100%, or
  "0% · a sponsor fills the shop", which needs a sponsor's shop money to launch and makes every
  deposit prize) and listed or unlisted. "The deal" box spells out the terms before "Start round".
  It costs about 0.007 test BNB in fees.
- **Invite** (on a round card): the link, a copy button and a QR code for that round.

## Before going on stage

- [ ] **Run the pre-talk check first**, from the repo root:

      bash scripts/preflight.sh

  It sends no transaction and reads no key. It reads the registry's host and that host's
  `/api/health`, the factory's multiplier on the Portal, how many more wallets the faucet can fund,
  and the judges' round and "Demo Day" (members, check-ins against the goal, pool, launched). Exit
  code 1 means a check failed; the items below say what each one means.
- [ ] **Never feature or demo a Season squad before 1 Dec.** Its check-ins are refused until Tue
      1 Dec 2026 00:00 UTC (07:00 in Bangkok), so a judge who joins it on stage cannot check in.
      "Bangkok Demo Run" stays the featured round for the talk and for judging, and a Season squad
      is never the backup round. On stage, show Season 1 as the upcoming flagship: join now, starts
      Tue 1 Dec.
- [ ] **The factory is still enabled on Flap's testnet Portal at 1x.** Anyone can call Flap's
      testnet helper for any factory, so read it back:

      cast call 0x000042108465206185A077Edc3F3fd2b49060000 "launcherFactoryMultiplier(address)(bool,uint256)" \
        0x2A872200B83dD025977d785cDE05356d23eA4153 --rpc-url https://bsc-testnet-rpc.publicnode.com

  Expect `true` and `10000`.
- [ ] **The registry names the server's current host.**

      cast call 0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 "origin()(string)" \
        --rpc-url https://bsc-testnet-rpc.publicnode.com

  It must not be empty, and `https://<that host>/api/health` must answer `"ok": true` with the
  attester `0x2f2ab3da0b824f9ca3edd2580443ca0b271efdd7` (in lower case there). If the tunnel
  restarted, the server writes the new host on its next check (every 60 seconds by default,
  `ORIGIN_CHECK_SECONDS`).
- [ ] **The server the apps will find serves the demo round, and the Season rule is where it
      belongs.** With `<host>` from `origin()` above (read-only, no key):

      curl -s -o /dev/null -w '%{http_code}\n' https://<host>/api/round
      curl -s https://<host>/api/round | jq '{name, season}'
      curl -s https://<host>/api/rounds/0xcf7957dc48e5c16732331d27e2c2a1b2a9fa5876 | jq .season
      curl -s https://<host>/api/rounds/0xa60e2f022d891dd394415a594c9e33614c019153 | jq .season

  Expect `200`; then `"name": "Bangkok Demo Run"` with `"season": null`; `null` again for the demo
  round; and for Season 1 Squad A a `season` object named "Season 1" (start `2026-12-01`, end
  `2026-12-30`, joinUntil `2026-12-07`, squadSize 10). On 26 Nov 2026 at 13:25 UTC all four read
  as expected (`origin()` was `reviews-resume-tunes-advisors.trycloudflare.com`). Check them again
  after any server restart.
- [ ] **Never feature Squad A before judging.** The featured round must stay "Bangkok Demo Run";
      do not call `/api/admin/round` for Squad A, and never run `scripts/run-round.ts` without
      `CREATE_ONLY=true` against the hosted server until judging is over.
- [ ] **After any server deploy, check in once on the demo round** and see the bar move. A server
      change for Season squads must leave every other round alone.
- [ ] **The TestFlight build is approved**: https://testflight.apple.com/join/bp4WaEu5 opens the
      Cypher Run page in TestFlight. The link opens only after Apple approves the beta of build
      202611261356; until then it says the beta is not accepting testers. If it is not approved,
      send iPhone judges to the web app or the Android APK.
- [ ] **The Android download works**: the newest run of the "Android app" workflow is green and
      https://github.com/dokind/kickoff-bnb-hack/releases/download/android-latest/cypher-run.apk
      downloads.
- [ ] **The site opens on mobile data**, not on the venue wifi: https://dokind.github.io/kickoff-bnb-hack/
      on a phone with wifi off, through Get started to Home.
- [ ] **A fresh round with room for the judges.** Start one shortly before the talk, with a goal
      the people in the room can fill in one sitting (each wallet checks in once per UTC day) and a
      deadline days away. Do not send judges to a round that is about to close or one check-in from
      full: "Demo Day" stands at 4 of 5 and its deadline is 28 Nov 2026 16:34 UTC. Plan the shop
      money: 30% of the deposits plus any sponsor money must reach 1,500 test USD before Launch
      works (five members at a 1,000 test USD deposit, or fewer and a sponsor through "Sponsor the
      shop").
      Done for Bangkok: "Bangkok Demo Run"
      [`0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876`](https://testnet.bscscan.com/address/0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876),
      opened 26 Nov 2026 04:34 UTC with `scripts/run-round.ts` (deposit 100 test USD, goal 12
      check-ins, deadline 30 Nov 2026 00:34:28 UTC). The deployer sponsored 1,410 test USD at once,
      so the pool already reads 1,530 test USD (`poolQuoteNow()`, 1,410 + 30% of 4 × 100), above
      the 1,500 floor: only check-ins decide the launch. It is a default round (30% of each
      deposit to the shop), so do not show the Keep-Up Guarantee on it. Read with `cast` on 26 Nov
      2026 at 10:49 UTC (block 144966501), and the same at 11:30 UTC (block 144971990):
      `memberCount()` 4, `totalCheckIns()` 3 of `checkInGoal()` 12, `launched()` false. The four
      members are three script wallets that joined at opening and a fourth member wallet,
      `0xd163f7f0a01dd8b708b8fdf0566ee750e7dae6ea`, that joined at 05:43 UTC. The 3 check-ins, all
      for 26 Nov (UTC day 20783): two of the script wallets 1 each, the fourth member 1; the third
      script wallet 0. A scripted check-in is due 27 Nov 00:02 UTC (07:02 in Bangkok), so the bar
      should read 4 of 12 before the judges add theirs; read it again before the talk (on 26 Nov at
      12:21 UTC it still read 4 members and 3 of 12). The join sheet asks for a second press,
      "Join anyway", once what is left of the goal is no more than the member count: with 4
      check-ins that is from 8 members on, so judges who join later may see it. Say so before they
      join; it is the honest warning, not an error. It is the featured round, first on Home. Its
      link: https://dokind.github.io/kickoff-bnb-hack/#/r/0xcf7957dc48e5c16732331d27e2c2a1b2a9fa5876
- [ ] **The faucet has gas, and room under its cap.** The faucet has its own wallet
      (`0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8`, `FAUCET_PRIVATE_KEY`), funded with 0.5 test
      BNB on 26 Nov; each new wallet gets `FAUCET_DRIP_BNB`, 0.012 test BNB for the event. Wallets
      left = (faucet balance − 0.05 reserve) / 0.012. On 26 Nov 2026 at 10:49 UTC the balance read
      0.427874 test BNB (the same at 11:30 UTC), so **about 31 wallets** (an upper bound: each
      transfer's gas also comes out of the balance). The faucet also stops for good after 200
      wallets in all (`GLOBAL_CAP`, `verifier/src/faucet.ts:14`), whatever its balance. Read it
      again:

      cast balance 0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8 --ether \
        --rpc-url https://bsc-testnet-rpc.publicnode.com

  A server with the `GET /api/faucet` route answers `walletsLeft` and `capLeft` directly
  (`scripts/preflight.sh` uses it when it is there). **Top it up** if fewer than about 40 wallets
  are left: the operator sends test BNB to the faucet wallet from the deployer (0.012 test BNB per
  extra wallet plus a little for gas), then runs the check again. A room on one wifi shares one
  network address: the event runs with `FAUCET_PER_IP_PER_HOUR=100`.
- [ ] **A recorded run is ready** in case the network fails.

## Season 1 runbook

Season 1: Show Up 30 is the upcoming flagship, not the stage demo: squads of 10, deposit 100 test
USD, 0% of the deposits to the shop, goal 240, check-ins Tue 1 Dec to Wed 30 Dec 2026, deadline
Thu 31 Dec 23:59:59 UTC (`1798761599`). Every step here that sends a transaction is for the
operator, from the operator's machine.

- [x] **Create Squad A.** Done on 26 Nov 2026 at 13:13 UTC: Launcher
      [`0xA60e2f022D891Dd394415A594c9e33614c019153`](https://testnet.bscscan.com/address/0xA60e2f022D891Dd394415A594c9e33614c019153),
      sponsored with 1,500 test USD, 0 members, 0 of 240, not featured; every transaction is in
      [PROOF.md](PROOF.md), "Season 1 Squad A". In the app:
      [Join Squad A · starts Tue 1 Dec](https://dokind.github.io/kickoff-bnb-hack/#/r/0xa60e2f022d891dd394415a594c9e33614c019153).
      How it was done, for the next squad (sends 4 transactions from the deployer key in
      `contracts/.env`; the deployer needs about 0.0115 test BNB, and the script checks before it sends). The create-only
      mode opens the round and sponsors its shop with 1,500 test USD, and does not feature it, join
      it or check in. The command, as in [`scripts/README.md`](scripts/README.md), section 2:

      cd verifier && CREATE_ONLY=true ROUND_NAME="Season 1 Squad A" DEPOSIT_USD=100 LIQUIDITY_BPS=0 \
        CHECKIN_GOAL=240 DEADLINE_AT=2026-12-31T23:59:59Z SPONSOR_USD=1500 \
        ATTESTER_ADDRESS=0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7 \
        STATE_FILE=../scripts/season1-a-run.json npx tsx ../scripts/run-round.ts

  Optional: add `VERIFIER_URL=https://<host>/api` and the script first checks, with a read-only
  `GET /health`, that the live server signs as `ATTESTER_ADDRESS`. Without it the server is not
  contacted at all.

  Never run `scripts/run-round.ts` without `CREATE_ONLY=true` against the hosted server before
  judging is over: its full run makes the new round the featured one. PROOF.md, "Season 1 Squad A",
  was filled from `scripts/season1-a-run.json`, and the docs carry the Squad A link.
- [x] **Turn the server's Season rule on.** Done: the hosted server runs with the rule on for Squad A
      (read 26 Nov 2026, 13:25 UTC). The settings: `SEASON_NAME="Season 1"`,
      `SEASON_LAUNCHERS=<squadA>`, `SEASON_START=2026-12-01`, `SEASON_END=2026-12-30`,
      `SEASON_JOIN_UNTIL=2026-12-07` and `SEASON_SQUAD_SIZE=10`, restart, and check in once on the
      demo round. Ship the server with these empty first, and set them only after Squad A exists.
- [x] **The `.season` check.** Squad A must carry the Season; every other round must not (passed on
      26 Nov 2026 at 13:25 UTC; repeat it before the talk, as above):

      curl -s https://<host>/api/rounds/0xa60e2f022d891dd394415a594c9e33614c019153 | jq .season
      curl -s https://<host>/api/rounds/0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876 | jq .season

  Expect the first to name "Season 1" with check-ins from 2026-12-01 to 2026-12-30 (UTC days 20788
  to 20817), joining until 2026-12-07 and squads of 10; expect `null` for the second. A check-in on
  Squad A before 1 Dec must answer `409` with `season_not_started`.
- [ ] **Feature Squad A only after judging** (it then shows first on Home):

      curl -X POST https://<host>/api/admin/round \
        -H "Authorization: Bearer <admin token from verifier/.env>" -H "Content-Type: application/json" \
        -d '{"launcher":"<squadA>","name":"Season 1 Squad A"}'

- [ ] **Open the next squad when one fills.** Squads open one at a time, with the same command and
      a new name and state file ("Season 1 Squad B", `../scripts/season1-b-run.json`), and are
      added to `SEASON_LAUNCHERS`.
- [ ] **If Flap raises the floor,** top the sponsor money up: `sponsor()` stays open until the
      launch.
- [ ] **31 Dec, 12:00 UTC: launch duty.** If a squad's bar is full and nobody has launched, the
      operator presses Launch (any wallet can; in the app, or
      `cast send <squad> "launch()" --legacy --gas-price 1000000000 --gas-limit 7000000 --rpc-url https://bsc-testnet-rpc.publicnode.com --interactive`).
- [ ] **From 1 Jan 2027, 00:00 UTC (07:00 in Bangkok): refunds.** A squad that did not launch
      refunds everyone in full; each wallet presses Refund in the app, and the sponsor (we, on
      testnet) refunds its 1,500 the same way. Season 2 opens.

## The refund proof

`scripts/refund-proof.ts` shows the Fall-Short Refund on BSC testnet. It sends transactions from
the deployer key, needs no server and leaves the featured round alone. Its settings and how to run
it are in the header of the script; from `verifier/`:

    npx tsx ../scripts/refund-proof.ts

It opens a throwaway round (deposit 100 test USD, 30% to the shop, goal 1, a deadline about 10
minutes out) whose attester is the deployer, so the server's public list leaves it out. It joins,
sponsors 50, signs one check-in so the bar is full, and shows two refusals by dry run: `launch()`
(the shop would hold 80 test USD, under Flap's floor) and `refund()` before the deadline
(`RefundUnavailable`). After the deadline it refunds and checks +150 test USD, `isMember` false and
`refundable` 0, and that a second `refund()` reverts `NothingToRefund`. It writes
`scripts/refund-result.json` (git-ignored). It ran on 26 Nov 2026 from 13:11:59 to 13:22:08 UTC:
Launcher `0xCDA4Fd2CD2Ca192216C64A827a0627e9d5BD092d` (unlisted: its attester is the deployer),
refund [`0x207ed121…ca73b0`](https://testnet.bscscan.com/tx/0x207ed12134a2c3651ea670142b4cc1227feb14af33bf8d6e1bc6d42148ca73b0)
(+150 test USD: the 100 deposit and the 50 sponsored), all 9 checks passed. Every hash is in
[PROOF.md](PROOF.md), "Refund on testnet". Once a run has succeeded, the script sends nothing more
unless given `--again`.

**Refund without our app,** for any member after a deadline with no launch:

    cast send <launcher> "refund()" --legacy --gas-price 1000000000 --gas-limit 150000 \
      --rpc-url https://bsc-testnet-rpc.publicnode.com --interactive

`--interactive` asks for the wallet's key, so it stays out of the shell history. It pays only the
wallet that sends it.
