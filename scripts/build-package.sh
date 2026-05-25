#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PARENT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"

PACKAGE_VERSION="${PACKAGE_VERSION:-$(date '+%Y%m%d%H%M%S')}"
PACKAGE_NAME="${PACKAGE_NAME:-nginx-offline-installer}"

DOCKER_ASSET_NAME="docker-x86_64.tgz"
COMPOSE_ASSET_NAME="docker-compose-linux-x86_64"
COMPOSE_CHECKSUM_NAME="docker-compose-linux-x86_64.sha256"
NGINX_ASSET_NAME="nginx-stable.tar.gz"
DOCKER_SOURCE_NAME="docker-28.1.1.tgz"
COMPOSE_SOURCE_NAME="docker-compose-linux-x86_64"
COMPOSE_CHECKSUM_SOURCE_NAME="docker-compose-linux-x86_64.sha256"
NGINX_SOURCE_NAME="nginx_stable.tar.gz"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

stage_asset() {
  local source="$1"
  local target="$2"
  local label="$3"

  if [[ -f "${target}" ]]; then
    echo "exists: ${target}"
    return
  fi

  if [[ ! -f "${source}" ]]; then
    echo "Missing ${label}: ${source}" >&2
    exit 1
  fi

  echo "stage ${label}: ${source} -> ${target}"
  mv "${source}" "${target}"
  chmod 0644 "${target}"
}

require_cmd sha256sum
require_cmd tar

mkdir -p "${ROOT_DIR}/assets/docker" "${ROOT_DIR}/assets/compose" "${ROOT_DIR}/assets/images" "${ROOT_DIR}/dist"

stage_asset \
  "${PARENT_DIR}/${DOCKER_SOURCE_NAME}" \
  "${ROOT_DIR}/assets/docker/${DOCKER_ASSET_NAME}" \
  "Docker offline asset"

stage_asset \
  "${PARENT_DIR}/${COMPOSE_SOURCE_NAME}" \
  "${ROOT_DIR}/assets/compose/${COMPOSE_ASSET_NAME}" \
  "Docker Compose offline asset"

stage_asset \
  "${PARENT_DIR}/${COMPOSE_CHECKSUM_SOURCE_NAME}" \
  "${ROOT_DIR}/assets/compose/${COMPOSE_CHECKSUM_NAME}" \
  "Docker Compose checksum"

stage_asset \
  "${PARENT_DIR}/${NGINX_SOURCE_NAME}" \
  "${ROOT_DIR}/assets/images/${NGINX_ASSET_NAME}" \
  "nginx image asset"

chmod 0644 \
  "${ROOT_DIR}/assets/docker/${DOCKER_ASSET_NAME}" \
  "${ROOT_DIR}/assets/compose/${COMPOSE_ASSET_NAME}" \
  "${ROOT_DIR}/assets/compose/${COMPOSE_CHECKSUM_NAME}" \
  "${ROOT_DIR}/assets/images/${NGINX_ASSET_NAME}"

(
  cd "${ROOT_DIR}/assets/compose"
  sha256sum -c "${COMPOSE_CHECKSUM_NAME}"
)

(
  cd "${ROOT_DIR}"
  sha256sum \
    "assets/docker/${DOCKER_ASSET_NAME}" \
    "assets/compose/${COMPOSE_ASSET_NAME}" \
    "assets/images/${NGINX_ASSET_NAME}" > SHA256SUMS
)

package_dir="$(basename "${ROOT_DIR}")"
archive="${ROOT_DIR}/dist/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
tar \
  --exclude="${package_dir}/dist" \
  --exclude="${package_dir}/dist/*" \
  --exclude="${package_dir}/.git" \
  -C "${ROOT_DIR}/.." \
  -czf "${archive}" \
  "${package_dir}"

echo "created: ${archive}"
