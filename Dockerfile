# syntax=docker.io/docker/dockerfile:1

FROM node:20-alpine AS base

# ---------- deps ----------
FROM base AS deps
# Prisma + many native deps need these
RUN apk add --no-cache libc6-compat curl bash openssl libstdc++
# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /app

# Copy only manifest first for better layer caching
COPY package.json bun.lockb ./
COPY prisma ./prisma

# Install deps (frozen for reproducibility)
RUN bun install --frozen-lockfile

# ---------- builder ----------
FROM base AS builder
RUN apk add --no-cache libc6-compat curl bash openssl libstdc++
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /app

# Reuse installed deps
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/prisma ./prisma
# Copy the rest of the source
COPY . .

# Generate Prisma client and build Next (ensure "build" script runs next build)
RUN bun prisma generate && bun run build

# ---------- runner ----------
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production

# Create non-root user
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

# Minimal runtime libs for Prisma/Node
RUN apk add --no-cache libc6-compat openssl libstdc++

# Copy the Next standalone output
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Next standalone places "server.js" at the root of the standalone tree
CMD ["node", "server.js"]
