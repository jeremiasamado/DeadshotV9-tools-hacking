#!/bin/bash
# deadshot-init.sh — Public bootstrap for Deadshot-RAW
set -euo pipefail

PUBKEY_ID="<REPLACE_WITH_PUBKEY_ID>"
DIST_DIR="$(dirname "$0")"

RED='\033[31;1m'
GREEN='\033[32;1m'
YELLOW='\033[33;1m'
NC='\033[0m'

cd "$DIST_DIR"

# 1. Check dependencies
def_check() {
    command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}[!] $1 not found. Please install it before proceeding.${NC}"; exit 1; }
}
def_check gpg
def_check sha256sum

echo -e "${GREEN}[*] Dependencies present: gpg, sha256sum${NC}"

# 2. Verify GPG signature
echo -e "${GREEN}[*] Verifying GPG signature on SHA256SUMS...${NC}"
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$PUBKEY_ID" || true
gpg --batch --verify SHA256SUMS.asc SHA256SUMS 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}[!] GPG signature verification FAILED. Possible tampering or missing public key.${NC}"
    rm -f SHA256SUMS SHA256SUMS.asc
    exit 1
fi

echo -e "${GREEN}[+] GPG signature valid.${NC}"

# 3. Verify SHA256 hashes
echo -e "${GREEN}[*] Verifying binary hashes...${NC}"
if ! sha256sum -c --status SHA256SUMS; then
    echo -e "${RED}[!] Hash verification FAILED. Possible tampering or corruption.${NC}"
    rm -f $(awk '{print $2}' SHA256SUMS)
    exit 1
fi

echo -e "${GREEN}[+] All hashes valid. Green Light: You may now run Deadshot Tools safely.${NC}"
exit 0
