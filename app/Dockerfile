# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: production dependencies only.
#
# `npm ci` (not `npm install`) so the build is reproducible from the lockfile
# and can never silently resolve a different version than the one reviewed.
# ---------------------------------------------------------------------------
FROM node:22.11.0-alpine3.20 AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---------------------------------------------------------------------------
# Stage 2: dev dependencies + test run.
#
# Exists so CI can lint and test the exact tree that gets shipped, using one
# `docker build` invocation, with no Node toolchain needed on the runner.
# ---------------------------------------------------------------------------
FROM node:22.11.0-alpine3.20 AS test

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run lint && npm test

# ---------------------------------------------------------------------------
# Stage 3: runtime.
#
# Distroless: no shell, no package manager, no busybox. If this container is
# ever compromised there is nothing in the image to pivot with. The `nonroot`
# variant runs as uid 65532, which also lets the pod spec assert
# runAsNonRoot: true without guessing a uid.
#
# No HEALTHCHECK instruction: there is no shell or curl to run one, and
# Kubernetes liveness/readiness probes are the authority here anyway.
# ---------------------------------------------------------------------------
FROM gcr.io/distroless/nodejs22-debian12:nonroot AS runtime

# Populated by CI from git metadata.
ARG APP_VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="hello-world-service" \
      org.opencontainers.image.description="Hello World microservice with health probes and Prometheus metrics" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}

# Copied as separate layers, least-to-most frequently changed, so a code-only
# edit does not invalidate the dependency layer.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER nonroot

EXPOSE 8080

# The distroless nodejs image's entrypoint is already `node`, so this is the
# script path rather than a full command. No shell form: we want PID 1 to be
# node itself so it receives SIGTERM directly and our graceful shutdown runs.
CMD ["src/server.js"]
