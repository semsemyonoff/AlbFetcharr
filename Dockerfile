# syntax=docker/dockerfile:1
#
# Production image for AlbFetcharr — the Flask API plus the pre-built SPA in a
# single container. The build context is THIS deploy repo root, so both pinned
# submodules are visible:
#   frontend/ — React/Vite SPA, built to static assets in stage 1
#   backend/  — Flask app; serves the API and the baked SPA on :5000, plus the
#               `wanted`/`download` CLI subcommands
#
# Build with ./build.sh (multi-arch, pushes) or `make release` / `make release-local`.
# This is fully self-contained: it does NOT depend on the DWE dev stack.

# ---- Stage 1: build the SPA ----
FROM node:20-slim AS spa
WORKDIR /app
# Manifests first for layer caching. Any committed frontend/.npmrc (registry
# concurrency cap) is brought in with the full source copy below before build.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
# vite.config.js pins base=/static/dist/ for the production build; output -> /app/dist.
RUN npm run build

# ---- Stage 2: backend runtime ----
FROM python:3.14

# Runtime tools:
#   gosu   — drop to the UID/GID requested at runtime (see docker-entrypoint.sh)
#   ffmpeg — audio conversion for the yt-dlp sources (YouTube Music, SoundCloud, Bandcamp)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# deno — JS runtime yt-dlp 2026.x needs to solve YouTube's signature / n-challenge
# (together with the yt-dlp-ejs solver bundled as a backend dependency). Without
# it some formats are missing and YouTube downloads fail with HTTP 403. The
# denoland/deno:bin image is multi-arch, so this copies the right binary per arch.
COPY --from=denoland/deno:bin /deno /usr/local/bin/deno

WORKDIR /app

# Dependencies are declared in backend/pyproject.toml (single source of truth;
# pulls yt-dlp, yt-dlp-ejs, ytmusicapi, the pinned yandex-music-downloader, etc.).
# README.md is referenced by pyproject (readme = "README.md"), so it must be present.
COPY backend/pyproject.toml backend/README.md ./
COPY backend/albfetcharr ./albfetcharr

# Bake the built SPA where Flask serves it: albfetcharr/web/static/dist/. It must
# land inside the package BEFORE `pip install`, so it is captured by the
# package-data glob (static/**/*) and ends up in the installed package.
COPY --from=spa /app/dist ./albfetcharr/web/static/dist
RUN pip install --no-cache-dir .

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 5000

# Container-internal defaults. UID/GID/UMASK drive the gosu drop in the
# entrypoint; DOWNLOAD_DIR is where the backend writes fetched albums (bind-mount
# a host dir here). These are overridable at runtime via the compose env.
ENV UID=1000 GID=1000 UMASK=022 \
    DOWNLOAD_DIR=/downloads \
    YANDEX_MUSIC_QUALITY=2

# Product release version, baked at build time (build.sh passes the release tag,
# e.g. 1.2.3). The backend reads APP_VERSION at startup and reports it as the
# OpenAPI info.version and GET /api/version (see albfetcharr/version.py). No git
# history is needed in the image — .dockerignore strips .git, so the version is
# injected here instead of derived from a tag at runtime. Defaults to 0.0.0 for a
# plain `docker build` without --build-arg.
ARG APP_VERSION=0.0.0
ENV APP_VERSION=$APP_VERSION

ENTRYPOINT ["/docker-entrypoint.sh"]
