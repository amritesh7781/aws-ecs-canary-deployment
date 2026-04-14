#!/usr/bin/env bash
# build.sh — build v1 and v2 images with multi-arch support (linux/amd64 + linux/arm64)
#
# Usage:
#   ./build.sh                        # build both versions, local load (single-arch, current platform)
#   ./build.sh --push                 # build both versions, push multi-arch manifest to registry
#   ./build.sh --version v1           # build only v1
#   ./build.sh --version v2           # build only v2
#   ./build.sh --registry my.ecr/repo # override image registry/repo
#   ./build.sh --push --registry my.ecr/repo --version v2
#
# Requirements:
#   - Docker with Buildx (Docker Desktop or 'docker buildx install')
#   - For --push: authenticated registry (ECR, GHCR, Docker Hub, etc.)
#
# Local load note:
#   'docker buildx build --load' only supports a single platform at a time.
#   Without --push the script builds each arch separately and loads the image
#   for your current platform so docker compose can use it immediately.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
REGISTRY="${REGISTRY:-amritesh/canary}"       # prefix / repo name
PLATFORMS="linux/amd64,linux/arm64"
BUILDER_NAME="canary-multiarch"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PUSH=false
TARGET_VERSION=""                          # empty = build both

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)         PUSH=true;              shift ;;
    --version)      TARGET_VERSION="$2";   shift 2 ;;
    --registry)     REGISTRY="$2";         shift 2 ;;
    --platforms)    PLATFORMS="$2";        shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}▸${RESET} $*"; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

# ── Ensure buildx builder ─────────────────────────────────────────────────────
ensure_builder() {
  if docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    log "Using existing buildx builder '${BUILDER_NAME}'"
  else
    log "Creating multi-arch buildx builder '${BUILDER_NAME}'"
    docker buildx create \
      --name "$BUILDER_NAME" \
      --driver docker-container \
      --platform "$PLATFORMS" \
      --bootstrap
    ok "Builder ready"
  fi
}

# ── Build one version ─────────────────────────────────────────────────────────
build_version() {
  local version="$1"          # v1 | v2
  local version_label="$2"    # 1.0.0 | 2.0.0
  local image_tag="${REGISTRY}:${version}"

  echo
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  Building ${version} (${version_label})${RESET}"
  echo -e "${BOLD}  Image  : ${image_tag}${RESET}"
  echo -e "${BOLD}  Archs  : ${PLATFORMS}${RESET}"
  echo -e "${BOLD}  Push   : ${PUSH}${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  local build_args=(
    --builder "$BUILDER_NAME"
    --file   "./app/Dockerfile"
    --build-arg "VERSION=${version}"
    --build-arg "VERSION_LABEL=${version_label}"
    --build-arg "BUILD_TIME=${BUILD_TIME}"
    --tag    "${image_tag}"
    --tag    "${REGISTRY}:${version}-${BUILD_TIME//[:T]/-}"   # timestamped tag
  )

  if [[ "$PUSH" == true ]]; then
    # Multi-arch push: builds both platforms and pushes a combined manifest
    docker buildx build \
      "${build_args[@]}" \
      --platform "$PLATFORMS" \
      --push \
      ./app

    ok "Pushed multi-arch manifest: ${image_tag}"
    echo
    log "Manifest digest:"
    docker buildx imagetools inspect "${image_tag}" | grep -E "^(Name|Digest|MediaType|Platform)" || true

  else
    # Local load: buildx --load only supports one platform at a time.
    # Detect host arch and load only that platform so docker compose works.
    local host_arch
    host_arch="$(uname -m)"
    local load_platform
    case "$host_arch" in
      arm64|aarch64) load_platform="linux/arm64" ;;
      *)             load_platform="linux/amd64"  ;;
    esac

    warn "Local load: building for host platform only (${load_platform})"
    warn "Use --push to build and store a true multi-arch manifest in a registry"

    docker buildx build \
      "${build_args[@]}" \
      --platform "$load_platform" \
      --load \
      ./app

    ok "Loaded ${image_tag} (${load_platform}) into local Docker daemon"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}  ECS Canary Demo — Multi-Arch Image Builder${RESET}"
echo -e "  Build time : ${BUILD_TIME}"
echo -e "  Platforms  : ${PLATFORMS}"
echo

# Check Docker is running
docker info &>/dev/null || err "Docker daemon is not running"

ensure_builder

case "$TARGET_VERSION" in
  v1)   build_version v1 "1.0.0" ;;
  v2)   build_version v2 "2.0.0" ;;
  "")   build_version v1 "1.0.0"
        build_version v2 "2.0.0" ;;
  *)    err "Unknown version '${TARGET_VERSION}'. Use v1 or v2." ;;
esac

echo
echo -e "${GREEN}${BOLD}All builds complete!${RESET}"

if [[ "$PUSH" == false ]]; then
  echo
  echo -e "  Start the local demo:"
  echo -e "  ${CYAN}docker compose up${RESET}"
  echo -e "  Then open ${CYAN}http://localhost:8080${RESET}"
fi
