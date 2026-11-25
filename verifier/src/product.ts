// The product name. This is the only place the server spells it: the service name and the
// texts members sign are built from it, so renaming the product means changing this one constant
// (and the same constant in the app, because both sides must build identical texts).
export const PRODUCT_NAME = "Cypher Run";

/** `cypher-run-verifier`: the name in lower case, spaces as hyphens. */
export const SERVICE_NAME = `${PRODUCT_NAME.toLowerCase().replace(/\s+/g, "-")}-verifier`;

/** Text a member signs (personal_sign) to report a day: `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>`. */
export const checkInMessage = (launcher: string, day: string, steps: string | number) =>
  `${PRODUCT_NAME} checkin ${launcher} ${day} ${steps}`;

/** Text a wallet signs (personal_sign) to ask the faucet for gas: `Cypher Run faucet <address>`. */
export const faucetMessage = (address: string) => `${PRODUCT_NAME} faucet ${address}`;

/**
 * Text a round's creator signs (personal_sign) to put the round on the app's public list or keep it
 * off: `Cypher Run round <launcher> <listed|unlisted>`, the launcher in lower case.
 */
export const roundMessage = (launcher: string, unlisted: boolean) =>
  `${PRODUCT_NAME} round ${launcher} ${unlisted ? "unlisted" : "listed"}`;
