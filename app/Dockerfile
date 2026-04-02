FROM node:20-alpine AS base
WORKDIR /app

# Install dependencies
COPY package.json ./
RUN npm install --omit=dev

# Copy source
COPY server.js ./
COPY public/ ./public/

# Build metadata baked in at image build time
ARG VERSION=v1
ARG VERSION_LABEL=1.0.0
ARG BUILD_TIME

ENV VERSION=${VERSION}
ENV VERSION_LABEL=${VERSION_LABEL}
ENV BUILD_TIME=${BUILD_TIME}
ENV PORT=3000
ENV NODE_ENV=production

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

USER node
CMD ["node", "server.js"]
