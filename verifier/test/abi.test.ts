import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { launcherAbi, registryAbi, vaultAbi } from "../src/chain.js";

// The server reads the contracts through hand-written fragments. This checks every fragment against
// the ABI the contracts folder exports, so a renamed or retyped view cannot go unnoticed.
const abiFile = (name: string) => fileURLToPath(new URL(`../../contracts/abi/${name}.json`, import.meta.url));
const exported = existsSync(abiFile("CheckInLauncher")) && existsSync(abiFile("StreakVault"));

type Fragment = {
  type: string;
  name?: string;
  stateMutability?: string;
  inputs?: readonly { type: string }[];
  outputs?: readonly { type: string }[];
};
const shape = (f: Fragment) => ({
  stateMutability: f.stateMutability,
  inputs: (f.inputs ?? []).map((i) => i.type),
  outputs: (f.outputs ?? []).map((o) => o.type),
});

describe.skipIf(!exported)("ABI fragments match contracts/abi", () => {
  const load = (name: string): Fragment[] => {
    const json = JSON.parse(readFileSync(abiFile(name), "utf8")) as Fragment[] | { abi: Fragment[] };
    return Array.isArray(json) ? json : json.abi;
  };

  for (const [name, fragments] of [
    ["CheckInLauncher", launcherAbi],
    ["StreakVault", vaultAbi],
  ] as const) {
    it(`${name}: every function this server reads exists with the same types`, () => {
      const full = load(name).filter((f) => f.type === "function");
      expect(fragments.length).toBeGreaterThan(0);
      for (const fragment of fragments as readonly Fragment[]) {
        const match = full.find((f) => f.name === fragment.name);
        expect(match, `${name}.${fragment.name} is missing from the exported ABI`).toBeDefined();
        expect(shape(match!), `${name}.${fragment.name}`).toEqual(shape(fragment));
      }
    });
  }
});

// OriginRegistry is not in contracts/abi; its compiled artifact is checked when `forge build` has run.
const registryFile = fileURLToPath(new URL("../../contracts/out/OriginRegistry.sol/OriginRegistry.json", import.meta.url));

describe.skipIf(!existsSync(registryFile))("ABI fragment matches the compiled OriginRegistry", () => {
  it("OriginRegistry: announcer, origin and setOrigin exist with the same types", () => {
    const full = (JSON.parse(readFileSync(registryFile, "utf8")) as { abi: Fragment[] }).abi.filter((f) => f.type === "function");
    for (const fragment of registryAbi as readonly Fragment[]) {
      const match = full.find((f) => f.name === fragment.name);
      expect(match, `OriginRegistry.${fragment.name} is missing`).toBeDefined();
      expect(shape(match!), `OriginRegistry.${fragment.name}`).toEqual(shape(fragment));
    }
  });
});
