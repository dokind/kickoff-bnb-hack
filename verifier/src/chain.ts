// Chain access with viem: reads of a round (CheckInLauncher and, after the launch, its
// StreakVault) and the faucet's gas transfers. BSC testnet only.
//
// This server sends no transaction to the Launcher or the vault. Members send join, checkIn,
// launch, refund and claim themselves; the only transactions sent from here are the faucet's.
import { createPublicClient, createWalletClient, http, parseAbi, zeroAddress } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet } from "viem/chains";

type Address = `0x${string}`;

// BSC testnet reports a base fee of 0, so fee estimation can return 1 wei and the transaction never
// gets mined. Every transaction is sent as a legacy one at a fixed 1 gwei with an explicit gas limit.
const TESTNET_GAS_PRICE = 1_000_000_000n;
const TRANSFER_GAS = 21_000n;
const NONCE_MEMORY_MS = 60_000;

// Minimal fragments for the functions this server reads (full ABIs live in ../contracts/abi).
export const launcherAbi = parseAbi([
  "function name() view returns (string)",
  "function quoteToken() view returns (address)",
  "function deposit() view returns (uint256)",
  "function liquidityBps() view returns (uint256)",
  "function checkInGoal() view returns (uint256)",
  "function deadline() view returns (uint256)",
  "function attester() view returns (address)",
  "function totalCheckIns() view returns (uint256)",
  "function memberCount() view returns (uint256)",
  "function totalDeposits() view returns (uint256)",
  "function totalSponsored() view returns (uint256)",
  "function poolQuoteNow() view returns (uint256)",
  "function prizeQuoteNow() view returns (uint256)",
  "function canLaunch() view returns (bool)",
  "function launched() view returns (bool)",
  "function token() view returns (address)",
  "function vault() view returns (address)",
  "function isMember(address account) view returns (bool)",
  "function daysOf(address member) view returns (uint256)",
  "function checkedInOn(address member, uint256 day) view returns (bool)",
  "function refundable(address account) view returns (uint256)",
]);
export const vaultAbi = parseAbi([
  "function taxToken() view returns (address)",
  "function quoteReceived() view returns (uint256)",
  "function claimable(address member) view returns (uint256 tokenAmount, uint256 quoteAmount)",
  "function claimedTokens(address member) view returns (uint256)",
  "function claimedQuote(address member) view returns (uint256)",
]);
export const tokenAbi = parseAbi(["function decimals() view returns (uint8)"]);

/** A round as the CheckInLauncher reports it. Amounts are in the quote token's smallest units. */
export interface RoundState {
  /** The name stored in the Launcher (the token's name). */
  name: string;
  quoteToken: string;
  quoteDecimals: number;
  deposit: bigint;
  liquidityBps: number;
  checkInGoal: number;
  deadline: number;
  /** The address whose signature the Launcher requires on every check-in. */
  attester: string;
  totalCheckIns: number;
  memberCount: number;
  totalDeposits: bigint;
  totalSponsored: bigint;
  /** What launch() would seed the pool with: all sponsor money plus liquidityBps of the deposits. */
  poolQuoteNow: bigint;
  /** Before the launch: what launch() would send to the vault. After it: everything the vault has
   *  received so far (the prize plus trading tax). */
  prizeNow: bigint;
  /** The Launcher's own launch checks pass. Flap's Portal can still refuse a pool below its floor. */
  canLaunch: boolean;
  launched: boolean;
  /** Null until the launch. */
  token: string | null;
  vault: string | null;
}

export interface MemberState {
  member: boolean;
  /** Days this wallet has checked in on chain. */
  daysOf: number;
  /** The check-in for the asked day is on chain. */
  checkedIn: boolean;
  /** What refund() would pay this wallet right now; zero while refunds are closed. */
  refundable: bigint;
}

