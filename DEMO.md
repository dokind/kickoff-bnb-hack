# Cypher Run demo

Six steps, in the app as it is today, on BSC testnet with test USD. Nothing to install: the web app
is at **https://dokind.github.io/kickoff-bnb-hack/** and makes a wallet in the browser. Everything
here is testnet; nothing has real value.

The scripted run of a whole round (open, join, check in, launch, trade, claim) is described under
"Demo" in [README.md](README.md). The walk-through of the earlier design (running club seasons) is
kept in [docs/archive/DEMO.md](docs/archive/DEMO.md).

## The six steps

| # | Do | What it shows |
|---|---|---|
| 1 | **Open the site or scan the QR.** https://dokind.github.io/kickoff-bnb-hack/, or a round's invite link `https://dokind.github.io/kickoff-bnb-hack/#/r/<launcher>`. | The app reads the server's current host from OriginRegistry `0xb9aD45Dc177C801f10670F2aac03B467f1C367d2` on chain before its first call, so the site works whatever tunnel host the server has today. An invite link opens with that round selected. |
| 2 | **Get started.** | A wallet is made on the device and its key stays in the browser; Wallet, "Back up your key", is the only way to open it on another device. The server's faucet sends it 0.03 test BNB for network fees when it first needs some ("Preparing your wallet"). In the browser "Get started" goes straight to Home; the check-in sheet says plainly that a browser cannot read health data, so a check-in here is typed in. |
| 3 | **Join a round.** On Home, swipe to the round and press "Join *name* · *deposit*". | The join sheet shows the deposit split: "To the prize" and "To the token pool" (70% and 30% by default), then "If it launches", "Last day to launch", and over the button what can be lost, one line each, starting with "Round never launches: your *deposit* comes back." "Get test dollars" mints the deposit in Flap's free test USD; "Pay deposit" approves and pays it into the round's Launcher. "You're in." When the bar is one check-in from full, the sheet warns that the round can launch before your first check-in, which would leave you nothing, and the payment takes a second press, "Join anyway". |
| 4 | **Check in.** "Check in · *name*", then type today's steps. | The server checks the report and signs the day; the member's own wallet sends `checkIn(day, signature)`. The bar on the card moves by one. On the web the steps are self-reported, a testnet-only switch on the server (`ALLOW_SELF_REPORTED=true`); the iPhone build reads Apple Health steps instead. One check-in per wallet per UTC day: a new day starts at 07:00 in Bangkok. |
| 5 | **Launch when the bar is full.** "Launch *name*". | Any wallet can press it once the bar is full, members or not. If the token pool is short of the 1,500 test USD Flap asks for today, the button is off and "Sponsor the token pool" is offered instead. The launch is one transaction through Flap Pool Launch: the token, its pool with the LP burned, and the round's vault with half the supply and the prize. Home then says "Launched. The token is live." and the result screen, "Launched on Flap", links to BscScan testnet and to Flap. |
| 6 | **Claim.** "Claim · *name*". | The result screen shows your days and your part: your days over all check-ins, of the reserved tokens and of the test USD in the vault. Claim again later for the trading tax that arrived since. A wallet with no check-in sees "You have no check-ins in this round": it gets nothing. |

Two more things a judge may try:

- **Start a round** (the "+" button): name, deposit, check-ins needed, how long it runs (1 to 30
  days in the app), token pool share and listed or unlisted. "The deal" box spells out the terms
  before "Start round". It costs about 0.007 test BNB in fees.
- **Invite** (on a round card): the link, a copy button and a QR code for that round.

## Before going on stage

- [ ] **The factory is still enabled on the Flap Portal at 1x.** Anyone can call Flap's testnet
      helper for any factory, so read it back:

      cast call 0x000042108465206185A077Edc3F3fd2b49060000 "launcherFactoryMultiplier(address)(bool,uint256)" \
        0x2A872200B83dD025977d785cDE05356d23eA4153 --rpc-url https://bsc-testnet-rpc.publicnode.com

      Expect `true` and `10000`.
- [ ] **The registry names the server's current host.**

      cast call 0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 "origin()(string)" \
        --rpc-url https://bsc-testnet-rpc.publicnode.com

      It must not be empty, and `https://<that host>/api/health` must answer `"ok": true` with
      the attester `0x2f2ab3da0b824f9ca3edd2580443ca0b271efdd7` (in lower case there). If the
      tunnel restarted, the server writes the new host on its next check (every 60 seconds by
      default, `ORIGIN_CHECK_SECONDS`).
- [ ] **The site opens on mobile data**, not on the venue wifi: https://dokind.github.io/kickoff-bnb-hack/
      on a phone with wifi off, through Get started to Home.
- [ ] **A fresh round with room for the judges.** Start one shortly before the talk, with a goal
      the people in the room can fill in one sitting (each wallet checks in once per UTC day) and a
      deadline days away. Do not send judges to a round that is about to close or one check-in from
      full: "Demo Day" stands at 4 of 5 and its deadline is 28 Nov 2026 16:34 UTC. Plan the token
      pool: 30% of the deposits plus any sponsor money must reach 1,500 test USD before Launch
      works (five members at a 1,000 test USD deposit, or fewer and a sponsor through "Sponsor the
      token pool").
      Done for Bangkok: "Bangkok Demo Run"
      [`0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876`](https://testnet.bscscan.com/address/0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876),
      opened 26 Nov 2026 with `scripts/run-round.ts` (deposit 100 test USD, goal 12 check-ins,
      deadline 30 Nov 2026 00:34 UTC). The pool was sponsored up to 1,500 test USD at once, so
      only check-ins decide the launch. Three script wallets joined (Ana, Ben, Chai); Ana and Ben
      checked in on 26 Nov UTC, and Ana again after 27 Nov 00:00 UTC, so the split reads 2 : 1 : 0
      before the judges add theirs. It is the featured round, first on Home.
- [ ] **The faucet has gas.** The faucet has its own wallet
      (`0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8`, `FAUCET_PRIVATE_KEY`), funded with 0.5 test
      BNB on 26 Nov; each new wallet gets `FAUCET_DRIP_BNB` (0.012 for the event, so about 40
      wallets). A room on one wifi shares one network address: the event runs with
      `FAUCET_PER_IP_PER_HOUR=100`.
- [ ] **A recorded run is ready** in case the network fails.
