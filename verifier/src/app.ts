// The HTTP API. Everything it needs is passed in, so tests can run it with fakes.
//
// What this server does for a round: it accepts a member's daily report (steps from the phone's
// health data, or typed in on the web when that is allowed) and signs the check-in the contract
// requires. It also remembers the accepted days (for streaks), relays what the chain says about
// the round, and hands out gas money. It cannot launch early, block a launch, choose who is paid
// beyond signing daily check-ins, or move funds. Check-ins are attested, not proven.
//
// Rounds: every route about a round exists twice. `/rounds/:launcher/...` names the round;
// `/round`, `/me`, `/members` and `/checkin` are the same routes for the featured round (the one
// set with CURRENT_LAUNCHER or POST /admin/round). GET /rounds is the app's public list.
import { createHash, timingSafeEqual } from "node:crypto";
import { Hono, type Context } from "hono";
import { cors } from "hono/cors";
import { formatUnits, getAddress, isAddress, recoverMessageAddress } from "viem";
import type { Attester } from "./attest.js";
import type { Chain, ClaimState, MemberState, RoundState } from "./chain.js";
import { dayIndexAt, dayString, streaks } from "./days.js";
import { DRIP_BNB_WEI, FAUCET_MESSAGES, MIN_BALANCE_WEI, PER_IP_PER_HOUR, RESERVE_WEI, faucetRefusal } from "./faucet.js";
import type { OriginHealth } from "./origin.js";
import { SERVICE_NAME, checkInMessage, faucetMessage, roundMessage } from "./product.js";
import { LISTING_DELAY_SECONDS, createRounds, type Rounds } from "./rounds.js";
import { DEFAULT_MIN_STEPS, checkReport, parseSteps } from "./rules.js";
import { totals, walletTotals, type Totals, type WalletTotals } from "./stats.js";
import type { Store } from "./store.js";
import type { CheckIn, FaucetDrip, RoundRef, Source } from "./types.js";

/** GET /rounds reads an open round from the chain again after this long; a launched or expired one
 *  after CLOSED_CACHE_FACTOR times as long. Between reads it answers from memory. */
export const LIST_CACHE_MS = 4_000;
const CLOSED_CACHE_FACTOR = 15;
/** When a round cannot be read, GET /rounds shows what it read last, but nothing older than this. */
const LIST_STALE_MS = 300_000;
/** Rounds read from the chain at the same time for GET /rounds. */
const LIST_READS_AT_ONCE = 6;
/** GET /stats answers from memory for this long before it adds the rounds up again. */
export const STATS_CACHE_MS = 10_000;
/** Wallets whose own totals (GET /stats/:address) are kept in memory at once. */
const WALLET_MEMORY_SIZE = 500;

export type RoundStatus = "open" | "launched" | "expired";

export interface Deps {
  store: Store;
  chain: Chain;
  /** Signs check-ins. Undefined when no key is configured: POST /checkin then answers 503. */
  attester?: Attester;
  adminToken?: string;
  now?: () => number;
  /** CURRENT_LAUNCHER (and CURRENT_ROUND_NAME): the round served until POST /admin/round sets one. */
  defaultRound?: { launcher: string; name?: string };
  minSteps?: number;
  /** ALLOW_SELF_REPORTED=true: accept source "self" (the testnet demo on the web). */
  allowSelfReported?: boolean;
  /** POST /faucet pays out only when this is true (FAUCET_ENABLED=true) and the chain has a wallet. */
  faucetEnabled?: boolean;
  /** Network address of the caller, for the faucet's per-IP limit. Default: everyone shares one bucket. */
  clientIp?: (c: Context) => string;
  /** FAUCET_DRIP_BNB in wei. Default DRIP_BNB_WEI (0.03 test BNB). */
  faucetDripWei?: bigint;
  /** FAUCET_PER_IP_PER_HOUR. Default PER_IP_PER_HOUR (5). */
  faucetPerIpPerHour?: number;
  /** The origin announcer's state for GET /health. Undefined when it is off. */
  originHealth?: () => OriginHealth;
  /** Address of a token's page on Flap, with `{token}` where the token address goes. */
  flapTokenUrl?: string;
  /** The rounds our factory created. Default: none are discovered, only the featured round is known. */
  rounds?: Rounds;
  /** See LIST_CACHE_MS. 0 reads every round on every GET /rounds. */
  listCacheMs?: number;
  /** See STATS_CACHE_MS. 0 adds the rounds up on every GET /stats. */
  statsCacheMs?: number;
  /** GET /rounds scans for new rounds first when the last scan is older than this. */
  roundsMaxAgeMs?: number;
  /** ...and waits at most this long for that scan before answering with what is known. */
  roundsWaitMs?: number;
  /** POST /rounds looks again this many times, this far apart, for a launcher the RPC does not show
   *  yet: the creator's app registers a round right after its creation transaction. */
  registerRetry?: { times: number; waitMs: number };
}

