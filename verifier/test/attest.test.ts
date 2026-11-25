import { describe, expect, it } from "vitest";
import { hashMessage, recoverMessageAddress } from "viem";
import { CHAIN_ID, checkInInner, createAttester } from "../src/attest.js";
import { dayIndexOf } from "../src/days.js";
import { LAUNCHER, VECTOR_ATTESTER, VECTOR_KEY } from "./fakes.js";

// The worked vector pinned in contracts/test/CheckInLauncher.t.sol (test_checkInSignatureVector).
// If any value here changes, the contract will reject this server's signatures.
const WALLET = "0x2000000000000000000000000000000000000002";
const DAY = 20782;
const INNER = "0xcbafcc6a3bedc56b8321a9d1f392336f2ecb2f6f507c449622b3597fab79ab07";
const DIGEST = "0xc1d54e2ae2bba8b6827381f84e8b5fa7ec86048f467fd60570575dec445aba41";
const SIGNATURE =
  "0xea91a378e84c0366ee93151c23b319e4ace635db74a3175e585737d4cd9cd5256dc9ee53d41e88ce0ac5b09c04f13e85612648bf490fad7c1e32814fc11b7cdc1c";

describe("attester signature (the contracts' worked vector)", () => {
  const attester = createAttester(VECTOR_KEY);

  it("signs for BSC testnet and with the vector's address", () => {
    expect(CHAIN_ID).toBe(97);
    expect(attester.address).toBe(VECTOR_ATTESTER);
  });

  it("inner = keccak256(abi.encode(chainId, launcher, wallet, day)), four words, not packed", () => {
    expect(checkInInner(97, LAUNCHER, WALLET, DAY)).toBe(INNER);
  });

  it("digest is the personal_sign hash of the 32 raw bytes of inner", () => {
    expect(hashMessage({ raw: INNER })).toBe(DIGEST);
  });

  it("produces exactly the pinned 65-byte signature, v = 28", async () => {
    const signature = await attester.signCheckIn(LAUNCHER, WALLET, DAY);
    expect(signature).toBe(SIGNATURE);
    expect(signature).toHaveLength(2 + 65 * 2);
    expect(signature.slice(-2)).toBe("1c");
    expect(await recoverMessageAddress({ message: { raw: INNER }, signature })).toBe(VECTOR_ATTESTER);
  });

  it("the address form of launcher and wallet does not change the signature", async () => {
    // An address with letters in it, written checksummed, lower-case and upper-case.
    const forms = [VECTOR_ATTESTER, VECTOR_ATTESTER.toLowerCase(), `0x${VECTOR_ATTESTER.slice(2).toUpperCase()}`];
    const asWallet = await Promise.all(forms.map((f) => attester.signCheckIn(LAUNCHER, f, DAY)));
    const asLauncher = await Promise.all(forms.map((f) => attester.signCheckIn(f, WALLET, DAY)));
    expect(new Set(asWallet).size).toBe(1);
    expect(new Set(asLauncher).size).toBe(1);
  });

  it("a signature is for one wallet, one day, one round and one chain", async () => {
    const other = async (chainId: number, launcher: string, wallet: string, day: number) =>
      createAttester(VECTOR_KEY, chainId).signCheckIn(launcher, wallet, day);
    expect(await other(97, LAUNCHER, WALLET, DAY + 1)).not.toBe(SIGNATURE);
    expect(await other(97, LAUNCHER, "0x2000000000000000000000000000000000000003", DAY)).not.toBe(SIGNATURE);
    expect(await other(97, "0x1000000000000000000000000000000000000002", WALLET, DAY)).not.toBe(SIGNATURE);
    expect(await other(56, LAUNCHER, WALLET, DAY)).not.toBe(SIGNATURE);
  });

  it("the vector's day number is 25 Nov 2026", () => {
    expect(dayIndexOf("2026-11-25")).toBe(DAY);
  });
});
