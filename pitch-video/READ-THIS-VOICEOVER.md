# Cypher Run video: read this out loud

One take, about 85 seconds. Read each numbered line, then **pause a full second** (count "one-thousand")
before the next. The pauses are how the video lines up with your voice, so keep them clear. Talk like
you are explaining it to a friend at the venue: a little faster than normal, smiling, no announcer voice.
If you stumble, pause two seconds and read that same line again; the last take of a line wins.

Record anywhere quiet, phone 15–20 cm from your mouth. iPhone Voice Memos, QuickTime
(File > New Audio Recording) or the Windows Sound Recorder are all fine.

---

1. What if showing up every day earned you a share, and skipping cost you yours?

2. Most fitness goals die in week two. Badges don't stop that, and betting apps make money when you fail.

3. Cypher Run flips it. Everyone puts in a small deposit, walks every day, and every check-in fills one shared bar.

4. Joining takes one tap. On testnet the app gets you free test dollars, pays the deposit, and drops you into your round.

5. Then you walk. Cypher Run reads today's steps from Apple Health or Health Connect. Read only. Pass a thousand steps, check in, and your share updates on the spot.

6. Your round shows what you'd get if it launched right now, and how every ending plays out. If the group falls short, your deposit comes back.

7. When the bar is full, anyone can launch the round's coin on Flap. The prize, half the new coins, and most of the trading tax go into the group's piggy bank, split by days. This testnet round split it two thirds, one third, and nothing for the member who never walked.

8. Run it for a marathon. The race sponsors the pool, runners train for six weeks, and the ones who trained most earn most.

9. Or a charity walk. A sponsor funds the pool, supporters walk every day, and members can give what they earn to the cause.

10. We never hold the money. It's all contracts on BNB Smart Chain, launched through Flap.

11. Cypher Run. Show up, and earn your share.

---

Want to change a line in your own words? Do it. Keep the same 11 lines in the same order and the
video follows your timing.

---

## Or: his AI voice (SoloSpark Voice), no recording needed

`vo/s1.aiff … s11.aiff` in this repo are already the 11 lines in his own cloned voice (namsrai-2.0 + his reference
recording, English), picked take by take for speaker similarity and read-back accuracy (`vo/picks.json`).
Rebuild them on the Windows PC with the GPU:

    <solospark-voice>/workspace/envs/train/Scripts/python.exe my-voice-en.py --with-ref --takes 4 --speed 0.95 --out cand/slow
    <solospark-voice>/workspace/envs/data/Scripts/python.exe pick-my-voice.py cand/slow --out vo

`--with-ref` matters: without his reference clip the English lines drift to other speakers.
To put a new voice on an already-rendered video without re-rendering it: `node dub-video.mjs <video.mp4> vo`.
The voice weights are CC-BY-NC 4.0: fine for the hackathon, not for paid use.
