// Builds the app from environment variables.
import { Hono, type Context } from "hono";
import { formatEther, isAddress, parseEther } from "viem";
import { createApp } from "./app.js";
import { CHAIN_ID, createAttester, type Attester } from "./attest.js";
import { createChain } from "./chain.js";
import { DRIP_BNB_WEI, MAX_DRIP_BNB_WEI, MAX_PER_IP_PER_HOUR, PER_IP_PER_HOUR } from "./faucet.js";
import {
  DEFAULT_ORIGIN_CHECK_SECONDS,
  DEFAULT_ORIGIN_SOURCE_URL,
  createOriginAnnouncer,
  hostFromSource,
  isPlainHost,
  type OriginAnnouncer,
} from "./origin.js";
import { DEFAULT_CHUNK_BLOCKS, createRounds, type Rounds } from "./rounds.js";
import { DEFAULT_MIN_STEPS, MAX_STEPS } from "./rules.js";
import { dayLabel, seasonFromEnv, type Season } from "./season.js";
import { LocalStore } from "./store.js";

/** The key as viem wants it, or an error that names the variable and does not repeat the value. */
function readKey(name: string, value: string | undefined): `0x${string}` | undefined {
  if (!value) return undefined;
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error(`${name} must be a 32-byte hex key.`);
  return key as `0x${string}`;
}

/** FAUCET_DRIP_BNB: test BNB per wallet as a decimal ("0.03"), in wei. */
export function dripFromEnv(value: string | undefined): bigint {
  if (!value) return DRIP_BNB_WEI;
  const wei = /^\d+(\.\d{1,18})?$/.test(value.trim()) ? parseEther(value.trim()) : -1n;
  if (wei <= 0n || wei > MAX_DRIP_BNB_WEI) {
    throw new Error(`FAUCET_DRIP_BNB must be an amount of test BNB above 0 and at most ${formatEther(MAX_DRIP_BNB_WEI)}, such as 0.03.`);
  }
  return wei;
}

/** Our CheckInLauncherFactory on BSC testnet and the block it was deployed in
 *  (contracts/deployments/bsc-testnet.json). Every round is one Launcher this factory created. */
export const DEFAULT_FACTORY = "0x2A872200B83dD025977d785cDE05356d23eA4153";
export const DEFAULT_FACTORY_FROM_BLOCK = 144_816_444;
/** How often the server looks for newly created rounds, unless ROUNDS_REFRESH_SECONDS says otherwise. */
export const DEFAULT_ROUNDS_REFRESH_SECONDS = 10;

function wholeNumber(name: string, value: string | undefined, fallback: number, min: number, max: number): number {
  const n = Number(value || fallback);
  if (!Number.isInteger(n) || n < min || n > max) throw new Error(`${name} must be a whole number from ${min} to ${max}.`);
  return n;
}

export interface Server {
  /** The API, served at the root and again under /api. */
  app: Hono;
  /** The rounds found on chain. The entry point refreshes it every `refreshSeconds`. */
  rounds: Rounds;
  refreshSeconds: number;
  /** Writes this server's host to the OriginRegistry. Undefined unless ORIGIN_REGISTRY and the
   *  attester key are set. The entry point starts it. */
  origin?: OriginAnnouncer;
  /** The faucet's settings as read from the environment. */
  faucet: { dripWei: bigint; perIpPerHour: number; wallet: string | null };
  /** The Season read from SEASON_*; undefined without SEASON_LAUNCHERS. */
  season?: Season;
}

export const appFromEnv = (env: NodeJS.ProcessEnv = process.env) => serverFromEnv(env).app;

