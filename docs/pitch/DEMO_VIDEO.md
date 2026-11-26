# Cypher Run demo video: production brief

> **Status, 26 November 2026: the video is made.** The cut is 85 seconds
> (`pitch-video/cypher-run-demo-1920x1080.mp4`, 85.1 s by `ffprobe`, with a 1080x1920 copy; the MP4
> files are git-ignored and stay on the owner's machine, the captions are in
> `pitch-video/cypher-run-demo.srt`). It is voiced in the owner's own voice: an AI clone of the
> owner's voice, line by line from
> [`pitch-video/READ-THIS-VOICEOVER.md`](../../pitch-video/READ-THIS-VOICEOVER.md). It follows that
> 11-line script, not the 2:00 scene plan below; this brief is kept as the record of how the video
> was planned.
>
> **Being re-voiced: lines 1, 7, 10 and 11.** Their words were rewritten to the final positioning
> (split by days, not paid by others; we never hold the money) and are being recorded again in the
> same voice clone. The new words are in `pitch-video/voiceover-lines.json`, which the voice tools
> read, and in `pitch-video/voiceover.txt`. **Do not upload the 85.1 s cut or its captions as they
> are:** its voice (`pitch-video/vo/s1, s7, s10, s11.aiff`) still says the old lines, and three of
> its picture cards in `pitch-video/compositor.html` (s1, s10, s11) still show the old words.
> `pitch-video/cypher-run-demo.srt` already carries the new words, but at the old lines' times,
> worked out by `pitch-video/srt.mjs` from the current voice files. After the four lines are
> re-voiced: put the new card text in `compositor.html`, render again with `render.mjs` (not
> `dub-video.mjs`, which keeps the old picture), run `srt.mjs` again from the new voice files (it
> reads `vo/lines.txt`, a copy of `voiceover.txt`), and recheck the chapter times in section 11.
>
> **The upload text in section 11 is the final one**, in the final positioning: the pot is safe, the
> launch is the bonus. Where the plan in sections 1 to 10 words something differently, the
> [README](../../README.md) wins: "every deposit comes back" always means "if the round has not
> launched by the deadline".

This brief is for a Claude Code session on the owner's Windows or Mac PC. Use it to make the demo
video for the HackQuest submission of **Cypher Run** at BNB Hack Bangkok. You have not seen this
project before. Everything you need is in this file. You do not need to clone the repo, and you
must not change it.

- **Deliverable:** one MP4 file, 1920x1080, 30 fps, H.264 and AAC, **2:00 long (hard cap 2:30)**,
  with burned-in captions. Upload it as an unlisted YouTube video (or a Loom) and give the link
  to the owner.
- **Deadline:** the submission closes **Friday 27 Nov 2026, 09:00 Bangkok time (02:00 UTC)**.
  Finish the upload by 08:00 Bangkok time so there is an hour to spare.
- **Working folder:** `~/cypher-run-video` on macOS or `%USERPROFILE%\cypher-run-video` on
  Windows, with the subfolders `raw`, `clips`, `frames`, `scenes`, `audio` and `out`.

## 0. Safety rules (read these before anything else)

1. **Testnet only.** The app runs on BNB Smart Chain testnet (chain 97) with test BNB and Flap's
   free test USD. Never connect a real wallet. Never send real money. Never buy anything.
2. **Never show, copy or open a private key.** In the app, never press Wallet → "Back up your key".
   Never open browser storage or DevTools panels that could show keys, on camera or off.
3. **Do not touch the project.** Do not edit the repo at https://github.com/dokind/kickoff-bnb-hack,
   its server or its contracts. Do not call any admin route. If something in the app is broken,
   stop and tell the owner. Do not try to fix it yourself.
4. **Nothing private on screen:** no email or chat notifications, no bookmarks bar, no browser
   profile avatar, no DevTools Network tab, no server address or IP, and no file paths that show
   the owner's user name. Turn on Do Not Disturb (macOS Focus, or Windows Focus Assist) before
   you record.
5. **Wording.** Write "test USD" or "test dollars", never just "dollars" or "$". Do not promise
   returns. Do not call it an investment. Do not use token tickers. Do not make up numbers or
   quotes. Use only the numbers in section 1.
6. **One check-in per wallet per UTC day.** The check-in scene can be recorded once per wallet per
   day (a new UTC day starts at 07:00 Bangkok time). Every fresh browser profile creates a new
   wallet, and that wallet joins the judges' round as a member. **Use no more than two wallets in
   total.**

## 1. The product, in facts you may use (all verified in the repo)

**One line:** Cypher Run turns showing up into a community, and a community into a launch. You pay
a deposit and check in each day you move. Everyone's check-ins fill one bar. When the bar is full,
anyone can launch the round's token through Flap Pool Launch. The prize, half the token supply and
80% of the trading tax are shared by days shown up. If the round has not launched by the deadline,
every deposit comes back. The pot is safe; the launch is the bonus.

**How a round works**

- A round is one contract (our Launcher). It is created through the Flap Portal by our own
  Launcher Factory, and that factory is enabled on Flap's testnet Portal.
- Every member pays the same deposit once (in test USD).
- Check-in: the phone app reads today's steps from Apple Health or Health Connect. Our server
  signs that day, and the member's own wallet records it on chain, once per UTC day. **On the
  web, steps are typed in.** That is a testnet-only switch.
- The bar: all check-ins count toward one goal. Once the bar is full and the deadline has not
  passed, anyone can call `launch()`. Not us, not an admin.
- At launch, one transaction through Flap creates the token, seeds its PancakeSwap pool with 30%
  of the deposits (by default) plus any sponsor money and half the supply, and burns the LP. The
  other 70% of the deposits (the prize), the other half of the supply and 80% of the trading tax
  (3% buy, 5% sell) go to the round's vault. The other 20% of the tax is burned.
- Claim: a member with `d` days gets `d / all check-ins` of the vault. **A member with 0 days gets
  nothing.** Each day counts the same, so a beginner's day is worth as much as a marathoner's.
- Not launched by the deadline (the bar not full, the pool under Flap's floor, or nobody pressed
  Launch): every member gets the full deposit back, and every sponsor gets their money back. If it
  launched, there is no refund: the vault is split by days.
- Sponsors (brands, clubs, races) can add money to the token pool. They get no share.

**Proof on BSC testnet: the round "Bangkok Showup" (25 Nov 2026), complete**

| Member | Paid | Days | Test USD received | Tokens received |
|---|---|---|---|---|
| Ana | 500 test USD | 2 | 822.32 | 333,333 |
| Ben | 500 test USD | 1 | 411.16 | 166,666 |
| Chai | 500 test USD | 0 | 0 | 0 |

- The vault received a 1,050 test USD prize plus 183.48 test USD of trading tax, and it paid out
  all 1,233.48. There were 47 transactions in total, and all of them succeeded.
- A member wallet sent the launch, not our server.
- **Be honest about this round:** it was a scripted test round. Ana, Ben and Chai are throwaway
  wallets run by the owner's script, and their steps were typed in. Never call them "three
  people". Call them "three members" or "three member wallets".

**Links and addresses (all public)**

