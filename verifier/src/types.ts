/** Where a day's step count came from. "self" means the member typed it in (testnet demo only). */
export type Source = "healthkit" | "healthconnect" | "self";

/** All addresses are stored lower-case. All times are unix seconds. */

/** The round this server currently serves: one CheckInLauncher. */
export interface RoundRef {
  launcher: string;
  /** Display name. Empty means "use the name stored in the Launcher". */
  name: string;
  setAt: number;
}

/** A daily report this server accepted and signed. At most one per member per day per round. */
export interface CheckIn {
  address: string;
  /** YYYY-MM-DD (UTC). */
  day: string;
  /** The contract's day number: unix time / 86400. */
  dayIndex: number;
  steps: number;
  source: Source;
  /** True when the member typed the number in instead of the phone reading it from health data. */
  selfReported: boolean;
  at: number;
}

/** One faucet payout. At most one that did not fail per address. */
export interface FaucetDrip {
  address: string;
  /** Network address the request came from, for the per-IP limit. */
  ip: string;
  at: number;
  bnbTx: string | null;
  /** The transfer could not be sent, so the wallet may ask again. */
  failed?: boolean;
}

/** A CheckInLauncher created by our factory, as the factory's creation event says. */
export interface CreatedRound {
  launcher: string;
  /** The wallet that called the Flap Portal to create the round. It has no rights on the round. */
  creator: string;
  /** Block of the creation event. */
  block: number;
  /** That block's timestamp. */
  createdAt: number;
}

/** What the scan of the factory's creation events has found so far. */
export interface Discovery {
  /** The factory that was scanned. Another factory address starts a new scan. */
  factory: string;
  /** The first block not scanned yet. */
  nextBlock: number;
  rounds: CreatedRound[];
}

/**
 * What a round's creator chose about the app's public list. "Unlisted" means only that the round is
 * left out of GET /rounds: anyone with its link, or anyone reading the chain, can still find it.
 */
export interface Listing {
  unlisted: boolean;
  /** The creator, who signed the choice. */
  by: string;
  at: number;
}
