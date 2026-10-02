# Living Page backend — multi-stage build. Node 20 (>=20.6 for --env-file).
FROM node:20.18.0-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:20.18.0-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

FROM node:20.18.0-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Run as the built-in non-root user.
USER node
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/dist ./dist
COPY --chown=node:node package.json ./

EXPOSE 8080
# Provide env at runtime via `--env-file` / orchestrator secrets, not baked in.
# kiro-cli is NOT installed here; install/mount it and set KIRO_CLI_PATH to use
# the real provider. Without KIRO_API_KEY the service runs in mock mode.
CMD ["node", "dist/server.js"]
