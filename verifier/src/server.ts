// Local entry: npm run dev
import { serve } from "@hono/node-server";
import { appFromEnv } from "./config.js";
import { SERVICE_NAME } from "./product.js";

const app = appFromEnv();
const port = Number(process.env.PORT || 8787);
serve({ fetch: app.fetch, port }, () => console.log(`${SERVICE_NAME} on http://localhost:${port}`));
