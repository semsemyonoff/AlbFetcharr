# AlbFetcharr

![logo](assets/logo.svg)

A web service that fetches [Lidarr](https://lidarr.audio/)'s **wanted** albums
from [Yandex Music](https://music.yandex.ru/),
[YouTube Music](https://music.youtube.com/),
[SoundCloud](https://soundcloud.com/), and [Bandcamp](https://bandcamp.com/),
then imports them back into Lidarr. Built around a pluggable source model.

AlbFetcharr complements Lidarr: Lidarr tracks what you're missing and owns the
library; AlbFetcharr is the fetcher that fills the gaps from streaming sources
and hands the results back via Lidarr's ManualImport.

## Features

- **Wanted list** — pulls albums with status *Missing* straight from the Lidarr API
- **Multi-source search** — Yandex Music, YouTube Music, SoundCloud, and Bandcamp
  behind one pluggable source model; pick which sources to search per run
- **Quality / format choice** — per-album selection of the best match and the
  download quality/format before fetching
- **Download with live progress** — per-album progress bars and a terminal log,
  via [yandex-music-downloader](https://github.com/llistochek/yandex-music-downloader)
  (Yandex) and [yt-dlp](https://github.com/yt-dlp/yt-dlp) (the rest)
- **Automatic import** — ManualImport into Lidarr plus cover-art copy next to the
  imported album (partial imports are surfaced, not failed)
- **Three-step web UI** — Select → Results → Download, with light/dark/system
  themes and EN/RU localization
- **CLI mode** — the same `wanted` / `download` flows headless, for cron or scripts
- **Persistent settings (optional)** — SQLite store with Fernet-encrypted secrets,
  an in-app settings screen, and a per-run override panel
- **OpenAPI 3** — Scalar / Swagger / Redoc viewers under `/apidoc`

---

## This repository — the entry point

This is the **release layer** that ties the product together. It contains no
application source — that lives in two repositories, pinned here as submodules
and built into a single image:

| Submodule    | Source                                                  | Role                            |
|--------------|---------------------------------------------------------|---------------------------------|
| `backend/`   | `semsemyonoff/AlbFetcharr-backend` (Flask API + fetcher)| App; serves API + SPA + CLI on :5000 |
| `frontend/`  | `semsemyonoff/AlbFetcharr-frontend` (React/Vite SPA)    | Built into the image            |

AlbFetcharr ships as **one product version** = **one container** = **one image**
(`semsemyonoff/albfetcharr`). The Vite SPA is built to static assets and baked
into the backend image, which Flask/gunicorn serves alongside the API on port
`5000`. There is no separate frontend container in production.

---

## For operators (self-hosting)

You only need this `README`, `docker-compose.yml`, and `.env.example` — not the
submodules.

```bash
cp .env.example .env                       # set tokens, Lidarr URL/key, paths, port
mkdir -p config downloads library          # persistent state, download staging, library
docker compose up -d
```

Open `http://localhost:8080` (or the `ALBFETCHARR_HTTP_PORT` you set), fill in
the required tokens (or set them in `.env`), then load your wanted list and start
fetching.

### Running alongside Lidarr

AlbFetcharr does not bundle Lidarr — point it at your existing instance. A
combined stack looks like this:

```yaml
services:
  lidarr:
    image: linuxserver/lidarr
    container_name: lidarr
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./lidarr/config:/config
      - /path/to/music:/data/library
      - /path/to/downloads:/data/downloads
    ports:
      - "8686:8686"
    restart: unless-stopped

  albfetcharr:
    image: semsemyonoff/albfetcharr
    container_name: albfetcharr
    environment:
      - YANDEX_MUSIC_TOKEN=your_token_here
      - YANDEX_MUSIC_QUALITY=2
      - LIDARR_URL=http://lidarr:8686
      - LIDARR_API_KEY=your_api_key_here
      - ALBFETCHARR_LIDARR_IMPORT_PATH=/data/downloads/alb
      - ALBFETCHARR_LIBRARY_MAP=/data/library=/libraries/music
    volumes:
      - ./albfetcharr/config:/config
      - /path/to/downloads/alb:/downloads
      - /path/to/music:/libraries/music
    ports:
      - "8080:5000"
    restart: unless-stopped
```

The provided `docker-compose.yml` ships only the `albfetcharr` service and drives
everything from `.env`; the snippet above shows how it sits next to Lidarr.

### Directories and library mapping

AlbFetcharr works with two kinds of directories:

- **Downloads** — the staging folder where albums are fetched to (mounted at
  `/downloads`). Share it with Lidarr so it can import from there.
- **Libraries** — Lidarr's **root folders**, where Lidarr stores imported music.

Lidarr may use several root folders (e.g. `/data/library` and `/data/soundtracks`),
and the container paths inside Lidarr and inside AlbFetcharr can differ. After an
import, AlbFetcharr asks the Lidarr API for the album's path (a *Lidarr* path) and
copies cover art next to it — so it needs to translate that path to its own view.
That translation is `ALBFETCHARR_LIBRARY_MAP`:

```
ALBFETCHARR_LIBRARY_MAP=<lidarr_path>=<albfetcharr_path>,<lidarr_path2>=<albfetcharr_path2>
```

**Single library:**

| Container   | Path                | Host                |
|-------------|---------------------|---------------------|
| Lidarr      | `/data/library`     | `/mnt/music`        |
| Lidarr      | `/data/downloads`   | `/mnt/downloads`    |
| AlbFetcharr | `/downloads`        | `/mnt/downloads/alb`|
| AlbFetcharr | `/libraries/music`  | `/mnt/music`        |

```
ALBFETCHARR_LIBRARY_MAP=/data/library=/libraries/music
ALBFETCHARR_LIDARR_IMPORT_PATH=/data/downloads/alb
```

**Multiple libraries** — add a mount and a map entry per root folder:

```
ALBFETCHARR_LIBRARY_MAP=/data/music=/libraries/music,/data/soundtracks=/libraries/soundtracks
```

On startup AlbFetcharr checks Lidarr's root folders via the API and warns if any
of them has no mapping entry.

### Lidarr setup

1. Get the Lidarr API key: **Settings → General → API Key**.
2. Make sure Lidarr has wanted albums (status *Missing*).
3. AlbFetcharr imports via the ManualImport API — no Lidarr Download Client
   configuration is required.

### Sources

| Source        | Requirement                | Notes                                                                       |
|---------------|----------------------------|-----------------------------------------------------------------------------|
| Yandex Music  | `YANDEX_MUSIC_TOKEN`       | Most accurate search, best metadata; AAC 64/192 or FLAC                      |
| YouTube Music | on by default              | Anonymous search gets bot-gated by YouTube → empty results; OAuth recommended |
| SoundCloud    | on by default              | Sets/playlists; search can be loose, tags may be incomplete                 |
| Bandcamp      | on by default              | Real albums with correct tags; mostly indie/self-releases; free stream is MP3 128 |

For the **YouTube cookies** and **YouTube Music OAuth** setup (both optional —
without them search/download still work for the other sources), and for the full
per-source behavior, see the
[backend README](https://github.com/semsemyonoff/AlbFetcharr-backend#sources).
The relevant paths (`ALBFETCHARR_YTDLP_COOKIES`, `ALBFETCHARR_YTMUSIC_OAUTH`) are
container paths under the mounted `/config`.

> yt-dlp's YouTube extractor needs a JS runtime (`deno`) and the `yt-dlp-ejs`
> solver to clear YouTube's signature/n-challenge. Both are **baked into the
> image** — nothing to install when self-hosting via Docker.

### Environment variables

The essentials for a deployment:

| Variable                          | Default                     | Description                                                  |
|-----------------------------------|-----------------------------|--------------------------------------------------------------|
| `ALBFETCHARR_IMAGE`               | `semsemyonoff/albfetcharr`  | Image repository                                             |
| `ALBFETCHARR_TAG`                 | `latest`                    | Image tag; pin to a release in prod                         |
| `ALBFETCHARR_HTTP_PORT`           | `8080`                      | Host port (container serves on 5000)                        |
| `ALBFETCHARR_CONFIG_DIR`          | `./config`                  | Host dir mounted to `/config` (settings DB, oauth, cookies) |
| `ALBFETCHARR_DOWNLOADS_DIR`       | `./downloads`               | Host dir mounted to `/downloads` (share with Lidarr)        |
| `ALBFETCHARR_LIBRARY_DIR`         | `./library`                 | Host dir mounted to `/libraries/music`                      |
| `LIDARR_URL`                      | —                           | Lidarr base URL (e.g. `http://lidarr:8686`)                 |
| `LIDARR_API_KEY`                  | —                           | Lidarr API key                                              |
| `YANDEX_MUSIC_TOKEN`              | —                           | Yandex Music auth token                                     |
| `YANDEX_MUSIC_QUALITY`            | `2`                         | `0` AAC 64, `1` AAC 192, `2` FLAC                           |
| `ALBFETCHARR_LIDARR_IMPORT_PATH`  | —                           | Download dir as Lidarr sees it (ManualImport)               |
| `ALBFETCHARR_LIBRARY_MAP`         | —                           | `lidarr_path=albfetcharr_path,…` (cover-art copy)           |
| `ALBFETCHARR_SECRET_KEY`          | —                           | Fernet key to encrypt secrets in the settings DB (optional) |
| `TZ`                              | `UTC`                       | Container timezone                                          |

This is the deployment-critical subset. The **complete reference** — every source
toggle, download tweak, network/retry knob, cookies/OAuth path, and the container
`UID`/`GID`/`UMASK` — lives in the
[backend README](https://github.com/semsemyonoff/AlbFetcharr-backend#environment-variables),
which is the app's config contract.

### Volumes

| Container path     | Source (env)                  | Purpose                                            |
|--------------------|-------------------------------|----------------------------------------------------|
| `/config`          | `ALBFETCHARR_CONFIG_DIR`      | Settings DB + optional `ytmusic_oauth.json` / `cookies.txt` |
| `/downloads`       | `ALBFETCHARR_DOWNLOADS_DIR`   | Download staging; shared with Lidarr               |
| `/libraries/music` | `ALBFETCHARR_LIBRARY_DIR`     | Lidarr root folder (cover-art copy after import)   |

### CLI mode

The same fetch flows run headless — useful for cron or one-off grabs:

```bash
# Fetch every wanted album and import into Lidarr
docker compose run --rm albfetcharr wanted

# Fetch without importing
docker compose run --rm albfetcharr wanted --no-import

# Restrict to one source (yandex / youtube_music / soundcloud / bandcamp)
docker compose run --rm albfetcharr wanted --source youtube_music

# Fetch a single album by URL (source auto-detected)
docker compose run --rm albfetcharr download "https://music.yandex.ru/album/12345"

# …with an explicit source
docker compose run --rm albfetcharr download --source soundcloud "https://soundcloud.com/..."
```

### Upgrade

Bump `ALBFETCHARR_TAG` in `.env`, then `make pull && make up`.
Handy commands: `make up` · `make down` · `make pull` · `make logs` · `make ps`.

### Migrating from Yamdarr

If you ran the old `semsemyonoff/yamdarr` image:

1. Change the image to `semsemyonoff/albfetcharr`.
2. Rename `YAMDARR_*` variables to `ALBFETCHARR_*`. Note that the three Yandex
   network knobs were renamed for accuracy (`YAMDARR_TIMEOUT` →
   `ALBFETCHARR_YANDEX_TIMEOUT`, and likewise `…_TRIES`, `…_RETRY_DELAY`), the
   path-pattern variables were removed (the path layout is now fixed in code),
   and `YAMDARR_AUTO_DOWNLOAD` / `YAMDARR_AUTO_CRON` are gone — background
   auto-download was removed; trigger fetches from the UI or CLI.

Unchanged: `LIDARR_URL`, `LIDARR_API_KEY`, `YANDEX_MUSIC_TOKEN`,
`YANDEX_MUSIC_QUALITY`, `DOWNLOAD_DIR`, `UID`, `GID`, `UMASK`.

---

## For maintainers (cutting a release)

A release is **reproducible**: one (backend, frontend) commit pair → one product
version → one multi-arch image, built from a self-contained `Dockerfile` (stage 1
builds the SPA, stage 2 is the backend runtime with `deno` for yt-dlp's YouTube
solver).

### Where the image is published

The same image is pushed to all registries by CI. Operators can pull from
whichever they like via `ALBFETCHARR_IMAGE` in `.env`:

| Registry   | Image ref                          | Built by        | Audience          |
|------------|------------------------------------|-----------------|-------------------|
| Docker Hub | `semsemyonoff/albfetcharr`         | GitHub Actions  | public (default)  |
| GHCR       | `ghcr.io/semsemyonoff/albfetcharr` | GitHub Actions  | public            |
| git.horn   | `git.horn/albfetcharr/app`         | Forgejo Actions | internal infra    |

The Forgejo repo is the source of truth and push-mirrors to GitHub.

### Cutting a release (the one button)

Run **Forgejo → Actions → Cut release → Run workflow**, pick a bump
(`patch`/`minor`/`major`). The `release-cut` workflow then:

1. repins `backend`/`frontend` to their latest semver tag (or a ref you pass);
2. bumps `VERSION`;
3. promotes the `CHANGELOG.md` `[Unreleased]` section to `[X.Y.Z] - <date>`
   (write your release notes there before cutting — that text is the release body);
4. commits `release: X.Y.Z`, tags `vX.Y.Z`, and pushes.

The tag fans out to the build pipelines: `.forgejo/workflows/release.yml` builds
and pushes the image on internal infra (git.horn), and — via the mirror —
`.github/workflows/release.yml` pushes Docker Hub + GHCR. It must be triggered on
Forgejo because the mirror is one-way (Forgejo → GitHub), so the tag has to
originate there.

A **Release** page is created on each platform from the same CHANGELOG section
(notes only, no attached assets): Forgejo via its API in `release-cut`, GitHub
via `action-gh-release` in the public build. Release objects aren't mirrored, so
each side publishes its own — that's expected.

### One-time setup

- **Push mirror** (Forgejo repo → Settings → Mirror → Push): mirror this repo to
  `github.com/semsemyonoff/AlbFetcharr-deploy` (or wherever the public copy lives)
  with a GitHub PAT, so tags/commits propagate and trigger the public build.
- **GitHub secrets:** `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (GHCR uses the
  built-in `GITHUB_TOKEN`).
- **Forgejo Actions secrets** (names can't start with `FORGEJO_`/`GITEA_`/`GITHUB_`):
  `HORN_REGISTRY_USER` + `HORN_REGISTRY_TOKEN` (a token with `write:package`) for
  the registry push, and `RELEASE_TOKEN` (a PAT with repo write) used by
  `release-cut` to push the tag. It must be a PAT — a tag pushed by the automatic
  Actions token would not trigger the build jobs.
- **Runner CA:** add the internal registry host to `FORGEJO_RUNNER_DOCKER_CA_HOSTS`
  in the git stack's `.env` and redeploy the runner, so its Docker daemon trusts
  the registry's CA when pushing (otherwise the push fails with x509).

### Local fallback

CI is the primary path, but the same build runs locally with Docker only:

```bash
git submodule update --init --recursive
git -C backend checkout <tag> && git -C frontend checkout <tag> && git add backend frontend
make release VERSION=1.0.0           # builds + pushes (override targets via IMAGES=...)
```

Smoke-test a build without pushing:

```bash
make release-local VERSION=1.0.0
ALBFETCHARR_TAG=1.0.0 docker compose up -d
```

### Relationship to the DWE dev workspace

The `AlbFetcharr` DWE workspace remains the **development** environment (live
bind-mounts, Vite HMR, separate backend/frontend/lidarr dev containers). This
repo is strictly about producing and running the **release** artifact. The two
are independent; nothing here changes the dev workflow.

---

## Disclaimer

This is an independent project, not affiliated with Yandex, Google, or SoundCloud.

Downloading music from the internet may be restricted by copyright law in your
jurisdiction. **You are solely responsible for ensuring your use complies with
local law.** When using YouTube Music and SoundCloud as sources, mind those
services' terms of use — automated downloading via yt-dlp may violate them.
