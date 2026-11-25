// Builds the app from environment variables.
import { Hono, type Context } from "hono";
import { isAddress } from "viem";
import { createApp } from "./app.js";
import { CHAIN_ID, createAttester, type Attester } from "./attest.js";
import { createChain } from "./chain.js";
import { DEFAULT_MIN_STEPS, MAX_STEPS } from "./rules.js";
import { LocalStore } from "./store.js";

/** The key as viem wants it, or an error that does not repeat the value. */
function readKey(value: string | undefined): `0x${string}` | undefined {
  if (!value) return undefined;
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("ATTESTER_PRIVATE_KEY must be a 32-byte hex key.");
  return key as `0x${string}`;
}

export function appFromEnv(env: NodeJS.ProcessEnv = process.env) {
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
  const chain = createChain(env.RPC_URL, key);

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
  const api = createApp({
    store: new LocalStore(env.DATA_FILE || "./data/store.json"),
    chain,
    attester,
    adminToken: env.ADMIN_TOKEN || undefined,
    defaultRound: launcher ? { launcher, name: env.CURRENT_ROUND_NAME || undefined } : undefined,
    minSteps,
    allowSelfReported,
    faucetEnabled,
    clientIp: (c) => clientIp(c, trustProxy),
    flapTokenUrl: env.FLAP_TOKEN_URL || undefined,
  });
  // The web app calls this server on its own origin under /api, so the same routes are also served
  // there. A reverse proxy can then pass /api/* through unchanged or strip the prefix; both work.
  return new Hono().route("/api", api).route("/", api);
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
