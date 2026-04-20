#!/bin/bash
set -euo pipefail

HOME_DIR="$(eval echo ~)"

# Copia seeds apenas se o destino estiver vazio
copy_seed() {
  local src="$1" dst="$2"
  if [ -d "$src" ] && [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
  fi
}

copy_seed "$HOME_DIR/.openclaw-seed"          "$HOME_DIR/.openclaw"
copy_seed "$HOME_DIR/.config-seed/fabric"     "$HOME_DIR/.config/fabric"
copy_seed "$HOME_DIR/.config-seed/sharepoint" "$HOME_DIR/.config/sharepoint"

OPENCLAW_CMD=$(command -v openclaw 2>/dev/null || true)
if [ -z "$OPENCLAW_CMD" ]; then
  echo "ERRO: binário openclaw não encontrado." >&2
  exit 1
fi

case "${1:-}" in
  gateway)
    exec "$OPENCLAW_CMD" gateway \
      --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
      --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
      --allow-unconfigured \
      "${@:2}"
    ;;
  *)
    exec "$OPENCLAW_CMD" "$@"
    ;;
esac