/** The address (lower-case) that personal_signed `message`, or null if the signature is malformed. */
async function signerOf(message: string, signature: unknown): Promise<string | null> {
  if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) return null;
  try {
    return (await recoverMessageAddress({ message, signature: signature as `0x${string}` })).toLowerCase();
  } catch {
    return null;
  }
}

/** True when `address` signed the text built from `subject` written lower-case or checksummed
 *  (wallet libraries differ on which form they hand out). `subject` is an address. */
async function signedEitherForm(address: string, signature: unknown, text: (subject: string) => string, subject: string) {
  for (const form of [subject.toLowerCase(), getAddress(subject)]) {
    if ((await signerOf(text(form), signature)) === address) return true;
  }
  return false;
}

const addr = (value: unknown): string | null =>
  typeof value === "string" && isAddress(value, { strict: false }) ? value.toLowerCase() : null;

const sameToken = (a: string, b: string) =>
  timingSafeEqual(createHash("sha256").update(a).digest(), createHash("sha256").update(b).digest());

export function createApp({
  store,
  chain,
  attester,
  adminToken,
  now: clock,
  defaultRound,
  minSteps = DEFAULT_MIN_STEPS,
  allowSelfReported = false,
  faucetEnabled = false,
  clientIp = () => "unknown",
  faucetDripWei = DRIP_BNB_WEI,
  faucetPerIpPerHour = PER_IP_PER_HOUR,
  originHealth,
  flapTokenUrl,
  rounds = createRounds({ store }),
  listCacheMs = LIST_CACHE_MS,
  statsCacheMs = STATS_CACHE_MS,
  roundsMaxAgeMs = 20_000,
  roundsWaitMs = 2_500,
  registerRetry = { times: 2, waitMs: 1_500 },
}: Deps) {
  const now = clock ?? (() => Math.floor(Date.now() / 1000));
  /** Milliseconds, for the short-lived memory of GET /rounds. Follows an injected clock. */
  const nowMs = clock ? () => clock() * 1000 : () => Date.now();
  const app = new Hono();
  // The web app calls this server from a browser, so every response carries CORS headers and
  // OPTIONS preflights are answered here (204) before any route runs.
  app.use("*", cors({ origin: "*", allowMethods: ["GET", "POST", "OPTIONS"], allowHeaders: ["Content-Type"] }));

  type Status = 400 | 401 | 403 | 404 | 409 | 422 | 503;
  const err = (c: Context, status: Status, error: string, message: string) => c.json({ error, message }, status);
  const noRound = (c: Context) => err(c, 404, "no_round", "no round is set on this server");
  const notOurs = (c: Context) => err(c, 404, "no_round", "no round with this address was created through this app's factory");
  const chainDown = (c: Context) => err(c, 503, "chain_unavailable", "could not read the round on chain; try again");

  async function body(c: Context): Promise<Record<string, unknown>> {
    const parsed: unknown = await c.req.json().catch(() => null);
    return parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : {};
  }

  /** The round being served: the one set with POST /admin/round, otherwise the configured default. */
  async function currentRound(): Promise<RoundRef | null> {
    const stored = await store.getRound();
    if (stored) return stored;
    return defaultRound ? { launcher: defaultRound.launcher.toLowerCase(), name: defaultRound.name ?? "", setAt: 0 } : null;
  }

  type Found = { ref: RoundRef } | Response;
  /** For the routes without a launcher in the path: the featured round. */
  const featuredRound = async (c: Context): Promise<Found> => {
    const ref = await currentRound();
    return ref ? { ref } : noRound(c);
  };
  /**
   * For `/rounds/:launcher/...`: that round, when our factory created it (or it is the featured
   * round). A launcher not seen yet is looked for on chain first.
   */
  const namedRound = async (c: Context): Promise<Found> => {
    const launcher = addr(c.req.param("launcher"));
    if (!launcher) return err(c, 400, "bad_launcher", "launcher must be an address");
    const featured = await currentRound();
    if (featured?.launcher === launcher) return { ref: featured };
    const found = await rounds.find(launcher);
    if (found.round) return { ref: { launcher, name: "", setAt: found.round.createdAt } };
    return found.complete ? notOurs(c) : chainDown(c);
  };

  const ourAttester = attester?.address.toLowerCase() ?? null;

  const statusOf = (s: RoundState): RoundStatus => (s.launched ? "launched" : now() > s.deadline ? "expired" : "open");

  /** GET /round. Amounts are decimal strings in whole tokens; `raw` holds the same in smallest units. */
  function roundView(ref: RoundRef, s: RoundState) {
    const quote = (amount: bigint) => formatUnits(amount, s.quoteDecimals);
    const today = dayIndexAt(now());
    return {
      launcher: ref.launcher,
      name: ref.name || s.name,
      quoteToken: s.quoteToken,
      deposit: quote(s.deposit),
      liquidityBps: s.liquidityBps,
      checkInGoal: s.checkInGoal,
      totalCheckIns: s.totalCheckIns,
      memberCount: s.memberCount,
      totalDeposits: quote(s.totalDeposits),
      totalSponsored: quote(s.totalSponsored),
      poolQuoteNow: quote(s.poolQuoteNow),
      prizeNow: quote(s.prizeNow),
      deadline: s.deadline,
      launched: s.launched,
      token: s.token,
      vault: s.vault,
      minSteps,
      flapUrl: s.launched && s.token && flapTokenUrl ? flapTokenUrl.replaceAll("{token}", getAddress(s.token)) : null,
      // Beyond the fields above: what the app needs to build today's signed text and to explain
      // what it may do next.
      today: dayString(today),
      dayIndex: today,
      canLaunch: s.canLaunch,
      refundOpen: !s.launched && now() > s.deadline,
      allowSelfReported,
      attester: s.attester,
      // False when the round was created with another attester (or this server has no key): the
      // contract would reject every signature from here, so check-ins are refused.
      attesterReady: ourAttester !== null && ourAttester === s.attester,
      quoteDecimals: s.quoteDecimals,
      raw: {
        deposit: s.deposit.toString(),
        totalDeposits: s.totalDeposits.toString(),
        totalSponsored: s.totalSponsored.toString(),
        poolQuoteNow: s.poolQuoteNow.toString(),
        prizeNow: s.prizeNow.toString(),
      },
    };
  }

  /** Remembers an address the chain confirmed as a member, so GET /members can list it. */
  async function remember(launcher: string, address: string) {
    if (!(await store.getMembers(launcher)).includes(address)) await store.addMember(launcher, address, now());
  }

  /**
   * The Launcher has no list of members to read, so this is everyone this server has seen as a
   * member of the round: a wallet appears after its first GET /me or POST /checkin as a member.
   */
  async function seenMembers(launcher: string, checkIns?: CheckIn[]): Promise<string[]> {
    const days = checkIns ?? (await store.getCheckIns(launcher));
    return [...new Set([...(await store.getMembers(launcher)), ...days.map((d) => d.address)])];
  }

  app.get("/", (c) => c.json({ service: SERVICE_NAME, ok: true }));

  // For the operator: what this server announces and which wallets it sends from. Nothing secret.
  app.get("/health", (c) =>
    c.json({
      service: SERVICE_NAME,
      ok: true,
      attester: ourAttester,
      faucetWallet: faucetEnabled ? (chain.faucet?.address ?? null) : null,
      origin: originHealth?.() ?? null,
    }),
  );

  // ── The round ─────────────────────────────────────────────────────────────

  app.get("/round", async (c) => {
    const found = await featuredRound(c);
    if (found instanceof Response) return found;
    const { ref } = found;
    try {
      return c.json(roundView(ref, await chain.round(ref.launcher)));
    } catch {
      return chainDown(c);
    }
  });

  // The same object as GET /round, for any round our factory created, plus `unlisted`.
  app.get("/rounds/:launcher", async (c) => {
    const found = await namedRound(c);
    if (found instanceof Response) return found;
    const { ref } = found;
    const unlisted = (await store.getListing(ref.launcher))?.unlisted ?? false;
    try {
      return c.json({ ...roundView(ref, await chain.round(ref.launcher)), unlisted });
    } catch {
      return chainDown(c);
    }
  });

  const meRoute = (which: (c: Context) => Promise<Found>) => async (c: Context) => {
    const address = addr(c.req.param("address"));
    if (!address) return err(c, 400, "bad_address", "address must be an address");
    const found = await which(c);
    if (found instanceof Response) return found;
    const { ref } = found;
    const today = dayIndexAt(now());

    let round: RoundState, me: MemberState, claim: ClaimState | null;
    try {
      [round, me] = await Promise.all([chain.round(ref.launcher), chain.member(ref.launcher, address, today)]);
      claim = round.launched && round.vault ? await chain.claims(round.vault, address) : null;
    } catch {
      return chainDown(c);
    }
    if (me.member) await remember(ref.launcher, address);

    // Streaks come from the days this server accepted. A day accepted here whose transaction the
    // member never sent is in `days` but not in `daysOf`, which is the chain's count.
    const days = (await store.getCheckIns(ref.launcher))
      .filter((d) => d.address === address)
      .map((d) => d.day)
      .sort();
    const tokens = (amount: bigint) => formatUnits(amount, claim?.tokenDecimals ?? 18);
    const quote = (amount: bigint) => formatUnits(amount, round.quoteDecimals);
    return c.json({
      address,
      member: me.member,
      daysOf: me.daysOf,
      // Today's check-in is on chain.
      checkedInToday: me.checkedIn,
      ...streaks(days, today),
      days,
      claimableTokens: tokens(claim?.claimableTokens ?? 0n),
      claimableQuote: quote(claim?.claimableQuote ?? 0n),
      claimedTokens: tokens(claim?.claimedTokens ?? 0n),
      // Beyond the fields above.
      claimedQuote: quote(claim?.claimedQuote ?? 0n),
      // This server signed today's check-in. True with checkedInToday false means the member still
      // has to send the transaction; POST /checkin hands the same signature out again.
      attestedToday: days.includes(dayString(today)),
      refundable: quote(me.refundable),
      raw: {
        claimableTokens: (claim?.claimableTokens ?? 0n).toString(),
        claimableQuote: (claim?.claimableQuote ?? 0n).toString(),
        claimedTokens: (claim?.claimedTokens ?? 0n).toString(),
        claimedQuote: (claim?.claimedQuote ?? 0n).toString(),
        refundable: me.refundable.toString(),
      },
    });
  };
  app.get("/me/:address", meRoute(featuredRound));
  app.get("/rounds/:launcher/me/:address", meRoute(namedRound));

  const membersRoute = (which: (c: Context) => Promise<Found>) => async (c: Context) => {
    const found = await which(c);
    if (found instanceof Response) return found;
    const { ref } = found;
    const today = dayIndexAt(now());
    const checkIns = await store.getCheckIns(ref.launcher);
    const addresses = await seenMembers(ref.launcher, checkIns);
    let onChain: { daysOf: number; checkedIn: boolean }[];
    try {
      onChain = await chain.members(ref.launcher, addresses, today);
    } catch {
      return chainDown(c);
    }
    const rows = addresses.map((address, i) => ({
      address,
      daysOf: onChain[i]?.daysOf ?? 0,
      streak: streaks(
        checkIns.filter((d) => d.address === address).map((d) => d.day),
        today,
      ).streak,
      checkedInToday: onChain[i]?.checkedIn ?? false,
    }));
    rows.sort((a, b) => b.daysOf - a.daysOf || b.streak - a.streak || (a.address < b.address ? -1 : 1));
    return c.json(rows);
  };
  app.get("/members", membersRoute(featuredRound));
  app.get("/rounds/:launcher/members", membersRoute(namedRound));

  // ── The public list ───────────────────────────────────────────────────────
  // Every round our factory created that is listed. A round is listed when its creator registered
  // it as listed, or when nobody registered it and it is older than LISTING_DELAY_SECONDS (so a
  // round whose creator is about to register it as unlisted is never shown in between). A round
  // registered as unlisted is left out. That is all "unlisted" means: the round is still on chain
  // for anyone to read, and GET /rounds/:launcher answers for anyone who has its address.
  //
  // Rounds this server cannot sign check-ins for (created with another attester) are left out too:
  // nobody could fill their bar from this app. The featured round is exempt from that and from the
  // delay, because the operator chose it; an unlisted choice by its creator still applies.

  const listMemory = new Map<string, { state: RoundState; at: number }>();
  /** A round's state for the list: from memory while fresh, else from the chain. A read that fails
   *  falls back to what was read last, up to LIST_STALE_MS old; null when there is nothing. */
  async function listState(launcher: string): Promise<RoundState | null> {
    const kept = listMemory.get(launcher);
    if (kept) {
      const keep = statusOf(kept.state) === "open" ? listCacheMs : listCacheMs * CLOSED_CACHE_FACTOR;
      if (nowMs() - kept.at < keep) return kept.state;
    }
    try {
      const state = await chain.round(launcher);
      listMemory.set(launcher, { state, at: nowMs() });
      return state;
    } catch {
      return kept && nowMs() - kept.at < LIST_STALE_MS ? kept.state : null;
    }
  }

  app.get("/rounds", async (c) => {
    await rounds.fresh(roundsMaxAgeMs, roundsWaitMs);
    const featured = await currentRound();
    const t = now();

    const listed: { ref: RoundRef; createdAt: number; featured: boolean }[] = [];
    let featuredFound = false;
    for (const round of await rounds.all()) {
      const isFeatured = featured?.launcher === round.launcher;
      featuredFound ||= isFeatured;
      const listing = await store.getListing(round.launcher);
      const show = listing ? !listing.unlisted : isFeatured || t >= round.createdAt + LISTING_DELAY_SECONDS;
      if (!show) continue;
      const ref = isFeatured ? featured! : { launcher: round.launcher, name: "", setAt: round.createdAt };
      listed.push({ ref, createdAt: round.createdAt, featured: isFeatured });
    }
    // A featured round our factory did not create (or that has not been found yet) is still shown.
    if (featured && !featuredFound) listed.push({ ref: featured, createdAt: featured.setAt, featured: true });

    const states: (RoundState | null)[] = [];
    for (let i = 0; i < listed.length; i += LIST_READS_AT_ONCE) {
      states.push(...(await Promise.all(listed.slice(i, i + LIST_READS_AT_ONCE).map((r) => listState(r.ref.launcher)))));
    }
    // Nothing to show and nothing known: say the chain could not be read instead of "no rounds".
    if (listed.length > 0 ? states.every((s) => s === null) : !(await rounds.scanned())) return chainDown(c);

    const rows = listed.flatMap((r, i) => {
      const s = states[i];
      if (!s) return [];
      if (!r.featured && ourAttester !== null && s.attester !== ourAttester) return [];
      const v = roundView(r.ref, s);
      return [
        {
          createdAt: r.createdAt,
          item: {
            launcher: v.launcher,
            name: v.name,
            deposit: v.deposit,
            liquidityBps: v.liquidityBps,
            checkInGoal: v.checkInGoal,
            totalCheckIns: v.totalCheckIns,
            memberCount: v.memberCount,
            prizeNow: v.prizeNow,
            poolQuoteNow: v.poolQuoteNow,
            deadline: v.deadline,
            launched: v.launched,
            token: v.token,
            vault: v.vault,
            state: statusOf(s),
            featured: r.featured,
          },
        },
      ];
    });
    // Featured first; then open rounds, the nearest deadline first; then launched ones, the newest
    // first; then expired ones, the most recently expired first.
    const group = (x: (typeof rows)[number]) => (x.item.featured ? 0 : x.item.state === "open" ? 1 : x.item.state === "launched" ? 2 : 3);
    rows.sort((a, b) => {
      const g = group(a) - group(b);
      if (g !== 0) return g;
      const order = group(a) === 1 ? a.item.deadline - b.item.deadline : group(a) === 2 ? b.createdAt - a.createdAt : b.item.deadline - a.item.deadline;
      return order || (a.item.launcher < b.item.launcher ? -1 : 1);
    });
    return c.json({ rounds: rows.map((r) => r.item) });
  });

  // The creator of a round says whether it is on the public list. Signed with the wallet that
  // created the round (the factory's creation event names it); the creator may call it again.
  // The signed text has no date in it: a signature seen once can be sent again to set the same
  // choice again. Nothing here touches the round on chain.
  app.post("/rounds", async (c) => {
    const b = await body(c);
    const launcher = addr(b.launcher);
    if (!launcher) return err(c, 400, "bad_launcher", "launcher must be an address");
    const unlisted = b.unlisted;
    if (typeof unlisted !== "boolean") return err(c, 400, "bad_unlisted", "unlisted must be true or false");
    const badSignature = () => err(c, 401, "bad_signature", "signature is not the round creator's");
    if (typeof b.signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(b.signature)) return badSignature();

    let found = await rounds.find(launcher);
    for (let i = 0; !found.round && i < registerRetry.times; i++) {
      await new Promise((resolve) => setTimeout(resolve, registerRetry.waitMs));
      found = await rounds.find(launcher);
    }
    if (!found.round) return found.complete ? notOurs(c) : chainDown(c);
    const text = (subject: string) => roundMessage(subject, unlisted);
    if (!(await signedEitherForm(found.round.creator, b.signature, text, launcher))) return badSignature();

    await store.putListing(launcher, { unlisted, by: found.round.creator, at: now() });
    return c.json({ launcher, unlisted });
  });

  // ── Totals ────────────────────────────────────────────────────────────────
  // GET /stats: every round our factory created added up, listed or not (and the featured round,
  // when it is not one of them), except the rounds GET /rounds leaves out for their attester: a
  // round created with another attester is not counted unless it is the featured round. The answer
  // is numbers only. No round is named in it, so an unlisted round is counted without being shown.
  // The rounds are read the way GET /rounds reads them, with the same short memory, and the sum is
  // kept for `statsCacheMs`.
  //
  // What each number is: `checkIns`, `deposited` and `launched` are the chain's. `people` is the
  // wallets this server has seen as members, each counted once however many rounds it joined; a
  // wallet that joined on chain and never opened the app is not in it. A deposit taken back after
  // a missed deadline is no longer in `deposited`.
  //
  // GET /stats/:address is the same object plus `you`: that wallet across the rounds this server
  // has seen it join. `you` is null when one of those rounds could not be read: no figure rather
  // than a low one.

  type Counted = { launchers: string[]; states: (RoundState | null)[]; totals: Totals };
  let statsMemory: { at: number; value: Counted } | null = null;
  let statsRun: Promise<Counted | null> | null = null;

  /** Null when nothing could be read from the chain at all. Requests made while one sum is being
   *  worked out share it. */
  function countEverything(): Promise<Counted | null> {
    if (statsMemory && nowMs() - statsMemory.at < statsCacheMs) return Promise.resolve(statsMemory.value);
    statsRun ??= (async () => {
      await rounds.fresh(roundsMaxAgeMs, roundsWaitMs);
      const featured = await currentRound();
      const found = [...new Set([...(await rounds.all()).map((r) => r.launcher), ...(featured ? [featured.launcher] : [])])];
      const read: (RoundState | null)[] = [];
      for (let i = 0; i < found.length; i += LIST_READS_AT_ONCE) {
        read.push(...(await Promise.all(found.slice(i, i + LIST_READS_AT_ONCE).map((l) => listState(l)))));
      }
      if (found.length > 0 ? read.every((s) => s === null) : !(await rounds.scanned())) return null;
      // The same rule as GET /rounds: a round created with another attester is left out (its
      // deposits, check-ins, launch and members), unless it is the featured round. A round that
      // could not be read stays in as unknown, so the sum says it is incomplete.
      const launchers: string[] = [];
      const states: (RoundState | null)[] = [];
      found.forEach((launcher, i) => {
        const s = read[i] ?? null;
        if (s && ourAttester !== null && s.attester !== ourAttester && featured?.launcher !== launcher) return;
        launchers.push(launcher);
        states.push(s);
      });
      const people = await Promise.all(launchers.map((l) => seenMembers(l)));
      const value: Counted = { launchers, states, totals: totals(states, people) };
      // A sum with a round missing is not kept: the next request tries that round again.
      statsMemory = value.totals.complete ? { at: nowMs(), value } : null;
      return value;
    })().finally(() => {
      statsRun = null;
    });
    return statsRun;
  }

  const walletMemory = new Map<string, { at: number; value: WalletTotals }>();

  /** One wallet across the rounds it was seen to join: two chain reads at most per such round. */
  async function countWallet(address: string, counted: Counted): Promise<WalletTotals | null> {
    const kept = walletMemory.get(address);
    if (kept && nowMs() - kept.at < listCacheMs) return kept.value;
    const mine: { launcher: string; state: RoundState }[] = [];
    for (const [i, launcher] of counted.launchers.entries()) {
      if (!(await seenMembers(launcher)).includes(address)) continue;
      const state = counted.states[i];
      if (!state) return null;
      mine.push({ launcher, state });
    }
    const today = dayIndexAt(now());
    const perRound: { daysOf: number; claimedQuote: bigint; quoteDecimals: number }[] = [];
    try {
      for (let i = 0; i < mine.length; i += LIST_READS_AT_ONCE) {
        perRound.push(
          ...(await Promise.all(
            mine.slice(i, i + LIST_READS_AT_ONCE).map(async ({ launcher, state }) => {
              const me = await chain.member(launcher, address, today);
              const claim = state.launched && state.vault ? await chain.claims(state.vault, address) : null;
              return { daysOf: me.daysOf, claimedQuote: claim?.claimedQuote ?? 0n, quoteDecimals: state.quoteDecimals };
            }),
          )),
        );
      }
    } catch {
      return null;
    }
    const value = walletTotals(address, perRound);
    if (walletMemory.size >= WALLET_MEMORY_SIZE) walletMemory.clear();
    walletMemory.set(address, { at: nowMs(), value });
    return value;
  }

  app.get("/stats", async (c) => {
    const counted = await countEverything();
    return counted ? c.json(counted.totals) : chainDown(c);
  });

  app.get("/stats/:address", async (c) => {
    const address = addr(c.req.param("address"));
    if (!address) return err(c, 400, "bad_address", "address must be an address");
    const counted = await countEverything();
    if (!counted) return chainDown(c);
    return c.json({ ...counted.totals, you: await countWallet(address, counted) });
  });

  // ── Check-in ──────────────────────────────────────────────────────────────
  // The member reports today's steps, signed with their own key. If the report passes the rules
  // the answer carries the attester's signature, and the member's wallet sends
  // CheckInLauncher.checkIn(dayIndex, attesterSignature) itself.

  const checkInRoute = (which: (c: Context) => Promise<Found>) => async (c: Context) => {
    const found = await which(c);
    if (found instanceof Response) return found;
    const { ref } = found;
    const b = await body(c);
    const address = addr(b.address);
    if (!address) return err(c, 400, "bad_address", "address must be an address");
    const report = checkReport({ steps: b.steps, source: b.source, minSteps, allowSelfReported });
    if (!report.ok) return err(c, report.status, report.code, report.message);
    const steps = parseSteps(b.steps)!;
    const source = b.source as Source;

    // Only today (UTC) is accepted, and the signed text names the day. A report signed for the day
    // before or after gets its own answer, because the usual cause is a request sent around
    // midnight UTC or a phone clock that is off.
    const today = dayIndexAt(now());
    const day = dayString(today);
    const text = (d: number) => (launcher: string) => checkInMessage(launcher, dayString(d), b.steps as string | number);
    if (!(await signedEitherForm(address, b.signature, text(today), ref.launcher))) {
      for (const other of [today - 1, today + 1]) {
        if (await signedEitherForm(address, b.signature, text(other), ref.launcher)) {
          return err(c, 422, "wrong_day", `only today (UTC) can be checked in, and today is ${day}`);
        }
      }
      return err(c, 401, "bad_signature", "signature does not match address");
    }

    if (!attester) return err(c, 503, "attester_disabled", "this server has no attester key, so it cannot sign check-ins");
    let round: RoundState, me: MemberState;
    try {
      [round, me] = await Promise.all([chain.round(ref.launcher), chain.member(ref.launcher, address, today)]);
    } catch {
      return chainDown(c);
    }
    if (round.attester !== attester.address.toLowerCase()) {
      return err(c, 503, "attester_mismatch", "this round was created with a different attester; this server cannot sign for it");
    }
    if (round.launched) return err(c, 409, "round_launched", "the round has launched; check-ins are closed");
    if (now() > round.deadline) return err(c, 409, "round_closed", "the round's deadline has passed");
    if (!me.member) return err(c, 403, "not_a_member", "this wallet has not joined the round");
    await remember(ref.launcher, address);
    if (me.checkedIn) return err(c, 409, "already_checked_in", "today's check-in is already on chain");

    // One accepted check-in per member per day. Asking again (the transaction failed, the app was
    // closed) returns the same signature and leaves the first accepted report as it is.
    const existing = (await store.getCheckIns(ref.launcher)).find((d) => d.address === address && d.day === day);
    if (!existing) {
      const accepted: CheckIn = { address, day, dayIndex: today, steps, source, selfReported: source === "self", at: now() };
      await store.putCheckIn(ref.launcher, accepted);
    }
    const attesterSignature = await attester.signCheckIn(ref.launcher, address, today);
    return c.json({ day, dayIndex: today, attesterSignature, repeat: Boolean(existing) });
  };
  app.post("/checkin", checkInRoute(featuredRound));
  app.post("/rounds/:launcher/checkin", checkInRoute(namedRound));

  // ── Faucet ────────────────────────────────────────────────────────────────
  // Sends a new wallet a little test BNB once, for gas. It does not send test USD: getting test
  // dollars for the deposit is a step the member takes in the app. Requests are handled one at a
  // time so the limits cannot be raced.
  let faucetQueue: Promise<unknown> = Promise.resolve();

  app.post("/faucet", async (c) => {
    const b = await body(c);
    const address = addr(b.address);
    if (!address) return err(c, 400, "bad_address", "address must be an address");
    if (!(await signedEitherForm(address, b.signature, faucetMessage, address))) {
      return err(c, 401, "bad_signature", "signature does not match address");
    }

    const refuse = (reason: string) => ({ funded: false, bnbTx: null, reason, message: FAUCET_MESSAGES[reason] }) as const;
    const wallet = chain.faucet;
    if (!faucetEnabled || !wallet) return c.json(refuse("faucet_disabled"));
    const ip = clientIp(c);

    const run = faucetQueue.then(async () => {
      const refusal = faucetRefusal(await store.getFaucetDrips(), address, ip, now(), faucetPerIpPerHour);
      if (refusal) return refuse(refusal);
      let balance: bigint, reserve: bigint;
      try {
        [balance, reserve] = await Promise.all([chain.balanceOf(address), wallet.balance()]);
      } catch {
        return refuse("chain_unavailable");
      }
      if (balance >= MIN_BALANCE_WEI) return refuse("has_funds");
      if (reserve < faucetDripWei + RESERVE_WEI) return refuse("faucet_empty");

      const drip: FaucetDrip = { address, ip, at: now(), bnbTx: null };
      try {
        drip.bnbTx = await wallet.sendBnb(address, faucetDripWei);
      } catch {
        // Nothing left the wallet. Remembered for the per-IP limit only; the address may ask again.
        await store.putFaucetDrip({ ...drip, failed: true });
        return refuse("send_failed");
      }
      await store.putFaucetDrip(drip);
      return { funded: true, bnbTx: drip.bnbTx };
    });
    faucetQueue = run.catch(() => undefined);
    return c.json(await run);
  });

  // ── Admin ─────────────────────────────────────────────────────────────────

  /** Returns an error response unless the request carries the admin token. */
  const adminOnly = (c: Context) => {
    if (!adminToken) return err(c, 503, "admin_disabled", "ADMIN_TOKEN is not configured");
    if (!sameToken(c.req.header("authorization") ?? "", `Bearer ${adminToken}`)) {
      return err(c, 401, "unauthorized", "admin token required");
    }
    return null;
  };

  // Points this server at a round. It changes which Launcher the routes above read and sign for;
  // it sends nothing to the chain.
  app.post("/admin/round", async (c) => {
    const denied = adminOnly(c);
    if (denied) return denied;
    const b = await body(c);
    const launcher = addr(b.launcher);
    if (!launcher) return err(c, 400, "bad_launcher", "launcher must be an address");
    const name = typeof b.name === "string" ? b.name.trim() : "";
    if (name.length > 80) return err(c, 400, "bad_name", "name must be at most 80 characters");

    let state: RoundState;
    try {
      state = await chain.round(launcher);
    } catch {
      return err(c, 503, "chain_unavailable", "could not read that launcher on chain; nothing was changed");
    }
    if (ourAttester !== null && state.attester !== ourAttester) {
      return err(c, 409, "attester_mismatch", "that round was created with a different attester; nothing was changed");
    }
    const ref: RoundRef = { launcher, name, setAt: now() };
    await store.putRound(ref);
    return c.json(roundView(ref, state));
  });

  return app;
}
