#!/bin/bash

set -euo pipefail

RED='\033[31;1m'
GREEN='\033[32;1m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

DEADSHOT_BUILD_UTC="2026-04-26T16:09:30Z"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRC_DIR="$SCRIPT_DIR"
if [ -d "${SCRIPT_DIR}/core" ] && [ -f "${SCRIPT_DIR}/core/deadshot.sh" ]; then
  SRC_DIR="${SCRIPT_DIR}/core"
fi
DEST_DIR="/opt/deadshot"
ETC_DIR="/etc/deadshot"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

BUILD_UTC="$DEADSHOT_BUILD_UTC"
if [ "$BUILD_UTC" = "2026-04-26T16:09:30Z" ] && [ -f "${SCRIPT_DIR}/SHA256SUMS" ]; then
  BUILD_UTC="$(date -u -r "${SCRIPT_DIR}/SHA256SUMS" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
fi

if [ "$(uname -s)" != "Linux" ]; then
  echo -e "${RED}[!] Execução bloqueada: Linux obrigatório.${NC}"
  exit 1
fi

if [ "${EUID:-0}" -ne 0 ]; then
  echo -e "${RED}[!] Execução bloqueada: requer root.${NC}"
  echo -e "${DARK_GRAY}[*] Usa: sudo ./install.sh${NC}"
  exit 1
fi

if [ ! -f "${SRC_DIR}/deadshot.sh" ]; then
  echo -e "${RED}[!] Fonte inválida: deadshot.sh não encontrado em ${SRC_DIR}.${NC}"
  exit 1
fi

if [ -d "$DEST_DIR" ]; then
  echo -e "${DARK_GRAY}[*] Backup de ${DEST_DIR} -> ${DEST_DIR}.bak.${TIMESTAMP}${NC}"
  mv -- "$DEST_DIR" "${DEST_DIR}.bak.${TIMESTAMP}"
fi

mkdir -p "$DEST_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude ".git/" "${SRC_DIR}/" "${DEST_DIR}/"
else
  cp -a "${SRC_DIR}/." "${DEST_DIR}/"
fi

chmod 755 "${DEST_DIR}/deadshot.sh" "${DEST_DIR}/deadshot_core_launcher.sh" 2>/dev/null || true

if [ "$SRC_DIR" != "$SCRIPT_DIR" ]; then
  if [ -f "${SCRIPT_DIR}/SHA256SUMS" ]; then
    cp -a "${SCRIPT_DIR}/SHA256SUMS" "${DEST_DIR}/SHA256SUMS" 2>/dev/null || true
  fi
  if [ -f "${SCRIPT_DIR}/deadshot.conf.example" ]; then
    cp -a "${SCRIPT_DIR}/deadshot.conf.example" "${DEST_DIR}/deadshot.conf.example" 2>/dev/null || true
  fi
fi

mkdir -p "$ETC_DIR"
CFG_SRC="${DEST_DIR}/Deadshot-Tools/deadshot-raw/deadshot.conf"
if [ ! -f "$CFG_SRC" ] && [ -f "${DEST_DIR}/deadshot.conf.example" ]; then
  CFG_SRC="${DEST_DIR}/deadshot.conf.example"
fi
CFG_DST="${ETC_DIR}/deadshot.conf"

if [ ! -f "$CFG_SRC" ]; then
  echo -e "${RED}[!] Config de origem não encontrada: ${CFG_SRC}${NC}"
  exit 1
fi

if [ -f "$CFG_DST" ]; then
  echo -e "${DARK_GRAY}[*] Backup de ${CFG_DST} -> ${CFG_DST}.bak.${TIMESTAMP}${NC}"
  cp -a "$CFG_DST" "${CFG_DST}.bak.${TIMESTAMP}"
fi

cp -a "$CFG_SRC" "$CFG_DST"
chmod 600 "$CFG_DST"

echo -e "${GREEN}[+] Instalado em: ${DEST_DIR}${NC}"
echo -e "${GREEN}[+] Config inicial: ${CFG_DST}${NC}"
if [ -n "$BUILD_UTC" ] && [ "$BUILD_UTC" != "2026-04-26T16:09:30Z" ]; then
  echo -e "${GREEN}[+] Build: ${BUILD_UTC}${NC}"
fi
echo -e "${DARK_GRAY}[*] Executar:${NC}"
echo -e "${DARK_GRAY}    sudo DEADSHOT_CONFIG_FILE=${CFG_DST} ${DEST_DIR}/deadshot.sh${NC}"
