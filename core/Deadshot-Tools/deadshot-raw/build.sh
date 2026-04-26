#!/bin/bash

set -euo pipefail

# ==========================================
# DEADSHOT-RAW: AUTOMATED BUILD & PROTECT
# Developer: NE0SYNC
# ==========================================

RED='\033[31;1m'
GREEN='\033[32;1m'
NC='\033[0m'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DIST_DIR="${SCRIPT_DIR}/dist"
GPG_SIGN_KEY="${GPG_SIGN_KEY:-}"

cleanup_build_artifacts() {
    rm -f "${SCRIPT_DIR}/deadshot_built.sh"
    rm -f "${SCRIPT_DIR}/deadshot_built.sh.x.c"
    rm -f "${SCRIPT_DIR}/deadshot_shield.sh.x.c"
    rm -rf "${SCRIPT_DIR}/build" "${SCRIPT_DIR}/deadshot_ui.spec" "${SCRIPT_DIR}/deadshot_agents.spec"
}

trap cleanup_build_artifacts EXIT

require_source_file() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo -e "${RED}[!] Required source file missing: ${path}${NC}"
        exit 1
    fi
}

echo -e "${GREEN}[*] Starting Build Sequence for Deadshot-Raw...${NC}"

# 1. Dependency Check
if ! command -v shc >/dev/null; then
    echo -e "${RED}[!] shc not found. Please install it first.${NC}"
    exit 1
fi

if ! command -v pyinstaller >/dev/null; then
    echo -e "${RED}[!] pyinstaller not found. Please install it via pip or apt.${NC}"
    exit 1
fi

if ! command -v sha256sum >/dev/null; then
    echo -e "${RED}[!] sha256sum not found. Please install coreutils.${NC}"
    exit 1
fi

require_source_file "${SCRIPT_DIR}/deadshot.sh"
require_source_file "${SCRIPT_DIR}/deadshot_shield.sh"
require_source_file "${SCRIPT_DIR}/deadshot_ui.py"
require_source_file "${SCRIPT_DIR}/deadshot_agents.py"
require_source_file "${SCRIPT_DIR}/deadshot.conf"
require_source_file "${SCRIPT_DIR}/deadshot_agents_policy.json"
require_source_file "${SCRIPT_DIR}/deadshot_scope.json"
require_source_file "${SCRIPT_DIR}/LICENSE.md"

# 2. Prepare Dist Directory
echo -e "${GREEN}[*] Preparing distribution folder...${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 3. Calculate Integrity Hash
echo -e "${GREEN}[*] Generating Integrity Lock for LICENSE.md...${NC}"
MASTER_HASH=$(sha256sum "${SCRIPT_DIR}/LICENSE.md" | awk '{print $1}')
echo -e "${GREEN}[+] Master Hash: $MASTER_HASH${NC}"

# 4. Inject Hash into Source (Temporary Copy)
echo -e "${GREEN}[*] Injecting lock into engine...${NC}"
cp "${SCRIPT_DIR}/deadshot.sh" "${SCRIPT_DIR}/deadshot_built.sh"
sed -i "s/REPLACE_ME_BY_BUILD_SH/$MASTER_HASH/g" "${SCRIPT_DIR}/deadshot_built.sh"

# 5. Compile Bash Scripts
echo -e "${GREEN}[*] Compiling Bash Engine (shc)...${NC}"
shc -f "${SCRIPT_DIR}/deadshot_built.sh" -o "${DIST_DIR}/deadshot"
shc -f "${SCRIPT_DIR}/deadshot_shield.sh" -o "${DIST_DIR}/deadshot_shield"

# 6. Compile Python UI
echo -e "${GREEN}[*] Compiling Python TUI (PyInstaller)...${NC}"
pyinstaller --onefile --noconfirm --clean \
    --name "deadshot_ui" \
    --distpath "$DIST_DIR" \
    --exclude-module matplotlib \
    --exclude-module numpy \
    --exclude-module PIL \
    --exclude-module PyQt5 \
    --exclude-module PyQt6 \
    --exclude-module IPython \
    --exclude-module pytest \
    --exclude-module setuptools \
    --exclude-module pkg_resources \
    --exclude-module gi \
    --exclude-module tkinter \
    --exclude-module jedi \
    --exclude-module parso \
    --exclude-module astroid \
    --exclude-module psutil \
    --exclude-module cryptography \
    --exclude-module bcrypt \
    --exclude-module sqlite3 \
    --exclude-module jinja2 \
    --exclude-module dateutil \
    --exclude-module certifi \
    --exclude-module zope \
    --exclude-module wcwidth \
    "${SCRIPT_DIR}/deadshot_ui.py"

# 6.1 Compile Python Agent Engine
echo -e "${GREEN}[*] Compiling Agent Engine (PyInstaller)...${NC}"
pyinstaller --onefile --noconfirm --clean \
    --name "deadshot_agents" \
    --distpath "$DIST_DIR" \
    "${SCRIPT_DIR}/deadshot_agents.py"

# 7. Finalize Package
echo -e "${GREEN}[*] Finalizing tactical package...${NC}"
cp "${SCRIPT_DIR}/deadshot.conf" "$DIST_DIR/"
cp "${SCRIPT_DIR}/LICENSE.md" "$DIST_DIR/"
cp "${SCRIPT_DIR}/deadshot_agents_policy.json" "$DIST_DIR/"
cp "${SCRIPT_DIR}/deadshot_scope.json" "$DIST_DIR/"

echo -e "${GREEN}[*] Generating release manifest (SHA256SUMS)...${NC}"
(
    cd "$DIST_DIR"
    sha256sum deadshot deadshot_shield deadshot_ui deadshot_agents deadshot.conf deadshot_agents_policy.json deadshot_scope.json LICENSE.md > SHA256SUMS
)

echo -e "${GREEN}[*] Signing release manifest with GPG...${NC}"
if [ -z "$GPG_SIGN_KEY" ]; then
    echo -e "${RED}[!] GPG_SIGN_KEY não definido.${NC}"
    echo -e "${RED}[!] Define GPG_SIGN_KEY para assinar o manifest SHA256SUMS.${NC}"
    exit 1
fi
gpg --batch --yes --detach-sign --armor --local-user "$GPG_SIGN_KEY" "${DIST_DIR}/SHA256SUMS"
echo -e "${GREEN}[+] GPG signature generated: SHA256SUMS.asc${NC}"

echo -e "${GREEN}[*] Verifying final artifact set...${NC}"
for artifact in deadshot deadshot_shield deadshot_ui deadshot_agents deadshot.conf deadshot_agents_policy.json deadshot_scope.json LICENSE.md SHA256SUMS SHA256SUMS.asc; do
    if [ ! -f "${DIST_DIR}/${artifact}" ]; then
        echo -e "${RED}[!] Missing artifact after build: ${DIST_DIR}/${artifact}${NC}"
        exit 1
    fi
done

if ! (cd "$DIST_DIR" && sha256sum -c SHA256SUMS --status 2>/dev/null); then
    echo -e "${RED}[!] Artifact manifest verification failed.${NC}"
    exit 1
fi

echo -e "\n${GREEN}[!!!] BUILD COMPLETE: Deadshot-Raw is now ARMED and PROTECTED.${NC}"
echo -e "${GREEN}[*] Public Release folder: ${DIST_DIR}${NC}"
echo -e "${GREEN}[*] Testing binaries locally now is highly recommended.${NC}"
