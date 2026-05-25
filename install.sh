#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/package.conf"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi

  if [[ -x /usr/local/bin/docker-compose ]] && /usr/local/bin/docker-compose version >/dev/null 2>&1; then
    echo "/usr/local/bin/docker-compose"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi

  fail "Docker Compose is not available after offline installation."
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Please run as root."
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    *) fail "Unsupported architecture: $(uname -m). This offline package only includes x86_64 Docker binaries." ;;
  esac
}

require_linux_systemd() {
  [[ "$(uname -s)" == "Linux" ]] || fail "Only Linux is supported."
  command -v systemctl >/dev/null 2>&1 || fail "systemd is required."
}

verify_assets() {
  local checksum_file="${SCRIPT_DIR}/SHA256SUMS"
  if [[ ! -f "${checksum_file}" ]]; then
    log "SHA256SUMS not found; skipping package checksum verification."
    return
  fi

  command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required to verify offline package assets."
  log "Verifying offline package checksums."
  (cd "${SCRIPT_DIR}" && sha256sum -c SHA256SUMS)
}

install_docker_group() {
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker
  fi
}

docker_service_exists() {
  [[ -f /etc/systemd/system/docker.service || -f /usr/lib/systemd/system/docker.service || -f /lib/systemd/system/docker.service ]]
}

install_docker_systemd_units() {
  install_docker_group
  install -m 0644 "${SCRIPT_DIR}/systemd/containerd.service" /etc/systemd/system/containerd.service
  install -m 0644 "${SCRIPT_DIR}/systemd/docker.socket" /etc/systemd/system/docker.socket
  install -m 0644 "${SCRIPT_DIR}/systemd/docker.service" /etc/systemd/system/docker.service
  systemctl daemon-reload
}

