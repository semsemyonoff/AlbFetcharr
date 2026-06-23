# AlbFetcharr release & deployment orchestration.
#
# Two audiences:
#   - Operators self-hosting a published image: `make up` / `make down` / `make pull` / `make logs`.
#   - Maintainers cutting a release: normally via CI — the "Cut release" button
#     (.forgejo/workflows/release-cut.yml) tags vX.Y.Z, which fans out to the
#     build pipelines (GitHub → Docker Hub + GHCR; Forgejo → git.horn). See README.
#     `make release VERSION=1.0.0` remains a LOCAL FALLBACK that builds the same
#     image (SPA + API, multi-arch) from the PINNED submodules and pushes it.
#
# The submodules (backend/, frontend/) pin the exact commits a release is built
# from — one product version = one (backend, frontend) pair. The build is
# self-contained (see Dockerfile); it does NOT need the DWE dev stack.

SHELL := /bin/bash

# Local fallback target list. CI passes its own ALBFETCHARR_IMAGES (GitHub →
# Docker Hub + GHCR; Forgejo → git.horn/albfetcharr/app). See build.sh.
IMAGES  ?= semsemyonoff/albfetcharr
IMAGE   ?= $(firstword $(IMAGES))
VERSION ?= $(shell cat VERSION 2>/dev/null)

.PHONY: help up down restart pull logs ps submodules release release-local

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ----- Operator targets (run a published image) -----

up: ## Start the stack (reads .env)
	docker compose up -d

down: ## Stop and remove the stack
	docker compose down

restart: ## Recreate the stack
	docker compose up -d --force-recreate

pull: ## Pull the image tag pinned in .env
	docker compose pull

logs: ## Tail logs
	docker compose logs -f

ps: ## Show container status
	docker compose ps

## ----- Maintainer targets (build & publish from submodules) -----

submodules: ## Init/update the pinned backend & frontend submodules
	git submodule update --init --recursive

release: submodules ## Build multi-arch image VERSION + latest and push (VERSION=x.y.z). CI is the primary path; this is a local fallback.
	@test -n "$(VERSION)" || { echo "ERROR: set VERSION (or write it to ./VERSION)" >&2; exit 1; }
	ALBFETCHARR_IMAGES="$(IMAGES)" ALBFETCHARR_TAGS="$(VERSION) latest" ./build.sh

release-local: submodules ## Build a single-arch image locally (no push) for testing
	@test -n "$(VERSION)" || { echo "ERROR: set VERSION" >&2; exit 1; }
	docker build --build-arg "APP_VERSION=$(VERSION)" -t "$(IMAGE):$(VERSION)" .
