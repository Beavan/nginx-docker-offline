#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-nginx-docker}"
INSTALL_DIR="${INSTALL_DIR:-/opt/nginx-docker}"
CONFIG_FILE="${CONFIG_FILE:-/etc/default/${SERVICE_NAME}}"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

ENV_FILE="${INSTALL_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
fi

CONTAINER_NAME="${CONTAINER_NAME:-nginx-server}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
NGINX_IMAGE_TAG="${NGINX_IMAGE_TAG:-nginx:stable}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
export CONTAINER_NAME HTTP_PORT HTTPS_PORT NGINX_IMAGE_TAG

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

  echo "Docker Compose is not available." >&2
  exit 1
}

compose() {
  local runner
  runner="$(compose_cmd)"
  # shellcheck disable=SC2086
  ${runner} -f "${COMPOSE_FILE}" "$@"
}

usage() {
  cat <<USAGE
Usage: nginx-docker <command>

Commands:
  start       Start nginx service
  stop        Stop nginx service
  restart     Restart nginx service
  reload      Reload nginx inside the container
  status      Show systemd and container status
  logs        Follow nginx container logs
  ps          Show compose containers
  configtest  Validate nginx configuration
USAGE
}

case "${1:-}" in
  _up)
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    compose up -d
    ;;
  _down)
    compose down || true
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    ;;
  _reload)
    compose exec -T nginx nginx -s reload
    ;;
  start)
    systemctl start "${SERVICE_NAME}.service"
    ;;
  stop)
    systemctl stop "${SERVICE_NAME}.service"
    ;;
  restart)
    systemctl restart "${SERVICE_NAME}.service"
    ;;
  reload)
    systemctl reload "${SERVICE_NAME}.service"
    ;;
  status)
    systemctl status "${SERVICE_NAME}.service" --no-pager
    compose ps
    ;;
  logs)
    compose logs -f --tail=200 nginx
    ;;
  ps)
    compose ps
    ;;
  configtest)
    compose exec -T nginx nginx -t
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
