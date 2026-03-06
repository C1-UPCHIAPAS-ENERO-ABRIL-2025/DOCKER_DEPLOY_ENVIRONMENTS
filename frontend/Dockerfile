# ============================================================
# Frontend Dockerfile - Multi-stage
# Stage: dev    -> Vite dev server with hot-reload (development profile)
# Stage: build  -> Runs `npm run build` (staging profile) — artifacts are EPHEMERAL
# Stage: prod   -> Nginx serves the static build (production profile)
# ============================================================

# ---------- Stage 0: base node ----------
FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci

# ---------- Stage 1: dev (hot-reload via volume mount) ----------
FROM base AS dev
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev"]

# ---------- Stage 2: build (used in staging — artifacts stay inside container) ----------
FROM base AS build
COPY . .
RUN npm run build
# dist/ is produced here but NOT mapped outside — ephemeral by design

# ---------- Stage 3: prod (nginx serves the static files) ----------
FROM nginx:1.27-alpine AS prod
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.staging.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