/** A wallet's share of a launched round's StreakVault. */
export interface ClaimState {
  claimableTokens: bigint;
  claimableQuote: bigint;
  /** Amount of the token already claimed (zero until the first claim). */
  claimedTokens: bigint;
  claimedQuote: bigint;
  tokenDecimals: number;
}

/** Sends gas money from the server wallet. Present only with a key. */
export interface FaucetWallet {
  /** Test BNB the server wallet holds. */
  balance(): Promise<bigint>;
  sendBnb(to: string, wei: bigint): Promise<string>;
}

export interface Chain {
  round(launcher: string): Promise<RoundState>;
  member(launcher: string, address: string, dayIndex: number): Promise<MemberState>;
  /** daysOf and the asked day's check-in for each address, in the same order. */
  members(launcher: string, addresses: string[], dayIndex: number): Promise<{ daysOf: number; checkedIn: boolean }[]>;
  claims(vault: string, address: string): Promise<ClaimState>;
  /** Test BNB balance of any address, in wei. */
  balanceOf(address: string): Promise<bigint>;
  faucet?: FaucetWallet;
}

const lower = (address: string) => address.toLowerCase();
const orNull = (address: string) => (address === zeroAddress ? null : lower(address));

export function createChain(rpcUrl: string, privateKey?: string): Chain {
  const transport = http(rpcUrl);
  const client = createPublicClient({ chain: bscTestnet, transport });
  // A Launcher's configuration is set once at creation, so it is read once per round.
  const fixed = new Map<string, Pick<RoundState, "name" | "quoteToken" | "quoteDecimals" | "deposit" | "liquidityBps" | "checkInGoal" | "deadline" | "attester">>();
  const tokenDecimals = new Map<string, number>();

  const reads: Chain = {
    round: async (launcher) => {
      const read = { address: launcher as Address, abi: launcherAbi } as const;
      let config = fixed.get(launcher);
      if (!config) {
        const [name, quoteToken, deposit, liquidityBps, checkInGoal, deadline, attester] = await client.multicall({
          allowFailure: false,
          contracts: [
            { ...read, functionName: "name" },
            { ...read, functionName: "quoteToken" },
            { ...read, functionName: "deposit" },
            { ...read, functionName: "liquidityBps" },
            { ...read, functionName: "checkInGoal" },
            { ...read, functionName: "deadline" },
            { ...read, functionName: "attester" },
          ],
        });
        const quoteDecimals = await client.readContract({ address: quoteToken, abi: tokenAbi, functionName: "decimals" });
        config = {
          name,
          quoteToken: lower(quoteToken),
          quoteDecimals,
          deposit,
          liquidityBps: Number(liquidityBps),
          checkInGoal: Number(checkInGoal),
          deadline: Number(deadline),
          attester: lower(attester),
        };
        fixed.set(launcher, config);
      }
      const [totalCheckIns, memberCount, totalDeposits, totalSponsored, poolQuoteNow, prizeQuoteNow, canLaunch, launched, token, vault] =
        await client.multicall({
          allowFailure: false,
          contracts: [
            { ...read, functionName: "totalCheckIns" },
            { ...read, functionName: "memberCount" },
            { ...read, functionName: "totalDeposits" },
            { ...read, functionName: "totalSponsored" },
            { ...read, functionName: "poolQuoteNow" },
            { ...read, functionName: "prizeQuoteNow" },
            { ...read, functionName: "canLaunch" },
            { ...read, functionName: "launched" },
            { ...read, functionName: "token" },
            { ...read, functionName: "vault" },
          ],
        });
      // After the launch the prize sits in the vault and grows as trading tax arrives.
      const prizeNow =
        launched && vault !== zeroAddress
          ? await client.readContract({ address: vault, abi: vaultAbi, functionName: "quoteReceived" })
          : prizeQuoteNow;
      return {
        ...config,
        totalCheckIns: Number(totalCheckIns),
        memberCount: Number(memberCount),
        totalDeposits,
        totalSponsored,
        poolQuoteNow,
        prizeNow,
        canLaunch,
        launched,
        token: orNull(token),
        vault: orNull(vault),
      };
    },

    member: async (launcher, address, dayIndex) => {
      const read = { address: launcher as Address, abi: launcherAbi } as const;
      const who = address as Address;
      const [member, daysOf, checkedIn, refundable] = await client.multicall({
        allowFailure: false,
        contracts: [
          { ...read, functionName: "isMember", args: [who] },
          { ...read, functionName: "daysOf", args: [who] },
          { ...read, functionName: "checkedInOn", args: [who, BigInt(dayIndex)] },
          { ...read, functionName: "refundable", args: [who] },
        ],
      });
      return { member, daysOf: Number(daysOf), checkedIn, refundable };
    },

    members: async (launcher, addresses, dayIndex) => {
      if (addresses.length === 0) return [];
      const read = { address: launcher as Address, abi: launcherAbi } as const;
      const day = BigInt(dayIndex);
      const [days, checked] = await Promise.all([
        client.multicall({
          allowFailure: false,
          contracts: addresses.map((a) => ({ ...read, functionName: "daysOf", args: [a as Address] }) as const),
        }),
        client.multicall({
          allowFailure: false,
          contracts: addresses.map((a) => ({ ...read, functionName: "checkedInOn", args: [a as Address, day] }) as const),
        }),
      ]);
      return addresses.map((_, i) => ({ daysOf: Number(days[i]), checkedIn: Boolean(checked[i]) }));
    },

    claims: async (vault, address) => {
      const read = { address: vault as Address, abi: vaultAbi } as const;
      const who = address as Address;
      let decimals = tokenDecimals.get(vault);
      if (decimals === undefined) {
        const token = await client.readContract({ ...read, functionName: "taxToken" });
        decimals = await client.readContract({ address: token, abi: tokenAbi, functionName: "decimals" });
        tokenDecimals.set(vault, decimals);
      }
      const [[claimableTokens, claimableQuote], claimedTokens, claimedQuote] = await client.multicall({
        allowFailure: false,
        contracts: [
          { ...read, functionName: "claimable", args: [who] },
          { ...read, functionName: "claimedTokens", args: [who] },
          { ...read, functionName: "claimedQuote", args: [who] },
        ],
      });
      return { claimableTokens, claimableQuote, claimedTokens, claimedQuote, tokenDecimals: decimals };
    },

    balanceOf: (address) => client.getBalance({ address: address as Address }),
  };
  if (!privateKey) return reads;

  const account = privateKeyToAccount(privateKey as Address);
  const wallet = createWalletClient({ account, chain: bscTestnet, transport });

  // Every transaction of the server wallet goes through this queue, one at a time, each with an
  // explicit nonce. A load-balanced public RPC can answer a "pending" count before it has seen the
  // transaction sent just before, so two transfers in a row would otherwise reuse a nonce.
  let queue: Promise<unknown> = Promise.resolve();
  let nextNonce = 0;
  let lastSent = 0;
  function send(tx: (nonce: number) => Promise<`0x${string}`>): Promise<`0x${string}`> {
    const run = queue.then(async () => {
      const pending = await client.getTransactionCount({ address: account.address, blockTag: "pending" });
      // Trust our own count only briefly: if a transaction was dropped, go back to what the node says.
      const nonce = Date.now() - lastSent < NONCE_MEMORY_MS ? Math.max(pending, nextNonce) : pending;
      const hash = await tx(nonce);
      nextNonce = nonce + 1;
      lastSent = Date.now();
      return hash;
    });
    queue = run.catch(() => undefined);
    return run;
  }
  const legacy = { type: "legacy", gasPrice: TESTNET_GAS_PRICE } as const;

  return {
    ...reads,
    faucet: {
      balance: () => client.getBalance({ address: account.address }),
      sendBnb: (to, wei) => send((nonce) => wallet.sendTransaction({ to: to as Address, value: wei, ...legacy, gas: TRANSFER_GAS, nonce })),
    },
  };
}