install_docker_offline() {
  local arch="$1"
  local asset="${SCRIPT_DIR}/${DOCKER_ASSET_DIR}/docker-${arch}.tgz"

  if command -v docker >/dev/null 2>&1 && command -v dockerd >/dev/null 2>&1; then
    log "Docker is already installed: $(docker --version 2>/dev/null || true)"
    if ! docker_service_exists; then
      log "Docker systemd units were not found; installing bundled units."
      install_docker_systemd_units
    fi
    return
  fi

  [[ -f "${asset}" ]] || fail "Missing offline Docker asset: ${asset}"
  log "Installing bundled Docker 28.1.1 from ${asset}"
  if systemctl is-active --quiet docker.service 2>/dev/null; then
    systemctl stop docker.service
  fi
  if systemctl is-active --quiet containerd.service 2>/dev/null; then
    systemctl stop containerd.service
  fi
  tar -xzf "${asset}" -C /tmp
  install -m 0755 /tmp/docker/* /usr/local/bin/
  rm -rf /tmp/docker

  install_docker_systemd_units
  systemctl enable --now containerd.service
  systemctl enable --now docker.socket
  systemctl enable --now docker.service
}

install_compose_offline() {
  local arch="$1"
  local asset="${SCRIPT_DIR}/${COMPOSE_ASSET_DIR}/docker-compose-linux-${arch}"
  local checksum="${asset}.sha256"
  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  local plugin_bin="${plugin_dir}/docker-compose"

  [[ -f "${asset}" ]] || fail "Missing offline Docker Compose asset: ${asset}"
  if [[ -f "${checksum}" ]]; then
    log "Verifying Docker Compose checksum."
    (cd "$(dirname "${asset}")" && sha256sum -c "$(basename "${checksum}")")
  fi

  log "Installing Docker Compose from ${asset}"
  install -d -m 0755 "${plugin_dir}"
  install -m 0755 "${asset}" "${plugin_bin}"
  ln -sfn "${plugin_bin}" /usr/local/bin/docker-compose

  log "Docker Compose installed: $($(compose_cmd) version --short 2>/dev/null || $(compose_cmd) version 2>/dev/null || true)"
  compose_cmd >/dev/null
}

start_docker() {
  systemctl daemon-reload
  systemctl enable --now containerd.service >/dev/null 2>&1 || true
  systemctl enable --now docker.socket >/dev/null 2>&1 || true
  systemctl enable --now docker.service

  for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  fail "Docker daemon did not become ready."
}

load_nginx_image() {
  local image_tar="${SCRIPT_DIR}/${NGINX_IMAGE_TAR}"

  if docker image inspect "${NGINX_IMAGE_TAG}" >/dev/null 2>&1; then
    log "Nginx image already exists: ${NGINX_IMAGE_TAG}"
    return
  fi

  [[ -f "${image_tar}" ]] || fail "Missing nginx image tar: ${image_tar}"
  log "Loading nginx image from ${image_tar}"
  docker load -i "${image_tar}"
  docker image inspect "${NGINX_IMAGE_TAG}" >/dev/null 2>&1 || fail "Loaded image does not contain tag ${NGINX_IMAGE_TAG}."
}

install_nginx_files() {
  log "Installing nginx compose files to ${INSTALL_DIR}"
  install -d -m 0755 "${INSTALL_DIR}"
  install -d -m 0755 "${INSTALL_DIR}/nginx/conf.d" "${INSTALL_DIR}/nginx/html" "${INSTALL_DIR}/nginx/certs" "${INSTALL_DIR}/logs"

  install -m 0644 "${SCRIPT_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
  install -m 0644 "${SCRIPT_DIR}/nginx/nginx.conf" "${INSTALL_DIR}/nginx/nginx.conf"
  install -m 0644 "${SCRIPT_DIR}/nginx/conf.d/default.conf" "${INSTALL_DIR}/nginx/conf.d/default.conf"
  install -m 0644 "${SCRIPT_DIR}/nginx/html/index.html" "${INSTALL_DIR}/nginx/html/index.html"

  cat > "${INSTALL_DIR}/.env" <<ENV
SERVICE_NAME=${SERVICE_NAME}
CONTAINER_NAME=${CONTAINER_NAME}
HTTP_PORT=${HTTP_PORT}
HTTPS_PORT=${HTTPS_PORT}
NGINX_IMAGE_TAG=${NGINX_IMAGE_TAG}
ENV
  chmod 0644 "${INSTALL_DIR}/.env"
}

register_service() {
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  local defaults_file="/etc/default/${SERVICE_NAME}"
  log "Registering systemd service ${SERVICE_NAME}.service"
  sed \
    -e "s#/opt/nginx-docker#${INSTALL_DIR}#g" \
    -e "s#/usr/local/bin/nginx-docker#${MANAGER_BIN}#g" \
    "${SCRIPT_DIR}/systemd/nginx-docker.service" > "${service_file}"
  chmod 0644 "${service_file}"

  cat > "${defaults_file}" <<ENV
SERVICE_NAME=${SERVICE_NAME}
INSTALL_DIR=${INSTALL_DIR}
CONTAINER_NAME=${CONTAINER_NAME}
HTTP_PORT=${HTTP_PORT}
HTTPS_PORT=${HTTPS_PORT}
NGINX_IMAGE_TAG=${NGINX_IMAGE_TAG}
ENV
  chmod 0644 "${defaults_file}"

  install -m 0755 "${SCRIPT_DIR}/manage.sh" "${MANAGER_BIN}"
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"
}

start_nginx() {
  local runner
  log "Starting ${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}.service"
  runner="$(compose_cmd)"
  # shellcheck disable=SC2086
  ${runner} -f "${INSTALL_DIR}/docker-compose.yml" ps
}

main() {
  require_root
  require_linux_systemd
  verify_assets

  local arch
  arch="$(detect_arch)"
  log "Detected architecture: ${arch}"

  install_docker_offline "${arch}"
  start_docker
  install_compose_offline "${arch}"
  load_nginx_image
  install_nginx_files
  register_service
  start_nginx

  log "Install completed. Manage with: ${MANAGER_BIN} status"
}

main "$@"
