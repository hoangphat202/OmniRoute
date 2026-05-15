FROM node:22-bookworm-slim AS builder
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsecret-1-0 ca-certificates python3 build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
COPY scripts/build/postinstall.mjs ./scripts/build/postinstall.mjs
COPY scripts/build/postinstallSupport.mjs ./scripts/build/postinstallSupport.mjs
COPY scripts/build/native-binary-compat.mjs ./scripts/build/native-binary-compat.mjs
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true

RUN npm pkg delete scripts.prepare

RUN if [ -f package-lock.json ]; then \
    npm ci --no-audit --no-fund --legacy-peer-deps; \
    else \
    npm install --no-audit --no-fund --legacy-peer-deps; \
    fi

COPY . ./
RUN mkdir -p /app/data && npm run build -- --webpack

# ---------------------------------------------------------

FROM node:22-bookworm-slim AS runner-base
WORKDIR /app

LABEL org.opencontainers.image.title="omniroute" \
  org.opencontainers.image.description="Unified AI proxy — route any LLM through one endpoint" \
  org.opencontainers.image.url="https://omniroute.online" \
  org.opencontainers.image.source="https://github.com/diegosouzapw/OmniRoute" \
  org.opencontainers.image.licenses="MIT"

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
ENV NODE_OPTIONS="--max-old-space-size=256"
ENV DATA_DIR=/app/data

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsecret-1-0 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/data

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/node_modules/@swc/helpers ./node_modules/@swc/helpers
COPY --from=builder /app/node_modules/pino-abstract-transport ./node_modules/pino-abstract-transport
COPY --from=builder /app/node_modules/pino-pretty ./node_modules/pino-pretty
COPY --from=builder /app/node_modules/split2 ./node_modules/split2
COPY --from=builder /app/src/lib/db/migrations ./migrations
ENV OMNIROUTE_MIGRATIONS_DIR=/app/migrations
COPY --from=builder /app/src/mitm/server.cjs ./src/mitm/server.cjs
COPY --from=builder /app/docs ./docs
COPY --from=builder /app/scripts/dev/run-standalone.mjs ./dev/run-standalone.mjs
COPY --from=builder /app/scripts/build/runtime-env.mjs ./build/runtime-env.mjs
COPY --from=builder /app/scripts/build/bootstrap-env.mjs ./build/bootstrap-env.mjs
COPY --from=builder /app/scripts/dev/healthcheck.mjs ./healthcheck.mjs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["node", "healthcheck.mjs"]

CMD ["node", "dev/run-standalone.mjs"]

# ---------------------------------------------------------

FROM runner-base AS runner-cli

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates docker.io docker-compose \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system url."https://github.com/".insteadOf "ssh://git@github.com/"

RUN npm install -g --no-audit --no-fund @openai/codex @anthropic-ai/claude-code droid openclaw@latest
