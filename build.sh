#!/usr/bin/env bash
# Build and push the multi-arch AlbFetcharr production image from the pinned
# submodules. Build context is this repo root (see Dockerfile).
#
# Shared by the local `make release` AND by both CI pipelines (GitHub Actions →
# Docker Hub + GHCR; Forgejo Actions → git.horn). The caller picks the targets:
#
#   ALBFETCHARR_IMAGES   space/newline-separated list of image refs WITHOUT tag
#                        (default: semsemyonoff/albfetcharr). Every image is
#                        tagged with every ALBFETCHARR_TAGS value in a single
#                        buildx --push, so the image is built ONCE and fanned out
#                        to all targets.
#   ALBFETCHARR_TAGS     space-separated list of tags (default: latest)
#   ALBFETCHARR_VERSION  product version baked into the image as APP_VERSION (the
#                        backend reports it as GET /api/version and the OpenAPI
#                        info.version). Defaults to the first non-"latest" tag,
#                        then to ./VERSION, then 0.0.0 — so CI needs no extra
#                        wiring (the release version is already the first
#                        ALBFETCHARR_TAGS value).
#   ALBFETCHARR_PLATFORMS  buildx platforms (default: linux/amd64,linux/arm64)
#
# `docker login` to each target registry must already be done by the caller.
# Back-compat: the old singular ALBFETCHARR_IMAGE / ALBFETCHARR_TAG are honored.
set -euo pipefail
cd "$(dirname "$0")"

IMAGES="${ALBFETCHARR_IMAGES:-${ALBFETCHARR_IMAGE:-semsemyonoff/albfetcharr}}"
TAGS="${ALBFETCHARR_TAGS:-${ALBFETCHARR_TAG:-latest}}"
PLATFORMS="${ALBFETCHARR_PLATFORMS:-linux/amd64,linux/arm64}"

# Product version baked into the image (APP_VERSION). Prefer an explicit
# ALBFETCHARR_VERSION; otherwise take the first tag that isn't "latest" (CI
# passes "$version latest"), then fall back to ./VERSION, then 0.0.0.
VERSION="${ALBFETCHARR_VERSION:-}"
if [ -z "$VERSION" ]; then
    for t in $TAGS; do
        if [ "$t" != latest ]; then VERSION="$t"; break; fi
    done
fi
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"

for sub in backend frontend; do
    if [ ! -e "$sub/.git" ]; then
        echo "ERROR: submodule '$sub' not initialized — run 'git submodule update --init'." >&2
        exit 1
    fi
done

# Fan out: one --tag per (image, tag) pair → built once, pushed everywhere.
tag_args=()
refs=()
for img in $IMAGES; do
    for t in $TAGS; do
        tag_args+=( --tag "${img}:${t}" )
        refs+=( "${img}:${t}" )
    done
done
echo ">> building ${PLATFORMS} (APP_VERSION=${VERSION}) and pushing:"
printf '   %s\n' "${refs[@]}"

# Pick the buildx builder.
#   ALBFETCHARR_BUILDER set -> use it as-is (e.g. "default" on a daemon with the
#                             containerd image store, which multi-arch-builds and
#                             pushes through the daemon itself — so it inherits the
#                             daemon's DNS and registry CA trust; needed for the
#                             internal git.horn push from the Forgejo dind runner).
#   unset                   -> manage a docker-container builder, required where
#                             the default builder can't do multi-arch (GitHub
#                             runners, local Docker without the containerd store).
if [ -n "${ALBFETCHARR_BUILDER:-}" ]; then
    docker buildx use "$ALBFETCHARR_BUILDER"
else
    BUILDER="albfetcharr-multiarch"
    if ! docker buildx inspect "$BUILDER" &>/dev/null; then
        docker buildx create --name "$BUILDER" --use
    else
        docker buildx use "$BUILDER"
    fi
fi

docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg "APP_VERSION=${VERSION}" \
    "${tag_args[@]}" \
    --push .
