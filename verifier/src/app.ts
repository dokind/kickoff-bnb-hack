// The HTTP API. Everything it needs is passed in, so tests can run it with fakes.
//
// What this server does for a round: it accepts a member's daily report (steps from the phone's
// health data, or typed in on the web when that is allowed) and signs the check-in the contract
// requires. It also remembers the accepted days (for streaks), relays what the chain says about
// the round, and hands out gas money. It cannot launch early, block a launch, choose who is paid
// beyond signing daily check-ins, or move funds. Check-ins are attested, not proven.
import { createHash, timingSafeEqual } from "node:crypto";
import { Hono, type Context } from "hono";
import { cors } from "hono/cors";
import { formatUnits, getAddress, isAddress, recoverMessageAddress } from "viem";
import type { Attester } from "./attest.js";
import type { Chain, ClaimState, MemberState, RoundState } from "./chain.js";
import { dayIndexAt, dayString, streaks } from "./days.js";
import { DRIP_BNB_WEI, FAUCET_MESSAGES, MIN_BALANCE_WEI, RESERVE_WEI, faucetRefusal } from "./faucet.js";
import { SERVICE_NAME, checkInMessage, faucetMessage } from "./product.js";
import { DEFAULT_MIN_STEPS, checkReport, parseSteps } from "./rules.js";
import type { Store } from "./store.js";
import type { CheckIn, FaucetDrip, RoundRef, Source } from "./types.js";

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
  /** Address of a token's page on Flap, with `{token}` where the token address goes. */
  flapTokenUrl?: string;
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
  now = () => Math.floor(Date.now() / 1000),
  defaultRound,
  minSteps = DEFAULT_MIN_STEPS,
  allowSelfReported = false,
  faucetEnabled = false,
  clientIp = () => "unknown",
  flapTokenUrl,
}: Deps) {
  const app = new Hono();
  // The web app calls this server from a browser, so every response carries CORS headers and
  // OPTIONS preflights are answered here (204) before any route runs.
  app.use("*", cors({ origin: "*", allowMethods: ["GET", "POST", "OPTIONS"], allowHeaders: ["Content-Type"] }));

  type Status = 400 | 401 | 403 | 404 | 409 | 422 | 503;
  const err = (c: Context, status: Status, error: string, message: string) => c.json({ error, message }, status);
  const noRound = (c: Context) => err(c, 404, "no_round", "no round is set on this server");
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

  const ourAttester = attester?.address.toLowerCase() ?? null;

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

  app.get("/", (c) => c.json({ service: SERVICE_NAME, ok: true }));

  // ── The round ─────────────────────────────────────────────────────────────

  app.get("/round", async (c) => {
    const ref = await currentRound();
    if (!ref) return noRound(c);
    try {
      return c.json(roundView(ref, await chain.round(ref.launcher)));
    } catch {
      return chainDown(c);
    }
  });

  app.get("/me/:address", async (c) => {
    const address = addr(c.req.param("address"));
    if (!address) return err(c, 400, "bad_address", "address must be an address");
    const ref = await currentRound();
    if (!ref) return noRound(c);
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
  });

  app.get("/members", async (c) => {
    const ref = await currentRound();
    if (!ref) return noRound(c);
    const today = dayIndexAt(now());
    const checkIns = await store.getCheckIns(ref.launcher);
    // The Launcher has no list of members to read, so this is everyone this server has seen as a
    // member: a wallet appears after its first GET /me or POST /checkin as a member.
    const addresses = [...new Set([...(await store.getMembers(ref.launcher)), ...checkIns.map((d) => d.address)])];
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
  });

  // ── Check-in ──────────────────────────────────────────────────────────────
  // The member reports today's steps, signed with their own key. If the report passes the rules
  // the answer carries the attester's signature, and the member's wallet sends
  // CheckInLauncher.checkIn(dayIndex, attesterSignature) itself.

  app.post("/checkin", async (c) => {
    const ref = await currentRound();
    if (!ref) return noRound(c);
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
  });

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
      const refusal = faucetRefusal(await store.getFaucetDrips(), address, ip, now());
      if (refusal) return refuse(refusal);
      let balance: bigint, reserve: bigint;
      try {
        [balance, reserve] = await Promise.all([chain.balanceOf(address), wallet.balance()]);
      } catch {
        return refuse("chain_unavailable");
      }
      if (balance >= MIN_BALANCE_WEI) return refuse("has_funds");
      if (reserve < DRIP_BNB_WEI + RESERVE_WEI) return refuse("faucet_empty");

      const drip: FaucetDrip = { address, ip, at: now(), bnbTx: null };
      try {
        drip.bnbTx = await wallet.sendBnb(address, DRIP_BNB_WEI);
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
