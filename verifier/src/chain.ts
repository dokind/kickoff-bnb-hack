// Chain access with viem: reads of a round (CheckInLauncher and, after the launch, its
// StreakVault), the factory's creation events (which rounds exist), the faucet's gas transfers and
// the OriginRegistry (where this server can be reached). BSC testnet only.
//
// This server sends no transaction to the Launcher or the vault. Members send join, checkIn,
// launch, refund and claim themselves; the only transactions sent from here are the faucet's
// transfers and OriginRegistry.setOrigin.
import {
  TransactionReceiptNotFoundError,
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  zeroAddress,
  type PrivateKeyAccount,
  type PublicClient,
  type Transport,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet } from "viem/chains";
import type { CreatedRound } from "./types.js";

type Address = `0x${string}`;

// BSC testnet reports a base fee of 0, so fee estimation can return 1 wei and the transaction never
// gets mined. Every transaction is sent as a legacy one at a fixed 1 gwei with an explicit gas limit.
const TESTNET_GAS_PRICE = 1_000_000_000n;
const TRANSFER_GAS = 21_000n;
/** setOrigin writes a short string and a timestamp: well under this. */
const ORIGIN_GAS = 200_000n;
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
/** contracts/src/OriginRegistry.sol: the server's current host, set by the attester key only. */
export const registryAbi = parseAbi([
  "function announcer() view returns (address)",
  "function origin() view returns (string)",
  "function setOrigin(string origin_)",
]);
/** Emitted once by CheckInLauncherFactory for every round it creates. `creator` is the wallet that
 *  called the Flap Portal. */
export const factoryAbi = parseAbi(["event CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)"]);

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

/** Sends gas money from the faucet's wallet: FAUCET_PRIVATE_KEY's when set, otherwise the
 *  attester's. Present only with a key. */
export interface FaucetWallet {
  /** The wallet's address, lower-case. */
  address: string;
  /** Test BNB the wallet holds. */
  balance(): Promise<bigint>;
  sendBnb(to: string, wei: bigint): Promise<string>;
}

/** The creation events of our CheckInLauncherFactory. Present only when a factory is configured. */
export interface FactoryLogs {
  /** The factory's address, lower-case. */
  address: string;
  /** The latest block number the RPC knows. */
  head(): Promise<number>;
  /** Rounds created in blocks `fromBlock` to `toBlock`, both included. One eth_getLogs call; the RPC
   *  may refuse a range it finds too wide. */
  created(fromBlock: number, toBlock: number): Promise<CreatedRound[]>;
}

/** A transaction's state as the RPC reports it. */
export type TxStatus = "pending" | "success" | "reverted";

/** The OriginRegistry. Present only with a registry address and the attester key. */
export interface OriginRegistryChain {
  /** The registry's address, lower-case. */
  address: string;
  /** The wallet that sends setOrigin (the attester), lower-case. */
  sender: string;
  /** The one address the registry accepts setOrigin from, lower-case. */
  announcer(): Promise<string>;
  /** origin() as stored now ("" before the first setOrigin). */
  read(): Promise<string>;
  /** Sends setOrigin(host) from the attester key and returns the transaction hash once submitted. */
  announce(host: string): Promise<`0x${string}`>;
  /** "pending" while the RPC has no receipt for `hash`. */
  status(hash: `0x${string}`): Promise<TxStatus>;
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
  factory?: FactoryLogs;
  origin?: OriginRegistryChain;
}

export interface ChainOptions {
  /** FAUCET_PRIVATE_KEY: the faucet pays from this key instead of the attester key. */
  faucetKey?: string;
  /** ORIGIN_REGISTRY: the OriginRegistry this server writes its host to (needs the attester key). */
  originRegistry?: string;
}

const lower = (address: string) => address.toLowerCase();
const orNull = (address: string) => (address === zeroAddress ? null : lower(address));

/**
 * `privateKey` is the attester key. `factory` is the address of our CheckInLauncherFactory; without
 * it no rounds are discovered. The faucet pays from `options.faucetKey` when given, otherwise from
 * the attester key; setOrigin is always sent from the attester key.
 */
