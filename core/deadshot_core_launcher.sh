#!/bin/bash

set -euo pipefail

RED='\033[31;1m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CORE_DIR="${SCRIPT_DIR}/Deadshot-Tools/deadshot-raw"
CORE_ENTRY="${CORE_DIR}/deadshot.sh"

if [ "$(uname -s)" != "Linux" ]; then
  echo -e "${RED}[!] Execução bloqueada: Linux obrigatório.${NC}"
  exit 1
fi

if [ "${EUID:-0}" -ne 0 ]; then
  echo -e "${RED}[!] Execução bloqueada: requer root.${NC}"
  echo -e "${DARK_GRAY}[*] Usa: sudo ${SCRIPT_DIR}/deadshot.sh${NC}"
  exit 1
fi

if [ ! -f "$CORE_ENTRY" ]; then
  echo -e "${RED}[!] Core não encontrado: ${CORE_ENTRY}${NC}"
  exit 1
fi

exec bash "$CORE_ENTRY" "$@"