export function serverFromEnv(env: NodeJS.ProcessEnv = process.env): Server {
  if (!env.RPC_URL) throw new Error("Set RPC_URL to a BSC testnet RPC. The round is read from the chain.");
  if (Number(env.CHAIN_ID || CHAIN_ID) !== CHAIN_ID) {
    throw new Error(`CHAIN_ID must be ${CHAIN_ID} (BSC testnet). This server runs on testnet only.`);
  }

  // The attester key signs check-ins (it must be the round's attester) and sends setOrigin. Its
  // wallet also pays the faucet's gas transfers unless FAUCET_PRIVATE_KEY gives the faucet a wallet
  // of its own. VERIFIER_PRIVATE_KEY is the name the earlier server used for the attester key.
  const key = readKey("ATTESTER_PRIVATE_KEY", env.ATTESTER_PRIVATE_KEY || env.VERIFIER_PRIVATE_KEY);
  const faucetKey = readKey("FAUCET_PRIVATE_KEY", env.FAUCET_PRIVATE_KEY);
  let attester: Attester | undefined;
  if (key) attester = createAttester(key);
  else console.warn(`No ATTESTER_PRIVATE_KEY: check-ins cannot be signed${faucetKey ? "" : " and the faucet is off"}.`);
  const dripWei = dripFromEnv(env.FAUCET_DRIP_BNB);
  const perIpPerHour = wholeNumber("FAUCET_PER_IP_PER_HOUR", env.FAUCET_PER_IP_PER_HOUR, PER_IP_PER_HOUR, 1, MAX_PER_IP_PER_HOUR);

  // Where this server can be reached: written to the OriginRegistry when ORIGIN_REGISTRY is set.
  const registry = env.ORIGIN_REGISTRY || undefined;
  if (registry && !isAddress(registry, { strict: false })) throw new Error("ORIGIN_REGISTRY must be an address.");
  const originHost = env.ORIGIN_HOST?.trim().toLowerCase() || undefined;
  if (originHost && !isPlainHost(originHost)) throw new Error("ORIGIN_HOST must be a plain hostname, such as name.trycloudflare.com.");
  const originSeconds = wholeNumber("ORIGIN_CHECK_SECONDS", env.ORIGIN_CHECK_SECONDS, DEFAULT_ORIGIN_CHECK_SECONDS, 10, 3600);
  const originSource = env.ORIGIN_SOURCE_URL || DEFAULT_ORIGIN_SOURCE_URL;
  if (!/^https?:\/\//.test(originSource)) throw new Error("ORIGIN_SOURCE_URL must be an http(s) address.");

  // Where rounds are found: the creation events of our factory, from the block it was deployed in.
  const factory = env.LAUNCHER_FACTORY || DEFAULT_FACTORY;
  if (!isAddress(factory, { strict: false })) throw new Error("LAUNCHER_FACTORY must be an address.");
  const fromBlock = wholeNumber("FACTORY_FROM_BLOCK", env.FACTORY_FROM_BLOCK, DEFAULT_FACTORY_FROM_BLOCK, 0, Number.MAX_SAFE_INTEGER);
  const chunkBlocks = wholeNumber("LOG_CHUNK_BLOCKS", env.LOG_CHUNK_BLOCKS, DEFAULT_CHUNK_BLOCKS, 1, 1_000_000);
  const refreshSeconds = wholeNumber("ROUNDS_REFRESH_SECONDS", env.ROUNDS_REFRESH_SECONDS, DEFAULT_ROUNDS_REFRESH_SECONDS, 2, 3600);
  const chain = createChain(env.RPC_URL, key, factory, { faucetKey, originRegistry: registry });
  let origin: OriginAnnouncer | undefined;
  if (registry && chain.origin) {
    origin = createOriginAnnouncer({
      registry: chain.origin,
      host: originHost ? async () => originHost : () => hostFromSource(originSource),
      intervalMs: originSeconds * 1000,
    });
  } else if (registry) console.warn("ORIGIN_REGISTRY is set but the origin is not announced: it needs ATTESTER_PRIVATE_KEY.");

  const launcher = env.CURRENT_LAUNCHER;
  if (launcher && !isAddress(launcher, { strict: false })) throw new Error("CURRENT_LAUNCHER must be an address.");

  const minSteps = Number(env.MIN_STEPS || DEFAULT_MIN_STEPS);
  if (!Number.isInteger(minSteps) || minSteps < 1 || minSteps > MAX_STEPS) {
    throw new Error(`MIN_STEPS must be a whole number from 1 to ${MAX_STEPS}.`);
  }
  const allowSelfReported = env.ALLOW_SELF_REPORTED === "true";
  if (allowSelfReported) console.warn("ALLOW_SELF_REPORTED=true: typed-in step counts are accepted. Testnet demo only.");

  // A Season (SEASON_*): one set of dates for the rounds in SEASON_LAUNCHERS. Check-ins for those
  // rounds are signed on the Season's days only. Without SEASON_LAUNCHERS no round is gated.
  const season = seasonFromEnv(env);
  if (season) {
    console.log(
      `${season.name}: ${season.launchers.length} round(s); check-ins signed from ${dayLabel(season.startDay)} to ${dayLabel(season.endDay)} (UTC days) only.`,
    );
    if (launcher && season.launchers.includes(launcher.toLowerCase())) {
      console.warn("CURRENT_LAUNCHER is a Season round: the featured round refuses check-ins outside the Season's days.");
    }
  } else if (Object.keys(env).some((name) => name.startsWith("SEASON_") && env[name]?.trim())) {
    console.warn("SEASON_* is set but SEASON_LAUNCHERS is empty: no round is gated by a Season.");
  }

  const faucetEnabled = env.FAUCET_ENABLED === "true";
  if (faucetEnabled && !chain.faucet) {
    console.warn("FAUCET_ENABLED=true but the faucet is off: it needs FAUCET_PRIVATE_KEY or ATTESTER_PRIVATE_KEY.");
  }

  const trustProxy = env.TRUST_PROXY === "true";
  const store = new LocalStore(env.DATA_FILE || "./data/store.json");
  // A lookup of a launcher nobody has seen starts a scan at most every 750 ms, however often it is asked.
  const rounds = createRounds({ store, factory: chain.factory, fromBlock, chunkBlocks, minGapMs: 750 });
  const api = createApp({
    store,
    chain,
    attester,
    adminToken: env.ADMIN_TOKEN || undefined,
    defaultRound: launcher ? { launcher, name: env.CURRENT_ROUND_NAME || undefined } : undefined,
    minSteps,
    allowSelfReported,
    faucetEnabled,
    clientIp: (c) => clientIp(c, trustProxy),
    faucetDripWei: dripWei,
    faucetPerIpPerHour: perIpPerHour,
    originHealth: origin?.health,
    flapTokenUrl: env.FLAP_TOKEN_URL || undefined,
    rounds,
    // With the entry point's timer running the list is never this old; without one (tests, another
    // host) GET /rounds scans by itself.
    roundsMaxAgeMs: refreshSeconds * 2000,
    season,
  });
  // The web app calls this server on its own origin under /api, so the same routes are also served
  // there. A reverse proxy can then pass /api/* through unchanged or strip the prefix; both work.
  return {
    app: new Hono().route("/api", api).route("/", api),
    rounds,
    refreshSeconds,
    origin,
    faucet: { dripWei, perIpPerHour, wallet: chain.faucet?.address ?? null },
    season,
  };
}

/**
 * Who is asking, for the faucet's per-IP limit. Behind a reverse proxy (TRUST_PROXY=true) it is the
 * last address in X-Forwarded-For, the one the proxy itself added; a client cannot forge that one.
 * Otherwise it is the socket's address. Never trust the header when clients can reach this server
 * directly.
 */
function clientIp(c: Context, trustProxy: boolean): string {
  if (trustProxy) {
    const forwarded = c.req.header("x-forwarded-for")?.split(",").pop()?.trim();
    if (forwarded) return forwarded;
  }
  const env = c.env as { incoming?: { socket?: { remoteAddress?: string } } } | undefined;
  return env?.incoming?.socket?.remoteAddress ?? "unknown";
}