export function createChain(rpcUrl: string, privateKey?: string, factory?: string, options: ChainOptions = {}): Chain {
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
  if (factory) {
    const address = lower(factory) as Address;
    const event = factoryAbi[0];
    reads.factory = {
      address,
      head: async () => Number(await client.getBlockNumber({ cacheTime: 0 })),
      created: async (fromBlock, toBlock) => {
        const logs = await client.getLogs({ address, event, fromBlock: BigInt(fromBlock), toBlock: BigInt(toBlock), strict: true });
        const found: CreatedRound[] = [];
        for (const log of logs) {
          if (log.removed) continue;
          // Most nodes put the block's timestamp on the log; the others are asked for the block.
          const at = log.blockTimestamp ?? (await client.getBlock({ blockNumber: log.blockNumber })).timestamp;
          found.push({ launcher: lower(log.args.launcher), creator: lower(log.args.creator), block: Number(log.blockNumber), createdAt: Number(at) });
        }
        return found;
      },
    };
  }
  // Each key has its own wallet and its own queue. The same key given twice is one wallet, so its
  // transactions still share one queue and one nonce count.
  const wallets = new Map<string, ServerWallet>();
  const walletOf = (key: string): ServerWallet => {
    const address = lower(privateKeyToAccount(key as Address).address);
    let found = wallets.get(address);
    if (!found) {
      found = serverWallet(client, transport, key as Address);
      wallets.set(address, found);
    }
    return found;
  };
  const signer = privateKey ? walletOf(privateKey) : undefined;
  const payer = options.faucetKey ? walletOf(options.faucetKey) : signer;
  const legacy = { type: "legacy", gasPrice: TESTNET_GAS_PRICE } as const;

  const chain: Chain = { ...reads };
  if (payer) {
    chain.faucet = {
      address: payer.address,
      balance: () => client.getBalance({ address: payer.address as Address }),
      sendBnb: (to, wei) =>
        payer.send((nonce) => payer.wallet.sendTransaction({ to: to as Address, value: wei, ...legacy, gas: TRANSFER_GAS, nonce })),
    };
  }
  if (options.originRegistry && signer) {
    const registry = lower(options.originRegistry) as Address;
    const read = { address: registry, abi: registryAbi } as const;
    chain.origin = {
      address: registry,
      sender: signer.address,
      announcer: async () => lower(await client.readContract({ ...read, functionName: "announcer" })),
      read: () => client.readContract({ ...read, functionName: "origin" }),
      announce: (host) =>
        signer.send((nonce) =>
          signer.wallet.writeContract({ ...read, functionName: "setOrigin", args: [host], ...legacy, gas: ORIGIN_GAS, nonce }),
        ),
      status: async (hash) => {
        try {
          const receipt = await client.getTransactionReceipt({ hash });
          return receipt.status === "success" ? "success" : "reverted";
        } catch (e) {
          if (e instanceof TransactionReceiptNotFoundError) return "pending";
          throw e;
        }
      },
    };
  }
  return chain;
}

interface ServerWallet {
  /** Lower-case. */
  address: string;
  wallet: WalletClient<Transport, typeof bscTestnet, PrivateKeyAccount>;
  /** Sends one transaction built with the given nonce, after every earlier one of this wallet. */
  send(tx: (nonce: number) => Promise<`0x${string}`>): Promise<`0x${string}`>;
}

function serverWallet(client: PublicClient<Transport, typeof bscTestnet>, transport: Transport, key: Address): ServerWallet {
  const account = privateKeyToAccount(key);
  const wallet = createWalletClient({ account, chain: bscTestnet, transport });

  // Every transaction of this wallet goes through this queue, one at a time, each with an explicit
  // nonce. A load-balanced public RPC can answer a "pending" count before it has seen the
  // transaction sent just before, so two transactions in a row would otherwise reuse a nonce.
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
  return { address: lower(account.address), wallet, send };
}
