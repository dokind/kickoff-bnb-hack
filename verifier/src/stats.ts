// Totals across every round, for GET /stats. Pure functions, no I/O.
//
// The numbers are the chain's own (check-ins, deposits, launches) plus one this server keeps: the
// wallets it has seen as members. Nothing here names a round, so an unlisted round can be counted
// without being shown.
import { formatUnits } from "viem";
import type { RoundState } from "./chain.js";

/** Every amount is added up at this many decimals, whatever the round's quote token uses. */
const DECIMALS = 18;

const scaled = (amount: bigint, decimals: number): bigint =>
  decimals <= DECIMALS ? amount * 10n ** BigInt(DECIMALS - decimals) : amount / 10n ** BigInt(decimals - DECIMALS);

export interface Totals {
  /** Rounds counted, listed or not. */
  rounds: number;
  /** Unique wallets this server has seen as a member of any of them. */
  people: number;
  /** Check-ins on chain, all rounds together. */
  checkIns: number;
  /** Deposits the rounds hold or launched with, in whole quote tokens. */
  deposited: string;
  /** Rounds whose token launched. */
  launched: number;
  /** False when a round could not be read: the totals leave it out and are lower than the truth. */
  complete: boolean;
  raw: { deposited: string };
}

/**
 * Adds the rounds up. `states` holds one entry per round; null is a round that could not be read.
 * `people` is the wallets seen as members, one list per round: a wallet in two rounds is one person.
 */
export function totals(states: (RoundState | null)[], people: string[][]): Totals {
  let checkIns = 0;
  let launched = 0;
  let deposited = 0n;
  for (const s of states) {
    if (!s) continue;
    checkIns += s.totalCheckIns;
    if (s.launched) launched += 1;
    deposited += scaled(s.totalDeposits, s.quoteDecimals);
  }
  return {
    rounds: states.length,
    people: new Set(people.flat()).size,
    checkIns,
    deposited: formatUnits(deposited, DECIMALS),
    launched,
    complete: states.every((s) => s !== null),
    raw: { deposited: deposited.toString() },
  };
}

/** One wallet across the rounds it joined. */
export interface WalletTotals {
  address: string;
  /** Rounds this server has seen the wallet as a member of. */
  rounds: number;
  /** Days it checked in on chain, all those rounds together. */
  days: number;
  /** Quote token it has claimed from the vaults of the launched ones, in whole tokens. */
  claimed: string;
  raw: { claimed: string };
}

export function walletTotals(address: string, perRound: { daysOf: number; claimedQuote: bigint; quoteDecimals: number }[]): WalletTotals {
  let days = 0;
  let claimed = 0n;
  for (const r of perRound) {
    days += r.daysOf;
    claimed += scaled(r.claimedQuote, r.quoteDecimals);
  }
  return { address, rounds: perRound.length, days, claimed: formatUnits(claimed, DECIMALS), raw: { claimed: claimed.toString() } };
}
