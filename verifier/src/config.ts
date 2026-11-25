// Builds the app from environment variables.
import { Hono, type Context } from "hono";
import { isAddress } from "viem";
import { createApp } from "./app.js";
import { CHAIN_ID, createAttester, type Attester } from "./attest.js";
import { createChain } from "./chain.js";
import { DEFAULT_CHUNK_BLOCKS, createRounds, type Rounds } from "./rounds.js";
import { DEFAULT_MIN_STEPS, MAX_STEPS } from "./rules.js";
import { LocalStore } from "./store.js";

/** The key as viem wants it, or an error that does not repeat the value. */
function readKey(value: string | undefined): `0x${string}` | undefined {
  if (!value) return undefined;
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("ATTESTER_PRIVATE_KEY must be a 32-byte hex key.");
  return key as `0x${string}`;
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
}

export const appFromEnv = (env: NodeJS.ProcessEnv = process.env) => serverFromEnv(env).app;

export function serverFromEnv(env: NodeJS.ProcessEnv = process.env): Server {
  if (!env.RPC_URL) throw new Error("Set RPC_URL to a BSC testnet RPC. The round is read from the chain.");
  if (Number(env.CHAIN_ID || CHAIN_ID) !== CHAIN_ID) {
    throw new Error(`CHAIN_ID must be ${CHAIN_ID} (BSC testnet). This server runs on testnet only.`);
  }

  // One key, two jobs: it signs check-ins (it must be the round's attester) and its wallet pays the
  // faucet's gas transfers. VERIFIER_PRIVATE_KEY is the name the earlier server used for the same key.
  const key = readKey(env.ATTESTER_PRIVATE_KEY || env.VERIFIER_PRIVATE_KEY);
  let attester: Attester | undefined;
  if (key) attester = createAttester(key);
  else console.warn("No ATTESTER_PRIVATE_KEY: check-ins cannot be signed and the faucet is off.");

  // Where rounds are found: the creation events of our factory, from the block it was deployed in.
  const factory = env.LAUNCHER_FACTORY || DEFAULT_FACTORY;
  if (!isAddress(factory, { strict: false })) throw new Error("LAUNCHER_FACTORY must be an address.");
  const fromBlock = wholeNumber("FACTORY_FROM_BLOCK", env.FACTORY_FROM_BLOCK, DEFAULT_FACTORY_FROM_BLOCK, 0, Number.MAX_SAFE_INTEGER);
  const chunkBlocks = wholeNumber("LOG_CHUNK_BLOCKS", env.LOG_CHUNK_BLOCKS, DEFAULT_CHUNK_BLOCKS, 1, 1_000_000);
  const refreshSeconds = wholeNumber("ROUNDS_REFRESH_SECONDS", env.ROUNDS_REFRESH_SECONDS, DEFAULT_ROUNDS_REFRESH_SECONDS, 2, 3600);
  const chain = createChain(env.RPC_URL, key, factory);

  const launcher = env.CURRENT_LAUNCHER;
  if (launcher && !isAddress(launcher, { strict: false })) throw new Error("CURRENT_LAUNCHER must be an address.");

  const minSteps = Number(env.MIN_STEPS || DEFAULT_MIN_STEPS);
  if (!Number.isInteger(minSteps) || minSteps < 1 || minSteps > MAX_STEPS) {
    throw new Error(`MIN_STEPS must be a whole number from 1 to ${MAX_STEPS}.`);
  }
  const allowSelfReported = env.ALLOW_SELF_REPORTED === "true";
  if (allowSelfReported) console.warn("ALLOW_SELF_REPORTED=true: typed-in step counts are accepted. Testnet demo only.");

  const faucetEnabled = env.FAUCET_ENABLED === "true";
  if (faucetEnabled && !chain.faucet) console.warn("FAUCET_ENABLED=true but the faucet is off: it needs ATTESTER_PRIVATE_KEY.");

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
    flapTokenUrl: env.FLAP_TOKEN_URL || undefined,
    rounds,
    // With the entry point's timer running the list is never this old; without one (tests, another
    // host) GET /rounds scans by itself.
    roundsMaxAgeMs: refreshSeconds * 2000,
  });
  // The web app calls this server on its own origin under /api, so the same routes are also served
  // there. A reverse proxy can then pass /api/* through unchanged or strip the prefix; both work.
  return { app: new Hono().route("/api", api).route("/", api), rounds, refreshSeconds };
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
