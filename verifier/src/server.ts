// Local entry: npm run dev
import { serve } from "@hono/node-server";
import { serverFromEnv } from "./config.js";
import { SERVICE_NAME } from "./product.js";

const { app, rounds, refreshSeconds } = serverFromEnv();
const port = Number(process.env.PORT || 8787);
serve({ fetch: app.fetch, port }, () => console.log(`${SERVICE_NAME} on http://localhost:${port}`));

// Looks for newly created rounds, now and then every few seconds. The message names no address and
// repeats no error text (an RPC error can contain the RPC's address, which may hold a key).
let reachedHead = true;
async function lookForRounds() {
  const ok = await rounds.refresh();
  if (ok !== reachedHead) console.warn(ok ? "Round discovery is up to date again." : "Round discovery could not read the chain; it will be tried again.");
  reachedHead = ok;
}
void lookForRounds();
setInterval(() => void lookForRounds(), refreshSeconds * 1000).unref();