| What | Link |
|---|---|
| Web app (no install) | https://dokind.github.io/kickoff-bnb-hack/ |
| Bangkok Showup in the app | https://dokind.github.io/kickoff-bnb-hack/#/r/0xe1c165c295ed8bc0aba2a81c2a524564689bceab |
| Its token on Flap's testnet site | https://abc.flap.sh/bnb-testnet/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777 |
| The launch transaction (BscScan testnet) | https://testnet.bscscan.com/tx/0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896 |
| The round's vault (BscScan testnet) | https://testnet.bscscan.com/address/0x93873812C48C9f5fCD3594fD651Ce9Ce96c75728 |
| Factory enabled on the Flap Portal (tx) | https://testnet.bscscan.com/tx/0x2a7d71063496b439a12248f90b133ce5230d7c9581a25b6af84ede2ec3d9ad45 |
| Our Launcher Factory | https://testnet.bscscan.com/address/0x2A872200B83dD025977d785cDE05356d23eA4153 |
| Android APK | https://github.com/dokind/kickoff-bnb-hack/releases/download/android-latest/cypher-run.apk |
| iPhone (TestFlight, **only if Apple has approved it**) | https://testflight.apple.com/join/bp4WaEu5 |
| Repo (open source) | https://github.com/dokind/kickoff-bnb-hack |
| Full proof, every transaction | https://github.com/dokind/kickoff-bnb-hack/blob/main/PROOF.md |
| Whitepaper | https://github.com/dokind/kickoff-bnb-hack/blob/main/docs/WHITEPAPER.md |

**Judges' round:** "Bangkok Demo Run", Launcher `0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876`.
The deposit is 100 test USD and the goal is 12 check-ins. The pool is already sponsored to Flap's
1,500 test USD floor. Three script wallets and one more member wallet are in it. It is the
featured round, the first card on Home.

**Tests:** 75 contract tests (80 including 5 fork tests against the live Portal) and 203 server
tests, as of 26 November 2026. Do not put an app test count on screen.

**Honest limits** (the video states the first one, and none of them may be hidden):

- Our server's key signs check-ins. That key cannot move funds, cannot launch early, cannot block a
  launch and cannot pay anyone who did not deposit.
- Steps typed in on the web are a testnet switch.
- A late joiner with 0 days gets nothing. The app warns them and asks for a second tap.
- The reserved tokens can be traded from the moment of launch.
- The contracts take no fee yet.

**App screens you will see:** the welcome screen ("RUN THE STAKES." and "Put in a test deposit.
Show up each day. Split the prize with everyone who did."); Home, with a slider of round cards, a TESTNET pill
and THE PRIZE ("If it launched now, each day shown up would be worth about X test USD", plus
members with friendly names such as "Gentle Giraffe"); the one-button join ("Join with test
dollars · 100 test USD", with a progress loader); Your round (WHAT YOU GET, YOUR MONEY, HOW IT ENDS
and YOUR WEEK); the check-in sheet; and the result screen after a launch ("Launched on Flap",
"THE COIN IS LIVE.", Claim).

## 2. The video at a glance

| # | Time | Length | Picture | Big headline (burned in) |
|---|---|---|---|---|
| 1 | 0:00–0:10 | 10 s | Phone: welcome screen | YOUR GYM GETS PAID WHEN YOU QUIT. |
| 2 | 0:10–0:30 | 20 s | Phone: Get started → Home → Join → Your round | PUT IN A DEPOSIT. |
| 3 | 0:30–0:48 | 18 s | Phone: check in, the bar moves, HOW IT ENDS | EVERY CHECK-IN FILLS ONE BAR. |
| 4a | 0:48–1:04 | 16 s | Desktop browser: Flap token page, launch tx, vault | THE REAL LAUNCH. ON CHAIN. |
| 4b | 1:04–1:12 | 8 s | Phone: Bangkok Showup result + payout numbers | IT ALREADY HAPPENED. |
| 5 | 1:12–1:35 | 23 s | Card: comparison | OTHERS SPLIT A POT. HERE, SHOWING UP ADDS A LAUNCH. |
| 6 | 1:35–1:50 | 15 s | Card: architecture (deck slide 6 or our card) | CONTRACTS HOLD THE MONEY. NOT US. |
| 7 | 1:50–2:00 | 10 s | Card: links | TRY IT IN 60 SECONDS. |

Layout of every frame (1920x1080, background `#0A0E11`): the phone recording sits on the left,
scaled to 820 px tall at x=200, y=40. The headline is on the right. A pill reading "TESTNET · NO
REAL MONEY" is in the top-right corner. **The bottom 200 px stay empty for the subtitles.**
Section 5 gives the HTML that draws these frames.

## 3. Scene by scene: picture, voiceover, headline

The voiceover is written in Alex Hormozi's style: short sentences, numbers said plainly, a pause
before each number, a downward ending on every sentence, and no filler words. Read it word for
word at about 140 to 150 words per minute. There are 265 words in total.

### Scene 1: the hook (0:00–0:10)

- **Picture:** the welcome screen, still ("RUN THE STAKES."). Take it from the first seconds of
  recording R1.
- **Voiceover:** "Your gym gets paid when you quit. Cypher Run splits the pot by days shown up. On
  testnet, it already did."
- **Headline:** YOUR GYM GETS PAID WHEN YOU QUIT. Sub-line: "Cypher Run splits the pot by days
  shown up." (No statistic about quitting: there is no source for one, and the rules forbid
  made-up numbers.)

### Scene 2: join (0:10–0:30)

- **Picture:** press Get started → Home (the Bangkok Demo Run card, the TESTNET pill, then scroll a
  little to THE PRIZE) → press "Join with test dollars · 100 test USD" → the loader (cut most of
  the wait) → Your round: WHAT YOU GET, then scroll through YOUR MONEY and HOW IT ENDS.
- **Voiceover:** "Here's the deal. You put in a deposit. Today, that's test dollars on BNB testnet.
  One tap, and you're in a round with everyone else. The app shows you, in plain words, what you
  put in, what you can get, and how it ends."
- **Headline:** PUT IN A DEPOSIT. Sub-line: "One tap. 100 test USD. The app spells out how it
  ends."

### Scene 3: check in (0:30–0:48)

- **Picture:** Home → "Check in · Bangkok Demo Run" → the check-in sheet → type today's steps →
  confirm → the bar on the card moves up by one. End on HOW IT ENDS (three outcomes) if there is
  time.
- **Voiceover:** "Each day you move, check in once. On a phone, steps come from Apple Health or
  Health Connect. Every check-in fills one shared bar. Full by the deadline: anyone launches the
  token. Miss it: every deposit comes back."
- **Headline:** EVERY CHECK-IN FILLS ONE BAR. Sub-lines: "Full by the deadline → anyone launches
  the token on Flap." / "Not launched by the deadline → every deposit comes back." Small print: "Web demo: steps typed
  in (testnet only). The phone apps read Apple Health / Health Connect."

### Scene 4a: the real launch (0:48–1:04)

- **Picture:** desktop browser footage, cut into three parts. (1) The Bangkok Showup token on
  Flap's testnet site (its trades and holders). (2) The launch transaction on BscScan testnet:
  status Success, the call to the Launcher, and the token transfers. (3) The vault address and its
  token transfers.
- **Voiceover:** "This isn't a mockup. Round one ran end to end: three member wallets, 500 test
  dollars each. A member, not our server, pressed launch. One call to Flap Pool Launch: token, pool,
  LP burned, vault funded."
