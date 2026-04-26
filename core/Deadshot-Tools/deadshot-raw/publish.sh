#!/bin/bash

set -euo pipefail

RED='\033[31;1m'
GREEN='\033[32;1m'
YELLOW='\033[33;1m'
NC='\033[0m'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DIST_DIR="${SCRIPT_DIR}/dist"

PUBLIC_REPO_URL="${PUBLIC_REPO_URL:-git@github.com:jeremiasamado/Deadshot-Raw.git}"
PUBLIC_REPO_DIR="${PUBLIC_REPO_DIR:-$(dirname "$SCRIPT_DIR")/Deadshot-Raw}"
PUBLIC_BRANCH="${PUBLIC_BRANCH:-main}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DRY_RUN="${DRY_RUN:-0}"
ALLOW_REMOTE_MISMATCH="${ALLOW_REMOTE_MISMATCH:-0}"
GPG_SIGN_KEY="${GPG_SIGN_KEY:-}"

PUBLISH_FILES=(
    deadshot
    deadshot_shield
    deadshot_ui
    deadshot_agents
    deadshot.conf
    deadshot_agents_policy.json
    deadshot_scope.json
    LICENSE.md
    SHA256SUMS
)

SOURCE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S")"
COMMIT_MSG="${1:-Automated Protected Build Release (${TIMESTAMP}, src ${SOURCE_COMMIT})}"

WORK_TMP_DIR=""

cleanup() {
    if [ -n "$WORK_TMP_DIR" ] && [ -d "$WORK_TMP_DIR" ]; then
        rm -rf "$WORK_TMP_DIR"
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[!] Required command not found: ${cmd}.${NC}"
        exit 1
    fi
}

assert_file() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo -e "${RED}[!] Required file missing: ${path}.${NC}"
        exit 1
    fi
}

trap cleanup EXIT

echo -e "${GREEN}[*] Starting private-to-public release sync...${NC}"

require_cmd git
require_cmd rsync
require_cmd sha256sum
require_cmd gpg

if [ -z "$GPG_SIGN_KEY" ]; then
    echo -e "${RED}[!] GPG_SIGN_KEY is required in paranoid mode.${NC}"
    echo -e "${YELLOW}[*] Example: GPG_SIGN_KEY=YOUR_KEY_ID ./publish.sh${NC}"
    exit 1
fi

assert_file "${SCRIPT_DIR}/build.sh"

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}[!] Script directory is not a git repository.${NC}"
    exit 1
fi

if [ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]; then
    echo -e "${RED}[!] Private repository has uncommitted or untracked changes.${NC}"
    echo -e "${YELLOW}[*] Commit or stash private changes before publish.${NC}"
    exit 1
fi

if [ "$SKIP_BUILD" = "1" ]; then
    echo -e "${YELLOW}[*] SKIP_BUILD=1 set. Using existing dist artifacts.${NC}"
else
    echo -e "${GREEN}[*] Building release artifacts...${NC}"
    bash "${SCRIPT_DIR}/build.sh"
fi

if [ ! -d "$DIST_DIR" ]; then
    echo -e "${RED}[!] dist directory not found.${NC}"
    exit 1
fi


# --- SANITIZE ARTIFACTS BEFORE PUBLISH ---
STAGING_PATH_FILE="$(mktemp)"
STAGING_DIR=""

cleanup_staging() {
    if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
    rm -f "$STAGING_PATH_FILE"
}
trap cleanup_staging EXIT

echo -e "${GREEN}[*] Validating dist artifact set...${NC}"
for file in "${PUBLISH_FILES[@]}"; do
    assert_file "${DIST_DIR}/${file}"
done

if ! (cd "$DIST_DIR" && sha256sum -c SHA256SUMS --status 2>/dev/null); then
    echo -e "${RED}[!] dist manifest check failed. Refusing to publish.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Sanitizing artifacts for public release...${NC}"
if ! "$SCRIPT_DIR/sanitize_publish_artifacts.sh" "$DIST_DIR" "$STAGING_PATH_FILE"; then
    echo -e "${RED}[!] Sanitization failed. Aborting publish.${NC}"
    exit 1
