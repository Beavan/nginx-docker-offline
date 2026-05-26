#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PARENT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"

PACKAGE_VERSION="${PACKAGE_VERSION:-$(date '+%Y%m%d%H%M%S')}"
PACKAGE_NAME="${PACKAGE_NAME:-nginx-offline-installer}"
PACKAGE_MODE="dev"

DOCKER_ASSET_NAME="docker-x86_64.tgz"
COMPOSE_ASSET_NAME="docker-compose-linux-x86_64"
COMPOSE_CHECKSUM_NAME="docker-compose-linux-x86_64.sha256"
NGINX_ASSET_NAME="nginx-stable.tar.gz"
DOCKER_SOURCE_NAME="docker-28.1.1.tgz"
COMPOSE_SOURCE_NAME="docker-compose-linux-x86_64"
COMPOSE_CHECKSUM_SOURCE_NAME="docker-compose-linux-x86_64.sha256"
NGINX_SOURCE_NAME="nginx_stable.tar.gz"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dev|--release]

Options:
  --dev       Build the full development package. This is the default.
  --release   Build a minimal install-only release package.
  -h, --help  Show this help message.
USAGE
}

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

build_dev_package() {
  local package_dir="$1"
  local archive="$2"

  tar \
    --exclude="${package_dir}/dist" \
    --exclude="${package_dir}/dist/*" \
    --exclude="${package_dir}/.git" \
    -C "${ROOT_DIR}/.." \
    -czf "${archive}" \
    "${package_dir}"
}

copy_release_path() {
  local source="$1"
  local target="$2"

  mkdir -p "$(dirname "${target}")"
  cp -R "${source}" "${target}"
}

build_release_package() {
  local package_dir="$1"
  local archive="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '${tmp_dir}'" EXIT

  local stage_dir="${tmp_dir}/${package_dir}"
  mkdir -p "${stage_dir}"

  copy_release_path "${ROOT_DIR}/install.sh" "${stage_dir}/install.sh"
  copy_release_path "${ROOT_DIR}/uninstall.sh" "${stage_dir}/uninstall.sh"
  copy_release_path "${ROOT_DIR}/manage.sh" "${stage_dir}/manage.sh"
  copy_release_path "${ROOT_DIR}/package.conf" "${stage_dir}/package.conf"
  copy_release_path "${ROOT_DIR}/docker-compose.yml" "${stage_dir}/docker-compose.yml"
  copy_release_path "${ROOT_DIR}/SHA256SUMS" "${stage_dir}/SHA256SUMS"
  copy_release_path "${ROOT_DIR}/assets" "${stage_dir}/assets"
  copy_release_path "${ROOT_DIR}/nginx" "${stage_dir}/nginx"
  copy_release_path "${ROOT_DIR}/systemd" "${stage_dir}/systemd"
  copy_release_path "${ROOT_DIR}/README.install.md" "${stage_dir}/README.md"

  find "${stage_dir}" -name '.DS_Store' -delete
  find "${stage_dir}" -name '.gitkeep' -delete

  tar -C "${tmp_dir}" -czf "${archive}" "${package_dir}"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dev)
      PACKAGE_MODE="dev"
      ;;
    --release)
      PACKAGE_MODE="release"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_cmd sha256sum
require_cmd tar
require_cmd cp
require_cmd find

if [[ "${PACKAGE_MODE}" == "release" && ! -f "${ROOT_DIR}/README.install.md" ]]; then
  echo "Missing release README source: ${ROOT_DIR}/README.install.md" >&2
  exit 1
fi

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

case "${PACKAGE_MODE}" in
  dev)
    build_dev_package "${package_dir}" "${archive}"
    ;;
  release)
    build_release_package "${package_dir}" "${archive}"
    ;;
esac

echo "created: ${archive}"
