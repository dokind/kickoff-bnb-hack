# Cypher Run verifier. Build from this folder:  docker build -t cypher-run-verifier .
# See README.md ("Running in Docker") for the environment and the data volume.

# 1. Build: compile the TypeScript into plain JavaScript (dist/server.mjs).
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# 2. Run: production dependencies only, as the unprivileged "node" user.
FROM node:22-slim
ENV NODE_ENV=production PORT=8787 DATA_FILE=/data/store.json
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
# The JSON store lives in /data; mount a volume there to keep it across restarts. ./data points to
# it too, so an .env that still says DATA_FILE=./data/store.json ends up on the same volume.
RUN mkdir /data && chown node:node /data && ln -s /data /app/data
VOLUME /data
USER node
EXPOSE 8787
# No secrets are baked in: RPC_URL, ADMIN_TOKEN and ATTESTER_PRIVATE_KEY come from the environment.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "dist/server.mjs"]
