# Changelog

All notable changes to the AlbFetcharr release are documented here. AlbFetcharr
ships as a single product version — each entry corresponds to one published
`semsemyonoff/albfetcharr` image tag built from the pinned `backend`/`frontend`
submodule commits.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

<!-- Write notes for the next release here. "Cut release" promotes this
     section to ## [X.Y.Z] - <date> and uses it as the release body. -->

## [0.1.0] - 2026-06-23

Initial release of **AlbFetcharr** — a web service that fetches Lidarr's
wanted albums from Yandex Music, YouTube Music, SoundCloud, and Bandcamp and
imports them back into Lidarr.

Ships as a single multi-arch image (linux/amd64 + linux/arm64) built from the
pinned `backend` and `frontend` submodules, published to Docker Hub and GHCR.

### Added
- Full feature set: wanted-list retrieval from the Lidarr API; album search
  across four sources (Yandex Music, YouTube Music, SoundCloud, Bandcamp) behind
  a pluggable source model; per-album quality/format selection; download with
  real-time progress; and automatic ManualImport into Lidarr with cover-art copy.
- Three-step web UI (Select → Results → Download) with light/dark/system themes
  and EN/RU localization; equivalent `wanted` / `download` CLI subcommands.
- Optional persistent settings store (SQLite) with Fernet-encrypted secrets, an
  in-app settings screen, and a per-run override panel.
- OpenAPI 3 spec with Scalar / Swagger / Redoc viewers under `/apidoc`, and a
  version readout backed by `GET /api/version`.
- Deployment layer: production `docker-compose.yml`, `.env.example`, a release
  `Makefile`, and pinned `backend`/`frontend` submodules built into one image.
- Self-contained multi-stage `Dockerfile` (SPA build + backend runtime, with
  deno baked in for yt-dlp's YouTube challenge solver) — the release image builds
  entirely from this repo, with no dependency on the dev stack.
- Release CI: the "Cut release" button builds the multi-arch image and publishes
  it to Docker Hub and GHCR (and to git.horn on internal infra).

