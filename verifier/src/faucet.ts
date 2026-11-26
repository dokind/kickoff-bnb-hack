// Gas faucet policy. A new wallet gets a little test BNB once, so nobody has to fund a wallet by
// hand before the first transaction. It sends gas money only: test USD for the deposit is a step
// the member takes in the app (anyone can mint it on BSC testnet). Pure functions, no I/O.
import type { FaucetDrip } from "./types.js";

/** Test BNB sent per wallet unless FAUCET_DRIP_BNB says otherwise: 0.03. At 1 gwei that covers
 *  approve, join, a round of daily check-ins, a claim and even the launch transaction (about 0.007). */
export const DRIP_BNB_WEI = 30_000_000_000_000_000n;
/** FAUCET_DRIP_BNB may be at most this much (1 test BNB). */
export const MAX_DRIP_BNB_WEI = 1_000_000_000_000_000_000n;
/** A wallet that already holds this much test BNB (0.002) is not funded. */
export const MIN_BALANCE_WEI = 2_000_000_000_000_000n;
/** The faucet stops for good after this many wallets. */
export const GLOBAL_CAP = 200;
/** Wallets one network (IP address) may get funded per hour, unless FAUCET_PER_IP_PER_HOUR says
 *  otherwise. A room of people on one Wi-Fi shares one IP address. */
export const PER_IP_PER_HOUR = 5;
/** FAUCET_PER_IP_PER_HOUR may be at most this. */
export const MAX_PER_IP_PER_HOUR = 1000;
/** Test BNB the server wallet keeps back (0.05), so the operator can still send a transaction from it. */
export const RESERVE_WEI = 50_000_000_000_000_000n;

export type FaucetRefusal = "already_funded" | "cap_reached" | "rate_limited";

/**
 * The checks that need only this server's own records, in the order they are applied. A drip whose
 * transfer failed (`failed`) does not count as funded and does not use up the global cap, but it
 * does count against the per-IP limit.
 */
export function faucetRefusal(
  drips: FaucetDrip[],
  address: string,
  ip: string,
  now: number,
  perIpPerHour: number = PER_IP_PER_HOUR,
): FaucetRefusal | null {
  const done = drips.filter((d) => !d.failed);
  if (done.some((d) => d.address === address)) return "already_funded";
  if (done.length >= GLOBAL_CAP) return "cap_reached";
  if (drips.filter((d) => d.ip === ip && d.at > now - 3600).length >= perIpPerHour) return "rate_limited";
  return null;
}

/**
 * How many more wallets a faucet wallet holding `balance` can fund at `dripWei` each before it
 * refuses with faucet_empty (it pays only while balance >= drip + RESERVE_WEI). An upper bound: each
 * transfer's own gas comes out of the same balance.
 */
export function walletsLeft(balance: bigint, dripWei: bigint): number {
  if (dripWei <= 0n || balance < dripWei + RESERVE_WEI) return 0;
  return Number((balance - RESERVE_WEI) / dripWei);
}

export const FAUCET_MESSAGES: Record<string, string> = {
  faucet_disabled: "the faucet is switched off on this server",
  already_funded: "this wallet was already funded once",
  cap_reached: "the faucet has reached its total limit",
  rate_limited: "too many requests from this network in the last hour",
  has_funds: "this wallet already holds enough test BNB",
  faucet_empty: "the faucet wallet is out of test BNB",
  chain_unavailable: "could not reach the chain; nothing was sent",
  send_failed: "the transfer could not be sent; try again",
};
