// What a daily report must look like before this server signs a check-in. Pure functions, no I/O.
import type { Source } from "./types.js";

/** Steps a member must have moved on a day to check in, unless MIN_STEPS says otherwise. */
export const DEFAULT_MIN_STEPS = 1000;
/** More than this in one day is rejected, not clipped. */
export const MAX_STEPS = 80_000;

export type RuleResult = { ok: true } | { ok: false; status: 400 | 422; code: string; message: string };
const fail = (status: 400 | 422, code: string, message: string): RuleResult => ({ ok: false, status, code, message });

/**
 * Steps as sent: a JSON number or a string of digits. The signed text contains exactly what was
 * sent, so only the plain form JavaScript prints for a whole number is accepted ("5000", not "5e3").
 */
export function parseSteps(value: unknown): number | null {
  if (typeof value === "number") return Number.isSafeInteger(value) && value >= 0 ? value : null;
  if (typeof value === "string" && /^(0|[1-9]\d{0,8})$/.test(value)) return Number(value);
  return null;
}

export const isSource = (value: unknown): value is Source =>
  value === "healthkit" || value === "healthconnect" || value === "self";

export interface ReportCheck {
  steps: unknown;
  source: unknown;
  minSteps: number;
  /** ALLOW_SELF_REPORTED=true: the testnet demo, where the web app has no health data to read. */
  allowSelfReported: boolean;
}

export function checkReport(r: ReportCheck): RuleResult {
  if (!isSource(r.source)) return fail(400, "bad_source", "source must be healthkit, healthconnect or self");
  if (r.source === "self" && !r.allowSelfReported) {
    return fail(422, "self_report_disabled", "self-reported check-ins are switched off on this server");
  }
  const steps = parseSteps(r.steps);
  if (steps === null) return fail(400, "bad_steps", "steps must be a whole number");
  if (steps > MAX_STEPS) return fail(422, "implausible_steps", `more than ${MAX_STEPS} steps in one day is not accepted`);
  if (steps < r.minSteps) return fail(422, "not_enough_steps", `a check-in needs at least ${r.minSteps} steps today`);
  return { ok: true };
}
