// The attester's signature: the one thing this server contributes to a round on chain.
//
// CheckInLauncher.checkIn(day, signature) accepts a check-in only with the round's attester's
// signature over (chain id, launcher, wallet, day). This server holds that key and signs once it
// has accepted a member's report for the day. The member's own wallet then sends the transaction.
//
// What the key can do: let a member of a round record a check-in for today (or, on chain, the day
// before). What it cannot do: launch early, block a launch, move or withdraw funds, or change who
// is paid in any way other than by signing or not signing daily check-ins.
//
// A check-in is attested, not proven: the step count comes from the member's phone (or is typed in
// on the web when self-reported check-ins are allowed) and this server cannot verify it.
import { encodeAbiParameters, keccak256, parseAbiParameters } from "viem";
import { privateKeyToAccount } from "viem/accounts";

type Hex = `0x${string}`;

/** BSC testnet. The only chain this server signs for. */
export const CHAIN_ID = 97;

/**
 * inner = keccak256(abi.encode(uint256 chainId, address launcher, address wallet, uint256 day)).
 * Four 32-byte words, not packed. `day` is the contract's day number (unix time / 86400).
 */
export function checkInInner(chainId: number, launcher: string, wallet: string, dayIndex: number): Hex {
  return keccak256(
    encodeAbiParameters(parseAbiParameters("uint256, address, address, uint256"), [
      BigInt(chainId),
      launcher.toLowerCase() as Hex,
      wallet.toLowerCase() as Hex,
      BigInt(dayIndex),
    ]),
  );
}

export interface Attester {
  /** Address of the signing key. A round must have been created with this address as its attester. */
  address: string;
  /**
   * The signature CheckInLauncher.checkIn requires: personal_sign (EIP-191) of the 32 raw bytes of
   * `checkInInner`, as 65 bytes r ++ s ++ v with v = 27 or 28.
   */
  signCheckIn(launcher: string, wallet: string, dayIndex: number): Promise<Hex>;
}

/** The key stays inside the returned object; it is never logged or returned. */
export function createAttester(privateKey: string, chainId: number = CHAIN_ID): Attester {
  const account = privateKeyToAccount(privateKey as Hex);
  return {
    address: account.address,
    signCheckIn: (launcher, wallet, dayIndex) =>
      account.signMessage({ message: { raw: checkInInner(chainId, launcher, wallet, dayIndex) } }),
  };
}
