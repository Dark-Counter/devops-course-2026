#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT}/site/"

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY=1
elif [[ $# -gt 0 ]]; then
  echo "Неизвестный аргумент: $1" >&2
  exit 1
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  echo "Нет файла site/index.html, доставка отменена." >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Есть незафиксированные изменения, доставка отменена." >&2
  exit 1
fi

choose_rsync() {
  local candidate
  for candidate in \
    rsync \
    "/Users/timofej/Mirea-Sdo/.local-devops/rsync/bin/rsync"
  do
    if [[ -x "$candidate" || "$candidate" == "rsync" ]] \
      && "$candidate" --chmod=D755,F644 --version >/dev/null 2>&1
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if ! RSYNC="$(choose_rsync)"; then
  echo "Нужен GNU rsync: параметр --chmod=D755,F644 не поддерживается." >&2
  exit 1
fi

args=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ "$DRY" -eq 1 ]]; then
  args+=(--dry-run)
fi

"$RSYNC" "${args[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}"

if [[ "$DRY" -eq 1 ]]; then
  exit 0
fi

if ! curl -4 -fsS --noproxy '*' --cacert "$CA_CERT" --connect-timeout 5 -o /dev/null "$SITE_URL"; then
  echo "Ресурс ${SITE_URL} недоступен." >&2
  exit 1
fi

echo "Доставлен коммит $(git -C "$ROOT" rev-parse --short HEAD)"