- **Headline (small label above the footage):** THE REAL LAUNCH. ON CHAIN. Label: "Flap testnet
  site + BscScan testnet · 47 transactions, all public".

### Scene 4b: the payout (1:04–1:12)

- **Picture:** the phone on the Bangkok Showup result screen ("Launched on Flap", "THE TOKEN IS
  LIVE.", "filled the bar with 3 check-ins"). The payout table is on the right.
- **Voiceover:** "The vault paid the prize and the trading tax by days. Two days: 822. One day:
  411. Zero days: zero."
- **Headline:** IT ALREADY HAPPENED. Table: "2 days → 822.32 test USD + 333,333 tokens" / "1 day →
  411.16 test USD + 166,666 tokens" / "0 days → 0". Small print: "Each paid 500 test USD. Test
  round: three member wallets run by our script, steps typed in."

### Scene 5: why it is different (1:12–1:35)

- **Picture:** the comparison card, full frame. The Cypher Run row is lit in volt yellow
  (`#D4FF3A`).
- **Voiceover:** "Stake apps: a company holds the money, and the best you win is what others lost.
  Here a contract holds it. Showing up together also launches a token on Flap: half its supply and
  eighty percent of its tax go to those who showed up. Fall short together? Every deposit comes
  back."
- **Headline:** OTHERS SPLIT A POT. HERE, SHOWING UP ADDS A LAUNCH.
- **Do not say or show** that other apps' losers pay the winners as if that does not happen here.
  In Cypher Run a member with 0 days gets nothing and their deposit goes to those who showed up. The
  card says so in its note line. What only Cypher Run adds: a launch on top, every deposit back if
  the group falls short, and a contract holding the money.

### Scene 6: how it is built (1:35–1:50)

- **Picture:** the architecture slide (slide 6) of the owner's pitch deck, if the owner gives you a
  PNG of it. Otherwise use the `s6` card from section 5. Hold still, or push in slowly.
- **Voiceover:** "Our Launcher Factory is enabled on Flap's Portal. Contracts hold the money. Not
  us. You trust one thing: our server decides if a day counts. It can't move money, launch early,
  or block a launch."
- **Headline:** CONTRACTS HOLD THE MONEY. NOT US.

### Scene 7: try it (1:50–2:00)

- **Picture:** the links card.
- **Voiceover:** "Try it in sixty seconds. Open the link. No install, no real money. Bring your
  crew. Show up. Launch together."
- **Headline:** TRY IT IN 60 SECONDS.

## 4. Capturing the footage

### 4.1 Tools (all free, on Windows or macOS)

- **Google Chrome**, for the app and the proof pages.
- **OBS Studio** (https://obsproject.com), for recording. Fallbacks: Xbox Game Bar (Win+Alt+R) on
  Windows, or Cmd+Shift+5 → "Record Selected Portion" on macOS.
- **ffmpeg 6 or newer**, for editing. Install with `winget install Gyan.FFmpeg` on Windows or
  `brew install ffmpeg` on macOS. Check with `ffmpeg -version`.
- **Node.js 20 or newer and Playwright**, only to render the title cards and the caption images to
  PNG (sections 5 and 9). Do
  not use Playwright to click through the app. The app is Flutter on a canvas, so scripted clicks
  are unreliable. Record the app by hand.
- **Audacity** (free), to record the voiceover. Any voice memo app also works.

### 4.2 Set up a fresh phone-sized Chrome

1. Open Chrome with a new, empty profile, so the app makes a new wallet:
   - Windows (PowerShell):
     `& "C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="$env:TEMP\cypher-demo" --no-first-run --no-default-browser-check "https://dokind.github.io/kickoff-bnb-hack/"`
   - macOS:
     `open -na "Google Chrome" --args --user-data-dir="/tmp/cypher-demo" --no-first-run --no-default-browser-check "https://dokind.github.io/kickoff-bnb-hack/"`
2. Open DevTools (F12, or Cmd+Opt+I). Set the dock side to **"Undock into separate window"**, so
   the DevTools panels stay out of the recorded window. Turn on device mode (Ctrl+Shift+M or
   Cmd+Shift+M). Choose Dimensions: Responsive, **390 x 844**, zoom 100%. Under "⋮", choose "Add
   device pixel ratio" and set **DPR 3**. Reload the page.
3. In OBS: set Settings → Video → Base and Output to **1920x1080**, 30 fps, and set Output →
   Recording Format to MKV, encoder x264 or hardware, CRF/CQ about 18. Add a Window Capture of
   Chrome. Alt+drag (Option+drag on macOS) the edges to crop it to the 390x844 viewport only. Then
   right-click → "Resize output (Source size)" so the recording is just the phone. **Check that the
   address bar and tabs are cropped out.** After a take, use File → Remux Recordings to get an MP4.
4. Before every take, turn on Do Not Disturb and close any other windows that could pop up.

### 4.3 Takes

**Do not rehearse the join.** Every join adds a member to the judges' round. Rehearse by looking at
Home and opening sheets, but do not press the pay button until the real take.

**R1: welcome, join, check in (scenes 1, 2 and 3), one continuous take, fresh profile.**

1. Start recording on the welcome screen. **Hold still for 12 seconds** (this is scene 1).
2. Press **Get started**. Home opens, and you may see "Preparing your wallet" while the server's
   faucet sends test BNB for fees. Wait until it is done.
3. On Home, stay on the first card, **Bangkok Demo Run** (swipe to it if it is not first). Hold for
   3 seconds. Scroll slowly down to THE PRIZE, hold for 3 seconds, and scroll back up.
4. Press **"Join with test dollars · 100 test USD"**. Let the loader run until you see "You're in"
   or Your round. If the app warns that the round may launch before your first check-in and asks
   "Join anyway", **stop and ask the owner**: it means the bar is nearly full.
5. On Your round, hold WHAT YOU GET for 3 seconds. Scroll slowly through YOUR MONEY and HOW IT ENDS,
   holding about 2 seconds on each.
6. Go back to Home. Press **"Check in · Bangkok Demo Run"**. In the sheet, type the owner's real
   step count for today (ask them, from their phone). If they cannot tell you, type any number of at
   least 1,000. The on-screen caption says the steps were typed in. Confirm, and wait for the bar on
   the card to move up by one. Hold for 3 seconds.
7. Stop recording. Remux to `raw/r1.mp4`.

If the check-in fails, **do not start a new profile at once.** Read the error and tell the owner.
The wallet can try again on the next UTC day (07:00 Bangkok time). A second wallet is allowed only
once, and only if the owner agrees.

**R2: the Bangkok Showup result (scene 4b), same profile.**

1. Open https://dokind.github.io/kickoff-bnb-hack/#/r/0xe1c165c295ed8bc0aba2a81c2a524564689bceab.
   Home opens with Bangkok Showup selected and shows that it has launched.
2. Start recording. If THE PRIZE on this card lists the three members with their amounts, scroll to
   it and hold for 3 seconds. Then press **"See the result · Bangkok Showup"**.
3. The result screen shows "Launched on Flap", "THE COIN IS LIVE." and "Bangkok Showup filled the
   bar with 3 check-ins…". Hold for 4 seconds, then scroll slowly to "Your days". This wallet has 0
   days, so the screen will say it has no check-ins in this round, which is fine. **Do not press
   Claim.**
4. Stop recording. Save it as `raw/r2.mp4`.

**R3: the on-chain proof (scene 4a), desktop browser, a normal window at 1920x1080.**

Use a fresh Chrome profile as in 4.2, but without device mode. Set the page zoom to 150%. On each
cookie banner, choose the least tracking ("Reject" or "Necessary only"). Record the window in OBS
(a second scene, cropped to the page area without the tab bar), and hold each view for 6 to 8
seconds:

1. https://abc.flap.sh/bnb-testnet/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777: the token, its
   trades and holders.
2. https://testnet.bscscan.com/tx/0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896:
   Status Success, "Interacted With" the Launcher, and the token transfers (scroll slowly).
3. https://testnet.bscscan.com/address/0x93873812C48C9f5fCD3594fD651Ce9Ce96c75728: the vault. Open
   the token transfers tab so the payouts are visible.

Save it as `raw/r3.mp4`.

**Optional R4: an Android phone screen recording** (the APK reading Health Connect), only if the
owner has the APK installed and wants to show it. It can replace 3 seconds of scene 3. Never show
any phone notifications.

### 4.4 Cut the raw takes into clips

Watch each raw file and write down the in and out times. Re-encode with these commands so cuts land
on exact frames (swap in your own times):

```sh
# Scene 1: welcome screen, 10 s
ffmpeg -y -ss 00:00:01.0 -to 00:00:11.0 -i raw/r1.mp4 -an -vf fps=30 -c:v libx264 -crf 18 -preset medium clips/s1.mp4

# Scene 2: Get started -> Home -> Join -> Your round. Several pieces with the waiting cut out,
# joined together (add or remove inputs as needed); about 20 s in total
ffmpeg -y -ss 00:00:12.0 -to 00:00:20.0 -i raw/r1.mp4 -ss 00:00:41.0 -to 00:00:47.0 -i raw/r1.mp4 -ss 00:01:05.0 -to 00:01:12.0 -i raw/r1.mp4 \
  -filter_complex "[0:v]fps=30,setsar=1[a];[1:v]fps=30,setsar=1[b];[2:v]fps=30,setsar=1[c];[a][b][c]concat=n=3:v=1:a=0[v]" \
  -map "[v]" -c:v libx264 -crf 18 -preset medium clips/s2.mp4

# Scene 3: check in, about 18 s (same pattern; cut the wait for the transaction)
ffmpeg -y -ss 00:01:20.0 -to 00:01:30.0 -i raw/r1.mp4 -ss 00:01:44.0 -to 00:01:52.0 -i raw/r1.mp4 \
  -filter_complex "[0:v]fps=30,setsar=1[a];[1:v]fps=30,setsar=1[b];[a][b]concat=n=2:v=1:a=0[v]" \
  -map "[v]" -c:v libx264 -crf 18 -preset medium clips/s3.mp4

# Scene 4a: three proof views, about 16 s
ffmpeg -y -ss 00:00:02.0 -to 00:00:07.5 -i raw/r3.mp4 -ss 00:00:15.0 -to 00:00:21.0 -i raw/r3.mp4 -ss 00:00:30.0 -to 00:00:35.0 -i raw/r3.mp4 \
  -filter_complex "[0:v]fps=30,setsar=1[a];[1:v]fps=30,setsar=1[b];[2:v]fps=30,setsar=1[c];[a][b][c]concat=n=3:v=1:a=0[v]" \
  -map "[v]" -c:v libx264 -crf 18 -preset medium clips/s4a.mp4

# Scene 4b: result screen, 8 s
ffmpeg -y -ss 00:00:03.0 -to 00:00:11.0 -i raw/r2.mp4 -an -vf fps=30 -c:v libx264 -crf 18 -preset medium clips/s4b.mp4
```

On Windows PowerShell, replace the trailing `\` with a backtick, or put the command on one line.

If you used Game Bar, the recording is the whole Chrome window. Crop it to the phone viewport first
(measure `w:h:x:y` on a still frame), for example:
`ffmpeg -i raw/r1_full.mp4 -vf "crop=1170:2532:400:180" -c:v libx264 -crf 18 raw/r1.mp4`.

## 5. Title frames and cards (HTML → PNG)

Save this as `cards.html` in the working folder. Before rendering, set `TESTFLIGHT_APPROVED`:
open https://testflight.apple.com/join/bp4WaEu5 first. If it says the beta is not accepting
testers, leave it `false`.

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Cypher Run frames</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Archivo+Black&family=Inter:wght@400;600;800&display=swap" rel="stylesheet">
<style>
:root{--ink:#0A0E11;--slate:#17222A;--steel:#24414A;--volt:#D4FF3A;--ok:#6CF2B0;--text:#fff;--t2:rgba(255,255,255,.66);--t3:rgba(255,255,255,.42);--line:rgba(255,255,255,.14)}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1920px;height:1080px;overflow:hidden;background:var(--ink);color:var(--text);font-family:Inter,Arial,sans-serif}
html.clear,html.clear body{background:transparent}
.pill{position:absolute;top:34px;right:48px;font:800 22px Inter,Arial;letter-spacing:.1em;color:var(--volt);border:2px solid var(--volt);border-radius:999px;padding:8px 20px}
.slot{position:absolute;left:190px;top:30px;width:400px;height:840px;border-radius:44px;border:2px solid var(--line);background:#000}
.panel{position:absolute;left:700px;top:120px;width:1140px}
.kicker{font:800 24px Inter,Arial;letter-spacing:.16em;color:var(--volt);text-transform:uppercase;margin-bottom:26px}
h1{font:400 100px/0.98 'Archivo Black','Arial Black',sans-serif;text-transform:uppercase;letter-spacing:-.01em}
.sub{margin-top:34px;font:400 38px/1.35 Inter,Arial;color:var(--t2)}
.sub b{color:var(--text);font-weight:800}
.small{margin-top:26px;font:400 26px/1.4 Inter,Arial;color:var(--t3)}
.pay{margin-top:36px;display:grid;grid-template-columns:200px 1fr;row-gap:18px;font:800 44px Inter,Arial;align-items:baseline}
.pay .d{color:var(--t2)} .pay .v{color:var(--volt)} .pay .z{color:var(--t3)}
.pay small{font:600 28px Inter,Arial;color:var(--t2);margin-left:14px}
.full{position:absolute;left:90px;right:90px;top:56px}
.full h1{font-size:84px}
table{width:100%;margin-top:24px;border-collapse:separate;border-spacing:0 9px;font:400 26px/1.3 Inter,Arial}
th{font:800 20px Inter,Arial;letter-spacing:.14em;text-transform:uppercase;color:var(--t3);text-align:left;padding:0 22px}
td{background:var(--slate);padding:13px 22px;color:var(--t2);vertical-align:top}
td:first-child{border-radius:14px 0 0 14px;color:var(--text);font-weight:800;width:430px}
td:last-child{border-radius:0 14px 14px 0}
td .ex{display:block;font:400 21px Inter,Arial;color:var(--t3);margin-top:4px}
tr.us td{background:var(--volt);color:#05080A;font-weight:600}
tr.us td:first-child{font:400 34px 'Archivo Black','Arial Black',sans-serif}
.note{margin-top:14px;font:600 26px Inter,Arial;color:var(--t2)}
.arch{display:grid;grid-template-columns:1fr 90px 1fr 90px 1.35fr;align-items:stretch;margin-top:40px}
.box{background:var(--slate);border:2px solid var(--steel);border-radius:20px;padding:26px}
.box h3{font:400 30px 'Archivo Black','Arial Black',sans-serif;margin-bottom:14px}
.box p{font:400 25px/1.4 Inter,Arial;color:var(--t2);margin-top:8px}
.box p b{color:var(--text)}
.box.chain{border-color:var(--volt)} .box.chain h3{color:var(--volt)}
.arrow{display:flex;align-items:center;justify-content:center;font:800 54px Inter,Arial;color:var(--volt)}
.strip{margin-top:30px;font:600 25px Inter,Arial;color:var(--t2)}
.links{margin-top:46px;display:grid;grid-template-columns:330px 1fr;row-gap:26px;font:400 40px Inter,Arial;align-items:baseline}
.links .k{font:800 26px Inter,Arial;letter-spacing:.14em;color:var(--t3);text-transform:uppercase}
.links .u{color:var(--text);font-weight:800}
.label{position:absolute;left:80px;top:40px;font:800 26px Inter,Arial;letter-spacing:.12em;color:var(--volt);text-transform:uppercase}
.label span{color:var(--t2);font-weight:600;letter-spacing:.02em;text-transform:none;margin-left:16px}
</style></head>
<body>
<div id="root"></div>
<script>
const TESTFLIGHT_APPROVED = false;   // true only if the TestFlight link accepts testers
const pill = '<div class="pill">TESTNET · NO REAL MONEY</div>';
const phone = (kicker, h, rest) => `<div class="slot"></div><div class="panel"><div class="kicker">${kicker}</div><h1>${h}</h1>${rest}</div>${pill}`;
const S = {
  s1: phone('01 · The hook', 'Your gym<br>gets paid<br>when you quit.',
    '<div class="sub">Cypher Run splits the pot by days shown up.</div>'),
  s2: phone('02 · Join', 'Put in<br>a deposit.',
    '<div class="sub"><b>One tap. 100 test USD.</b><br>The app spells out what you put in, what you can get, and how it ends.</div>'),
  s3: phone('03 · Show up', 'Every check-in<br>fills one bar.',
    '<div class="sub">Full by the deadline → <b>anyone launches the token on Flap.</b><br>Not launched by the deadline → <b>every deposit comes back.</b></div>' +
    '<div class="small">Web demo: steps typed in (testnet only). The phone apps read Apple Health / Health Connect.</div>'),
  s4a: `<div class="label">The real launch. On chain.<span>Flap testnet site + BscScan testnet · 47 transactions, all public</span></div>${pill}`,
  s4b: phone('04 · Bangkok Showup, BSC testnet', 'It already<br>happened.',
    '<div class="pay">' +
    '<div class="d">2 days</div><div class="v">822.32 test USD<small>+ 333,333 tokens</small></div>' +
    '<div class="d">1 day</div><div class="v">411.16 test USD<small>+ 166,666 tokens</small></div>' +
    '<div class="d">0 days</div><div class="z">0</div></div>' +
    '<div class="small">Each paid 500 test USD. Test round: three member wallets run by our script, steps typed in. Every transaction is in PROOF.md.</div>'),
  s5: `<div class="full"><div class="kicker">05 · Why it is different</div><h1 style="font-size:70px">Others split a pot.<br>Here, showing up adds a launch.</h1>
    <table style="margin-top:14px"><tr><th></th><th>Who holds the money?</th><th>What showing up together adds</th><th>Group falls short?</th></tr>
    <tr><td>Stake apps<span class="ex">StickK · Beeminder · DietBet</span></td><td>A company charges your card or holds the pot</td><td>Nothing. At best, a share of what others lost</td><td>Each person passes or fails alone</td></tr>
    <tr><td>Move to earn<span class="ex">STEPN · Sweatcoin</span></td><td>No shared pot</td><td>Nothing shared: new tokens, ads</td><td>No group goal</td></tr>
    <tr><td>Step challenges<span class="ex">Strava</span></td><td>No money</td><td>A badge</td><td>Nothing at stake</td></tr>
    <tr><td>Plain token launch<span class="ex">money fills the bar</span></td><td>A contract</td><td>Nobody has to show up</td><td>Money goal only</td></tr>
    <tr class="us"><td>Cypher Run</td><td>A contract, not us</td><td><b>A Flap launch:</b> half the token supply + 80% of its tax, on top of the deposits</td><td><b>Not launched by the deadline: every deposit back</b></td></tr></table>
    <div class="note">Fewer days, smaller share. Zero days: your deposit goes to those who showed up. One day = one share, beginner or marathoner.</div></div>${pill}`,
  s6: `<div class="full"><div class="kicker">06 · How it is built</div><h1>Contracts hold the money.<br>Not us.</h1>
    <div class="arch">
      <div class="box"><h3>OUR SERVER</h3><p><b>Decides if a day counts:</b> signs one check-in per wallet per day</p><p>Cannot move funds, launch early, or block a launch</p></div>
      <div class="arrow">⇄</div>
      <div class="box"><h3>PHONE</h3><p>Reads today's steps from <b>Apple Health / Health Connect</b></p><p>Wallet key stays on the device</p><p>Sends every transaction from the member's own wallet</p></div>
      <div class="arrow">→</div>
      <div class="box chain"><h3>BNB CHAIN (TESTNET)</h3><p><b>Launcher Factory</b>, enabled on the Flap Portal</p><p><b>Launcher</b>: deposits, check-ins, the bar</p><p><b>launch()</b>, by anyone → Flap: token + pool, LP burned</p><p><b>Vault</b>: prize + half the supply + 80% of tax → claim by days</p></div>
    </div>
    <div class="strip">75 contract tests (+5 against the live Portal on a fork) · 203 server tests · open source · github.com/dokind/kickoff-bnb-hack</div></div>${pill}`,
  s7: `<div class="full" style="top:110px"><div class="kicker">07 · Try it</div><h1>Try it in 60 seconds.</h1>
    <div class="links">
      <div class="k">Web, no install</div><div class="u">dokind.github.io/kickoff-bnb-hack</div>
      <div class="k">Android</div><div class="u">cypher-run.apk · Releases on GitHub</div>
      ${TESTFLIGHT_APPROVED ? '<div class="k">iPhone</div><div class="u">TestFlight · link in the description</div>' : ''}
      <div class="k">Code + proof</div><div class="u">github.com/dokind/kickoff-bnb-hack</div>
    </div>
    <div class="sub" style="margin-top:50px">BNB Smart Chain testnet. Test USD has no value. <b>Show up together. Launch together.</b></div></div>${pill}`
};
const s = new URLSearchParams(location.search).get('s') || 's1';
if (s === 's4a') document.documentElement.classList.add('clear');
document.getElementById('root').innerHTML = S[s];
</script>
</body></html>
```

Render the frames with Playwright. Save this as `render.mjs`:

```js
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

fs.mkdirSync('frames', { recursive: true });
const scenes = ['s1', 's2', 's3', 's4a', 's4b', 's5', 's6', 's7'];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
for (const s of scenes) {
  await page.goto(pathToFileURL(path.resolve('cards.html')).href + '?s=' + s);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(400);
  await page.screenshot({ path: `frames/${s}.png`, omitBackground: s === 's4a' });
}
await browser.close();
console.log('frames written');
```

```sh
npm init -y
npm i -D playwright@1.49.1
npx playwright install chromium
node render.mjs
```

Open every PNG and check it. No text may be cut off, and nothing may sit in the bottom 200 px
except on `s4a`. If the owner sends a PNG of deck slide 6 (the architecture), scale it to
1920x1080 and use it as `frames/s6.png` in place of the rendered card:
`ffmpeg -y -i slide6.png -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x0A0E11" frames/s6.png`.
The deck is a private link (https://claude.ai/artifact/RggCsKsccSdm5GTuMiSo9A). Ask the owner to
export the slide. Do not try to log in to it.

## 6. Build the scenes

All scenes must come out at the same size (1920x1080), frame rate (30) and pixel format (yuv420p),
with no audio, so they can be joined without re-encoding.

```sh
# Phone scenes: frame + phone clip on the left. The clip's last frame is held if the clip is short.
# Usage: scene <frame> <clip> <seconds> <out>
ffmpeg -y -loop 1 -framerate 30 -i frames/s1.png -i clips/s1.mp4 -filter_complex \
 "[1:v]fps=30,scale=-2:820:flags=lanczos,setsar=1,tpad=stop_mode=clone:stop_duration=60[p];[0:v][p]overlay=x=200:y=40,format=yuv420p[v]" \
 -map "[v]" -t 10 -c:v libx264 -crf 18 -preset medium scenes/s1.mp4
# Repeat with: s2 -> -t 20, s3 -> -t 18, s4b -> -t 8 (same command, change the three names and -t)

# Scene 4a: desktop footage in a box, transparent label frame on top
ffmpeg -y -f lavfi -i "color=c=0x0A0E11:s=1920x1080:r=30" -i clips/s4a.mp4 -loop 1 -framerate 30 -i frames/s4a.png -filter_complex \
 "[1:v]fps=30,scale=1760:740:force_original_aspect_ratio=decrease:flags=lanczos,setsar=1,tpad=stop_mode=clone:stop_duration=60[b];[0:v][b]overlay=x=(W-w)/2:y=110[t];[t][2:v]overlay=0:0,format=yuv420p[v]" \
 -map "[v]" -t 16 -c:v libx264 -crf 18 -preset medium scenes/s4a.mp4

# Card scenes: still image (s5 23 s, s6 15 s, s7 10 s)
ffmpeg -y -loop 1 -framerate 30 -i frames/s5.png -t 23 -vf "format=yuv420p" -c:v libx264 -crf 18 -preset medium -tune stillimage scenes/s5.mp4
ffmpeg -y -loop 1 -framerate 30 -i frames/s6.png -t 15 -vf "format=yuv420p" -c:v libx264 -crf 18 -preset medium -tune stillimage scenes/s6.mp4
ffmpeg -y -loop 1 -framerate 30 -i frames/s7.png -t 10 -vf "format=yuv420p" -c:v libx264 -crf 18 -preset medium -tune stillimage scenes/s7.mp4
```

The phone clip comes out 378 px wide, so it sits inside the 400 px slot, which starts at x=190.

Join the scenes into one silent video. Save this as `list.txt`:

```text
file 'scenes/s1.mp4'
file 'scenes/s2.mp4'
file 'scenes/s3.mp4'
file 'scenes/s4a.mp4'
file 'scenes/s4b.mp4'
file 'scenes/s5.mp4'
file 'scenes/s6.mp4'
file 'scenes/s7.mp4'
```

```sh
ffmpeg -y -f concat -safe 0 -i list.txt -c copy out/video_nosound.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 out/video_nosound.mp4   # expect 120.0
```

## 7. Voiceover

**Preferred: the owner's real voice.** Ask the owner to record it. A real voice wins over a
synthetic one. Send them the script in section 3 and these notes:

- Record in a quiet room with soft things around (a closet works). Hold the phone or microphone a
  hand's width away. Stand up while you speak.
- Record one file per scene, `audio/s1.wav` to `audio/s7.wav`, and three takes of each. Keep the
  best one.
- Delivery: short and certain, a beat of silence before each number ("Two days… 822."), and a
  downward ending on every sentence. No "um", no "so yeah". Smile on the last scene.
- Each file must fit its scene: s1 ≤ 9.5 s, s2 ≤ 19.5 s, s3 ≤ 17.5 s, s4 (4a plus 4b) ≤ 23.5 s,
  s5 ≤ 22.5 s, s6 ≤ 14.5 s, s7 ≤ 9.5 s. Check with
  `ffprobe -v error -show_entries format=duration -of csv=p=0 audio/s5.wav`. If a take runs long,
  record it again a little faster. Speed it up with `atempo` only as a last resort (at most 1.06).

**Placeholder until then: the computer's own voice** (never ship this if the owner sends a
recording):

- macOS: `say -v Samantha -r 165 -o audio/s1.aiff "Your gym gets paid when you quit. Cypher Run splits the pot by days shown up. On testnet, it already did."`
  then `ffmpeg -y -i audio/s1.aiff -ar 48000 audio/s1.wav`. Repeat for each scene.
- Windows PowerShell:

  ```powershell
  Add-Type -AssemblyName System.Speech
  $t = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $t.Rate = 1
  $t.SetOutputToWaveFile("$PWD\audio\s1.wav")
  $t.Speak("Your gym gets paid when you quit. Cypher Run splits the pot by days shown up. On testnet, it already did.")
  $t.Dispose()
  ```

Place each scene's voice at its scene start, then even out the loudness. The delays are in
milliseconds: s1 300, s2 10200, s3 30200, s4 48200, s5 72200, s6 95200, s7 110200.

```sh
ffmpeg -y -i audio/s1.wav -i audio/s2.wav -i audio/s3.wav -i audio/s4.wav -i audio/s5.wav -i audio/s6.wav -i audio/s7.wav -filter_complex \
 "[0]adelay=300:all=1[a0];[1]adelay=10200:all=1[a1];[2]adelay=30200:all=1[a2];[3]adelay=48200:all=1[a3];[4]adelay=72200:all=1[a4];[5]adelay=95200:all=1[a5];[6]adelay=110200:all=1[a6];[a0][a1][a2][a3][a4][a5][a6]amix=inputs=7:normalize=0,highpass=f=80,loudnorm=I=-16:TP=-1.5:LRA=11,apad=whole_dur=120[a]" \
 -map "[a]" -ar 48000 -ac 2 audio/vo.wav
```

**Music is optional.** Use royalty-free music only (for example the YouTube Audio Library, with the
attribution its page asks for), and keep it far under the voice:

```sh
ffmpeg -y -i audio/vo.wav -stream_loop -1 -i audio/music.mp3 -filter_complex "[1:a]volume=0.07,afade=t=out:st=117:d=3[m];[0:a][m]amix=inputs=2:duration=first:normalize=0[a]" -map "[a]" -ar 48000 audio/mix.wav
```

## 8. Captions: `captions.srt`

Save this exactly as `captions.srt` (UTF-8) in the working folder. The times follow the scene plan.
After the real voiceover is in, play `out/video_nosound.mp4` together with `audio/vo.wav` and nudge
any cue that is early or late. Aegisub and Subtitle Edit are both free tools for that.

```text
1
00:00:00,300 --> 00:00:03,200
Your gym gets paid when you quit.

2
00:00:03,300 --> 00:00:06,400
Cypher Run splits the pot by days shown up.

3
00:00:06,500 --> 00:00:09,000
On testnet, it already did.

4
00:00:10,200 --> 00:00:12,600
Here's the deal.
You put in a deposit.

5
00:00:12,700 --> 00:00:15,600
Today, that's test dollars
on BNB testnet.

6
00:00:15,700 --> 00:00:19,400
One tap, and you're in a round
with everyone else.

7
00:00:19,500 --> 00:00:23,400
The app shows you, in plain words,

8
00:00:23,500 --> 00:00:29,600
what you put in, what you can get,
and how it ends.

9
00:00:30,200 --> 00:00:32,400
Each day you move, check in once.

10
00:00:32,500 --> 00:00:36,400
On a phone, steps come from
Apple Health or Health Connect.

11
00:00:36,500 --> 00:00:39,200
Every check-in fills one shared bar.

12
00:00:39,300 --> 00:00:43,400
Full by the deadline:
anyone launches the token.

13
00:00:43,500 --> 00:00:47,000
Miss it: every deposit comes back.

14
00:00:48,200 --> 00:00:50,000
This isn't a mockup.

15
00:00:50,100 --> 00:00:55,200
Round one ran end to end: three
member wallets, 500 test dollars each.

16
00:00:55,300 --> 00:00:58,200
A member, not our server,
pressed launch.

17
00:00:58,300 --> 00:01:03,600
One call to Flap Pool Launch:
token, pool, LP burned, vault funded.

18
00:01:04,000 --> 00:01:07,000
The vault paid the prize
and the trading tax by days.

19
00:01:07,100 --> 00:01:11,800
Two days: 822. One day: 411.
Zero days: zero.

20
00:01:12,200 --> 00:01:18,600
Stake apps: a company holds the money,
and the best you win is what others lost.

21
00:01:18,700 --> 00:01:20,700
Here a contract holds it.

22
00:01:20,800 --> 00:01:24,400
Showing up together also
launches a token on Flap:

23
00:01:24,500 --> 00:01:30,400
half its supply and 80% of its tax
go to those who showed up.

24
00:01:30,500 --> 00:01:34,800
Fall short together?
Every deposit comes back.

25
00:01:35,200 --> 00:01:38,600
Our Launcher Factory is enabled
on Flap's Portal.

26
00:01:38,700 --> 00:01:41,200
Contracts hold the money. Not us.

27
00:01:41,300 --> 00:01:45,600
You trust one thing:
our server decides if a day counts.

28
00:01:45,700 --> 00:01:49,800
It can't move money, launch early,
or block a launch.

29
00:01:50,200 --> 00:01:52,600
Try it in sixty seconds.

30
00:01:52,700 --> 00:01:55,600
Open the link.
No install, no real money.

31
00:01:55,700 --> 00:01:59,800
Bring your crew. Show up.
Launch together.
```

## 9. Final render with burned-in captions

**Way A (works with any ffmpeg; use this one).** Many ffmpeg builds have no `subtitles` filter.
The Homebrew build on macOS is one of them. This script turns each cue of `captions.srt` into a
transparent PNG with Playwright, then overlays each PNG during its time range. It was tested end to
end with ffmpeg 8.1. Save it as `burn-captions.mjs` in the working folder:

```js
// Burns captions.srt into the video without needing ffmpeg's libass:
// renders each cue to a transparent 1920x1080 PNG, then overlays it during its time range.
// Usage: node burn-captions.mjs <video_nosound.mp4> <audio.wav> <out.mp4>
import { chromium } from 'playwright';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';

const [video = 'out/video_nosound.mp4', audio = 'audio/vo.wav', out = 'out/cypher-run-demo-1080p.mp4'] = process.argv.slice(2);
const toSec = (s) => { const [h, m, rest] = s.split(':'); const [sec, ms] = rest.split(','); return +h * 3600 + +m * 60 + +sec + +ms / 1000; };
const cues = fs.readFileSync('captions.srt', 'utf8').replace(/\r/g, '').trim().split(/\n\s*\n/).map((b) => {
  const lines = b.split('\n');
  const [a, z] = lines[1].split(' --> ');
  return { start: toSec(a.trim()), end: toSec(z.trim()), text: lines.slice(2).join('\n') };
});

fs.mkdirSync('caps', { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, '<br>');
for (const [i, c] of cues.entries()) {
  await page.setContent(`<html style="background:transparent"><body style="margin:0;width:1920px;height:1080px;background:transparent;position:relative">
    <div style="position:absolute;left:0;right:0;bottom:52px;text-align:center">
      <span style="display:inline-block;font:700 46px/1.25 Inter,Arial,sans-serif;color:#fff;background:rgba(0,0,0,.62);padding:10px 26px;border-radius:14px;-webkit-box-decoration-break:clone">${esc(c.text)}</span>
    </div></body></html>`);
  await page.screenshot({ path: `caps/${String(i).padStart(2, '0')}.png`, omitBackground: true });
}
await browser.close();

const args = ['-y', '-i', video, '-i', audio];
cues.forEach((_, i) => args.push('-i', `caps/${String(i).padStart(2, '0')}.png`));
let graph = '';
let last = '0:v';
cues.forEach((c, i) => {
  const label = i === cues.length - 1 ? 'vout' : `v${i}`;
  graph += `[${last}][${i + 2}:v]overlay=0:0:enable='between(t,${c.start.toFixed(3)},${c.end.toFixed(3)})'[${label}];`;
  last = label;
});
graph = graph.slice(0, -1) + ';[vout]format=yuv420p[vf]';
args.push('-filter_complex', graph, '-map', '[vf]', '-map', '1:a', '-c:v', 'libx264', '-crf', '18', '-preset', 'slow',
  '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out);
const r = spawnSync('ffmpeg', args, { stdio: 'inherit' });
process.exit(r.status ?? 1);
```

```sh
node burn-captions.mjs out/video_nosound.mp4 audio/vo.wav out/cypher-run-demo-1080p.mp4
```

Use `audio/mix.wav` in place of `audio/vo.wav` if you added music.

**Way B (only if `ffmpeg -hide_banner -filters` lists `subtitles`, as the Gyan builds on Windows
do).** Run it from inside the working folder, because on Windows a subtitle path with `C:` in it
breaks the filter:

```sh
ffmpeg -y -i out/video_nosound.mp4 -i audio/vo.wav \
 -vf "subtitles=captions.srt:force_style='FontName=Arial,FontSize=13,Bold=1,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1,Outline=2,Shadow=0,Alignment=2,MarginV=14'" \
 -map 0:v -map 1:a -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k -shortest -movflags +faststart \
 out/cypher-run-demo-1080p.mp4
```

In Way B the subtitles use a 384x288 grid that is scaled up to 1080p: FontSize 13 comes out about
49 px tall, and MarginV 14 puts the text about 52 px above the bottom edge.

Whichever way you used, pull stills and look at them:

```sh
for t in 5 25 45 58 68 80 100 115; do ffmpeg -y -ss $t -i out/cypher-run-demo-1080p.mp4 -frames:v 1 out/check_$t.png; done
```

(In PowerShell: `foreach ($t in 5,25,45,58,68,80,100,115) { ffmpeg -y -ss $t -i out/cypher-run-demo-1080p.mp4 -frames:v 1 "out/check_$t.png" }`.)
The captions must sit in the empty bottom band. They must not cover the phone or the cards, and
they must not run past two lines.

**Optional vertical copy** for social media (judges should get the 16:9 file):
`ffmpeg -y -i out/cypher-run-demo-1080p.mp4 -vf "scale=1080:-2,pad=1080:1920:0:(oh-ih)/2:color=0x0A0E11" -c:v libx264 -crf 20 -c:a copy out/cypher-run-demo-vertical.mp4`

## 10. Checklist before upload

- [ ] Length is 2:00, and not over 2:30 (`ffprobe` on the final file).
- [ ] Watch the whole thing once on a phone screen. Every caption and headline is readable at
      phone size, and the numbers 822.32 / 411.16 / 0 can be read.
- [ ] Audio: the voice is clear, nothing clips, the music (if any) sits far below the voice, and
      the levels are steady from scene to scene.
- [ ] "TESTNET · NO REAL MONEY" is visible in every scene, and "test USD" or "test dollars" is the
      only money wording on screen and in the voiceover.
- [ ] Nothing private is on screen: no private key and no "Back up your key" sheet, no emails or
      notifications, no server address or IP, no DevTools panels, no address bar with personal
      bookmarks, no user name in file paths.
- [ ] Scene 4 says "three members" or "member wallets", never "three people", and its small print
      says it was a scripted test round.
- [ ] The honest bound is stated (scene 6): our server decides if a day counts, and it cannot move
      money, launch early or block a launch.
- [ ] Scene 5 never implies that no-shows' deposits stay with them: the card's note line says a
      member with 0 days gets nothing.
- [ ] The iPhone line appears (on the card and in the description) only if the TestFlight link
      accepts testers right now.
- [ ] All links in the description open: web app, APK, repo, PROOF.md, whitepaper.
- [ ] No token tickers anywhere.

## 11. Upload and HackQuest text

**Upload:** YouTube, **Unlisted** (preferred; judges can play it without signing in), on the
owner's account. Ask the owner to sign in, and never type their password yourself. Alternative:
Loom, shared as "anyone with the link". After uploading, open the link in a private window to make
sure it plays without a login. Give the link to the owner.

**YouTube title:** `Cypher Run: show up together, launch together · BNB Hack Bangkok (testnet demo)`

**YouTube description and HackQuest description field.** The final text, in the final
positioning: the pot is safe, the launch is the bonus. The iPhone line carries its caveat: the
TestFlight link opens only after Apple approves the beta (build 202611261356 was in Apple's beta
review on 26 November 2026). Once Apple approves it, the caveat in brackets can go; if it is still
not approved at upload time, keep the caveat or remove the line. The Squad A line links to Season 1
Squad A, created on BSC testnet on 26 November 2026.

```text
Cypher Run turns showing up into a community, and a community into a launch. Built on Flap Pool Launch, on BNB Chain. Voiced in the founder's own voice (an AI clone of it).

The pot is safe, the launch is the bonus. A group puts in equal deposits and checks in each day they walk 1,000 steps or more (the phone app reads Apple Health or Health Connect; on the web you type them, testnet only). Everyone's check-ins fill one bar.

Two endings. The group falls short: if the round has not launched by its deadline, each member presses Refund and gets 100% of the deposit back. The bar fills: anyone can launch the group's own coin through Flap. 1,000,000 coins: half into a shop locked forever (its LP is burned), half into the group's piggy bank with the prize, plus 80% of 30 days of trading tax (3% on buys, 5% on sells; the other 20% is burned). The piggy bank is split by days shown up, not by dollars; 0 days gets nothing.

Why Flap Pool Launch: members get a free bonus on top of a safe pot, paid for by a sponsor; sponsors launch their community's coin with a crowd that has already proven it shows up; and Flap gets launches that can't happen until a community exists, because days of people showing up are the launch condition.

Season 1: Show Up 30 starts Tue 1 Dec 2026, in squads of 10. A sponsor fills each squad's shop, so every deposit is prize: keep up with the average member and you get your whole deposit back, or more (sponsored rounds, test USD, once the round launches). Join Squad A · starts Tue 1 Dec: https://dokind.github.io/kickoff-bnb-hack/#/r/0xa60e2f022d891dd394415a594c9e33614c019153

Proof on BSC testnet: the round "Bangkok Showup" launched through our Launcher Factory (enabled on Flap's testnet Portal) and split its prize and trading tax by days: 822.32 / 411.16 / 0 test USD to members with 2 / 1 / 0 days. A split, not a return: it was a scripted test round with typed-in steps, and the tax came from our own test trades. 47 transactions, all listed in PROOF.md. The refund ending ran on testnet too: a round with a full bar that never launched (its shop was under Flap's floor) paid 150 test USD back after its deadline, exactly what its wallet put in.

Honest bound: our server's key decides which check-ins count (attested, not proven). It cannot move funds, launch early or block a launch. We never hold the money.

Testnet only. Test USD has no value. Not audited.

Try it (web, no install): https://dokind.github.io/kickoff-bnb-hack/
Android: https://github.com/dokind/kickoff-bnb-hack/releases/download/android-latest/cypher-run.apk
iPhone (TestFlight; the link opens only after Apple approves the beta): https://testflight.apple.com/join/bp4WaEu5
Code: https://github.com/dokind/kickoff-bnb-hack
Proof: https://github.com/dokind/kickoff-bnb-hack/blob/main/PROOF.md
Whitepaper: https://github.com/dokind/kickoff-bnb-hack/blob/main/docs/WHITEPAPER.md

0:00 The idea, and joining a round
0:24 Check in, fill the bar
0:45 The launch, and a testnet round split by days
1:01 Who it is for: a marathon, a charity walk
1:14 We never hold the money
```

The chapter times are where lines 5, 7, 8 and 10 start in the 85-second cut as first rendered.
Rechecked on 26 November against `pitch-video/cypher-run-demo.srt` as it is now (the new words at
the old times): 0:24.7, 0:45.3, 1:01.5 and 1:14.0, so the list above still holds for that timeline.
A new render with the re-voiced lines moves all four by the change in line 1's length (line 7's
scene has a fixed length, and line 10 starts its own chapter), so read them again from the new
cut's captions before uploading. YouTube needs each chapter to be at least 10 seconds, so the hook
and the join share the first one.

## 12. What to ask the owner (ask early, all at once)

1. "Please send a PNG export of deck slide 6 (the architecture). If you don't, I'll use the card in
   this brief."
2. "Please record the voiceover, one file per scene. The script and timing are attached. Until it
   arrives, I'll build the cut with a placeholder voice."
3. "How many steps did you walk today? It goes into the web check-in, which is labelled as typed
   in."
4. "Has TestFlight been approved yet?" (Check the link yourself as well.)
5. "Please sign in to YouTube (or Loom) for the upload."

When you are done, report the video link, the final length, the file path of
`out/cypher-run-demo-1080p.mp4`, and anything that differs from this brief (for example a scene
that used a fallback).
