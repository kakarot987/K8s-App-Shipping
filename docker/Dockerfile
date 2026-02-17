# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT: Build from the app/ directory as context:
#   docker build -f docker/Dockerfile -t my-service:local app/
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: deps — production dependencies only
FROM node:20-alpine AS deps
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: build — full deps + source (TypeScript compile, etc.)
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . ./
RUN npm run build 2>/dev/null || true   # no-op if no build script

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: runtime — minimal production image
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

ARG BUILD_DATE
ARG GIT_SHA

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="my-service" \
      org.opencontainers.image.vendor="MyOrg"

# Security: run as non-root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

# Copy prod node_modules and source from earlier stages
COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/src          ./src
COPY --from=build /app/package.json ./

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

ENV NODE_ENV=production

CMD ["node", "src/server.js"]