fi

if [ ! -f "$STAGING_PATH_FILE" ]; then
    echo -e "${RED}[!] Could not determine sanitized staging directory (missing path file).${NC}"
    exit 1
fi

STAGING_DIR="$(cat "$STAGING_PATH_FILE")"
if [ -z "$STAGING_DIR" ] || [ ! -d "$STAGING_DIR" ]; then
    echo -e "${RED}[!] Could not determine sanitized staging directory.${NC}"
    exit 1
fi

if [ ! -d "$PUBLIC_REPO_DIR/.git" ]; then
    echo -e "${GREEN}[*] Public repository not found locally. Cloning...${NC}"
    git clone "$PUBLIC_REPO_URL" "$PUBLIC_REPO_DIR"
fi

cd "$PUBLIC_REPO_DIR"

public_origin="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$public_origin" ] && [ "$public_origin" != "$PUBLIC_REPO_URL" ] && [ "$ALLOW_REMOTE_MISMATCH" != "1" ]; then
    echo -e "${RED}[!] Public repo URL mismatch detected.${NC}"
    echo -e "${RED}[!] Expected: ${PUBLIC_REPO_URL}${NC}"
    echo -e "${RED}[!] Found:    ${public_origin}${NC}"
    echo -e "${YELLOW}[*] Set ALLOW_REMOTE_MISMATCH=1 to override (not recommended).${NC}"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}[!] Public repository has local uncommitted changes. Aborting.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Updating local public repository...${NC}"
git fetch origin "$PUBLIC_BRANCH"
if git show-ref --verify --quiet "refs/heads/${PUBLIC_BRANCH}"; then
    git checkout "$PUBLIC_BRANCH"
elif git show-ref --verify --quiet "refs/remotes/origin/${PUBLIC_BRANCH}"; then
    git checkout -b "$PUBLIC_BRANCH" "origin/${PUBLIC_BRANCH}"
else
    git checkout -b "$PUBLIC_BRANCH"
fi

if git show-ref --verify --quiet "refs/remotes/origin/${PUBLIC_BRANCH}"; then
    git pull --ff-only origin "$PUBLIC_BRANCH"
fi


echo -e "${GREEN}[*] Syncing allowlisted artifacts to public repository...${NC}"
WORK_TMP_DIR="$(mktemp -d)"
for file in "${PUBLISH_FILES[@]}"; do
    cp "${STAGING_DIR}/${file}" "${WORK_TMP_DIR}/${file}"
done
rsync -a --delete --exclude ".git/" --exclude "SHA256SUMS.asc" "${WORK_TMP_DIR}/" "./"

if ! sha256sum -c SHA256SUMS --status 2>/dev/null; then
    echo -e "${RED}[!] Post-sync manifest verification failed in public repository.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Exporting release public key...${NC}"
gpg --batch --yes --armor --export "$GPG_SIGN_KEY" > RELEASE-PUBKEY.asc

git add -A

if git diff --cached --quiet; then
    echo -e "${YELLOW}[*] No changes to publish.${NC}"
    exit 0
fi

echo -e "${GREEN}[*] Signing SHA256SUMS with GPG key ${GPG_SIGN_KEY}...${NC}"
gpg --batch --yes --armor --local-user "$GPG_SIGN_KEY" --output SHA256SUMS.asc --detach-sign SHA256SUMS

if ! gpg --batch --verify SHA256SUMS.asc SHA256SUMS >/dev/null 2>&1; then
    echo -e "${RED}[!] Signature verification failed for SHA256SUMS.asc.${NC}"
    exit 1
fi

git add SHA256SUMS.asc

if [ "$DRY_RUN" = "1" ]; then
    echo -e "${YELLOW}[*] DRY_RUN=1 enabled. Skipping commit/push.${NC}"
    git --no-pager status --short
    git --no-pager diff --cached --stat
    exit 0
fi

echo -e "${GREEN}[*] Committing and pushing to public repository...${NC}"
git commit -m "$COMMIT_MSG"
git push origin "$PUBLIC_BRANCH"

echo -e "${GREEN}[+] Publish complete.${NC}"
