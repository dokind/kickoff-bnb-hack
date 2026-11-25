// Storage: in memory, optionally mirrored to a JSON file.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { CheckIn, Discovery, FaucetDrip, Listing, RoundRef } from "./types.js";

export interface Store {
  /** The round set with POST /admin/round, if any. */
  getRound(): Promise<RoundRef | undefined>;
  putRound(round: RoundRef): Promise<void>;
  /** Addresses this server has seen as members of a round (the chain has no list to read). */
  getMembers(launcher: string): Promise<string[]>;
  addMember(launcher: string, address: string, at: number): Promise<void>;
  getCheckIns(launcher: string): Promise<CheckIn[]>;
  /** One entry per member per day: a second put for the same (address, day) replaces the first. */
  putCheckIn(launcher: string, checkIn: CheckIn): Promise<void>;
  /** Faucet payouts, one per address: a second put for the same address replaces the first. */
  getFaucetDrips(): Promise<FaucetDrip[]>;
  putFaucetDrip(drip: FaucetDrip): Promise<void>;
  /** The rounds found in the factory's creation events and how far the scan got. */
  getDiscovery(): Promise<Discovery | undefined>;
  putDiscovery(discovery: Discovery): Promise<void>;
  /** A creator's choice to list or unlist a round, if one was registered. */
  getListing(launcher: string): Promise<Listing | undefined>;
  putListing(launcher: string, listing: Listing): Promise<void>;
}

interface Data {
  round?: RoundRef;
  /** launcher -> address -> first seen (unix seconds). */
  roundMembers: Record<string, Record<string, number>>;
  /** launcher -> "<address>#<day>" -> check-in. */
  checkIns: Record<string, Record<string, CheckIn>>;
  faucet: Record<string, FaucetDrip>;
  // The two below are absent from the file until first written.
  discovery?: Discovery;
  /** launcher -> the creator's choice. */
  listings?: Record<string, Listing>;
}

/** Pass a file path to keep data across restarts; pass nothing for a pure in-memory store. */
export class LocalStore implements Store {
  private data: Data = { roundMembers: {}, checkIns: {}, faucet: {} };

  constructor(private readonly file?: string) {
    if (file && existsSync(file)) {
      // Only the keys above are kept. A file written by the earlier club-season server is read for
      // its faucet record; its other records are left out and are gone once this server writes.
      const saved = JSON.parse(readFileSync(file, "utf8")) as Partial<Data>;
      this.data = {
        round: saved.round,
        roundMembers: saved.roundMembers ?? {},
        checkIns: saved.checkIns ?? {},
        faucet: saved.faucet ?? {},
        discovery: saved.discovery,
        listings: saved.listings,
      };
    }
  }

  private save(): void {
    if (!this.file) return;
    mkdirSync(dirname(this.file), { recursive: true });
    writeFileSync(this.file, JSON.stringify(this.data, null, 2));
  }

  async getRound() {
    return this.data.round;
  }
  async putRound(round: RoundRef) {
    this.data.round = round;
    this.save();
  }
  async getMembers(launcher: string) {
    return Object.keys(this.data.roundMembers[launcher] ?? {});
  }
  async addMember(launcher: string, address: string, at: number) {
    const members = (this.data.roundMembers[launcher] ??= {});
    if (address in members) return;
    members[address] = at;
    this.save();
  }
  async getCheckIns(launcher: string) {
    return Object.values(this.data.checkIns[launcher] ?? {});
  }
  async putCheckIn(launcher: string, checkIn: CheckIn) {
    (this.data.checkIns[launcher] ??= {})[`${checkIn.address}#${checkIn.day}`] = checkIn;
    this.save();
  }
  async getFaucetDrips() {
    return Object.values(this.data.faucet);
  }
  async putFaucetDrip(drip: FaucetDrip) {
    this.data.faucet[drip.address] = drip;
    this.save();
  }
  async getDiscovery() {
    return this.data.discovery;
  }
  async putDiscovery(discovery: Discovery) {
    this.data.discovery = { ...discovery, rounds: discovery.rounds.map((r) => ({ ...r })) };
    this.save();
  }
  async getListing(launcher: string) {
    return this.data.listings?.[launcher];
  }
  async putListing(launcher: string, listing: Listing) {
    (this.data.listings ??= {})[launcher] = listing;
    this.save();
  }
}
