#!/bin/bash

# ==========================================
# DEADSHOT SHIELD (Blue Team Active Defense)
# Developer: NE0SYNC
# ==========================================

# 1. Pre-Drop Setup: Ensure sandbox user exists
if ! id -u deadshot >/dev/null 2>&1; then
    echo "[!] CRITICAL: Dedicated sandbox user 'deadshot' does not exist. Aborting." >&2
    echo "    Run: sudo useradd --system --no-create-home --shell /usr/sbin/nologin deadshot" >&2
    exit 1
fi

# 2. Pre-Drop Setup: Fix log directory permissions
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
mkdir -p "$SCRIPT_DIR/Reports"
chown deadshot:deadshot "$SCRIPT_DIR/Reports"

# 3. PRIVILEGE DROP: Never run honeypot as root
if [ "$EUID" -eq 0 ]; then
    echo "[*] Root execution detected. Dropping privileges to 'deadshot' user..." >&2
    exec runuser -u deadshot -- "$0" "$@"
fi

# ==========================================
# EXECUTION (Now running securely as 'deadshot')
# ==========================================
RED='\033[31;40;1m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

SHIELD_LOG="$SCRIPT_DIR/Reports/Shield_Blocked_IPs.txt"
HONEYPOT_PORTS="80 8080 8888"
SSH_FAIL_THRESHOLD=5
CONFIG_FILE="$SCRIPT_DIR/deadshot.conf"

load_secure_config() {
    local cfg="$CONFIG_FILE"
    local owner_uid perms mode

    if [ ! -f "$cfg" ]; then
        return 0
    fi

    if [ -L "$cfg" ]; then
        echo -e "${RED}[!] Insecure config: symbolic links are not allowed for deadshot.conf.${NC}"
        return 1
    fi

    owner_uid=$(stat -Lc '%u' "$cfg" 2>/dev/null)
    perms=$(stat -Lc '%a' "$cfg" 2>/dev/null)

    if [ -z "$owner_uid" ] || [ -z "$perms" ]; then
        echo -e "${RED}[!] Unable to validate deadshot.conf ownership/permissions.${NC}"
        return 1
    fi

    if [ "$owner_uid" -ne 0 ] && { [ -z "$SUDO_UID" ] || [ "$owner_uid" -ne "$SUDO_UID" ]; }; then
        echo -e "${RED}[!] Insecure config owner for deadshot.conf (uid: $owner_uid).${NC}"
        echo -e "${DARK_GRAY}[*] Owner must be root or the invoking sudo user.${NC}"
        return 1
    fi

    mode=$((8#$perms))
    if (( mode & 0022 )); then
        echo -e "${RED}[!] Insecure config permissions on deadshot.conf ($perms).${NC}"
        echo -e "${DARK_GRAY}[*] Group/other write permissions are forbidden.${NC}"
        return 1
    fi

    source "$cfg"
    return 0
}

# Load configuration
if ! load_secure_config; then
    exit 1
fi

# --- ENVIRONMENT VARIABLE HARDENING (após configuração, antes de uso) ---

# Validate PUBLIC_REPO_URL
if [[ ! "$PUBLIC_REPO_URL" =~ ^https?:// ]]; then
    echo "[!] CRITICAL: PUBLIC_REPO_URL must start with http:// or https://." >&2
    exit 1
fi

# Validate PUBLIC_REPO_DIR
if [[ "$PUBLIC_REPO_DIR" != /* ]] || [[ "$PUBLIC_REPO_DIR" == *".."* ]]; then
    echo "[!] CRITICAL: PUBLIC_REPO_DIR must be absolute and not contain '..'." >&2
    exit 1
fi

# Validate AUTH_LOG
if [[ "$AUTH_LOG" != /* ]] || [[ "$AUTH_LOG" == *".."* ]]; then
    echo "[!] CRITICAL: AUTH_LOG must be absolute and not contain '..'." >&2
    exit 1
fi

# Validate TOOLS_DIR
if [[ "$TOOLS_DIR" != /* ]] || [[ "$TOOLS_DIR" == *".."* ]]; then
    echo "[!] CRITICAL: TOOLS_DIR must be absolute and not contain '..'." >&2
    exit 1
fi

# Lock variables
readonly PUBLIC_REPO_URL
readonly PUBLIC_REPO_DIR
readonly AUTH_LOG
readonly TOOLS_DIR

if [[ "$SHIELD_METRICS_FILE" != /* ]]; then
    SHIELD_METRICS_FILE="$SCRIPT_DIR/$SHIELD_METRICS_FILE"
fi

if [ -z "$AUTH_LOG" ]; then
    if [ -f "/var/log/auth.log" ]; then
        AUTH_LOG="/var/log/auth.log"
    elif [ -f "/var/log/secure" ]; then
        AUTH_LOG="/var/log/secure"
    else
        AUTH_LOG="/var/log/auth.log"
    fi
fi

mkdir -p "$SCRIPT_DIR/Reports"

USE_IPSET=0
SHIELD_MODE="interactive"
ENRICH_PIPE=""
ENRICH_PID=""
BLOCKED_FILE=""
RUNTIME_DIR=""

METRIC_STARTED_AT=$(date +%s)
METRIC_EVENTS=0
METRIC_BLOCKED_TOTAL=0
METRIC_BLOCKED_FAIL=0
METRIC_BLOCKED_ENUM=0
METRIC_BLOCKED_SCAN=0
METRIC_LAST_BLOCKED_IP=""
METRIC_LAST_EVENT="startup"
METRIC_LAST_FLUSH=0

extract_ipv4() {
    local line="$1"
    if [[ "$line" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
        echo "${BASH_REMATCH[0]}"
    fi
}

assert_not_symlink_and_owner() {
    local target="$1"
    local expected_uid="$2"
    local expected_mode="$3"
    local actual_uid actual_mode

    [ -e "$target" ] || return 0

    if [ -L "$target" ]; then
        echo -e "${RED}[!] SECURITY ALERT: $target is a symbolic link. Swapping detected!${NC}" >&2
        exit 1
    fi

    actual_uid=$(stat -Lc '%u' "$target" 2>/dev/null)
    if [ "$actual_uid" -ne "$expected_uid" ]; then
        echo -e "${RED}[!] SECURITY ALERT: $target owner mismatch ($actual_uid != $expected_uid).${NC}" >&2
        exit 1
    fi

    if [ -n "$expected_mode" ]; then
        actual_mode=$(stat -Lc '%a' "$target" 2>/dev/null)
        # Check if actual mode is more permissive than expected (simplified)
        if [ "$actual_mode" -gt "$expected_mode" ]; then
             chmod "$expected_mode" "$target" 2>/dev/null
        fi
    fi
}

is_blocked_ip() {
    local ip="$1"
    grep -qx "$ip" "$BLOCKED_FILE" 2>/dev/null
}

append_window_event() {
    local existing="$1"
    local now_epoch="$2"
    local window_secs="$3"
    local cutoff=$((now_epoch - window_secs))
    local rebuilt=""

    if [ -n "$existing" ]; then
        IFS=',' read -r -a _ts <<< "$existing"
        for t in "${_ts[@]}"; do
            if [ -n "$t" ] && [ "$t" -ge "$cutoff" ] 2>/dev/null; then
                if [ -z "$rebuilt" ]; then
                    rebuilt="$t"
                else
                    rebuilt="$rebuilt,$t"
                fi
            fi
        done
    fi

    if [ -z "$rebuilt" ]; then
        echo "$now_epoch"
    else
        echo "$rebuilt,$now_epoch"
    fi
}

count_window_events() {
    local series="$1"
    if [ -z "$series" ]; then
        echo 0
        return
    fi

    local count=1
    local rest="$series"
    while [[ "$rest" == *,* ]]; do
        rest="${rest#*,}"
        count=$((count + 1))
    done
    echo "$count"
}

write_metrics() {
    local now_epoch="${1:-$(date +%s)}"
    local state="${2:-active}"
    local uptime=$((now_epoch - METRIC_STARTED_AT))
    local tmp_file="${SHIELD_METRICS_FILE}.tmp"

    cat > "$tmp_file" <<EOF
{
  "status": "$state",
  "mode": "$SHIELD_MODE",
  "started_at_epoch": $METRIC_STARTED_AT,
  "uptime_sec": $uptime,
  "events_seen": $METRIC_EVENTS,
  "blocked_total": $METRIC_BLOCKED_TOTAL,
  "blocked_fail": $METRIC_BLOCKED_FAIL,
  "blocked_enum": $METRIC_BLOCKED_ENUM,
  "blocked_scan": $METRIC_BLOCKED_SCAN,
  "last_blocked_ip": "$METRIC_LAST_BLOCKED_IP",
  "last_event": "$METRIC_LAST_EVENT",
  "auth_log": "$AUTH_LOG",
  "ipset_enabled": $USE_IPSET,
  "ipset_name": "$SHIELD_IPSET_NAME",
  "window_secs": $SSH_WINDOW_SECS,
  "timestamp_epoch": $now_epoch
}
EOF
    chmod 600 "$tmp_file" 2>/dev/null
    assert_not_symlink_and_owner "$tmp_file" "$(id -u)" "600"
    mv "$tmp_file" "$SHIELD_METRICS_FILE"
}

flush_metrics_if_needed() {
    local now_epoch="$1"
    if [ $((now_epoch - METRIC_LAST_FLUSH)) -ge 1 ]; then
        write_metrics "$now_epoch" "active"
        METRIC_LAST_FLUSH="$now_epoch"
    fi
}

mark_block_metric() {
    local reason="$1"
    local ip="$2"
    local now_epoch="$3"

    METRIC_BLOCKED_TOTAL=$((METRIC_BLOCKED_TOTAL + 1))
    case "$reason" in
        FAIL) METRIC_BLOCKED_FAIL=$((METRIC_BLOCKED_FAIL + 1));;
        ENUM) METRIC_BLOCKED_ENUM=$((METRIC_BLOCKED_ENUM + 1));;
        SCAN) METRIC_BLOCKED_SCAN=$((METRIC_BLOCKED_SCAN + 1));;
    esac

    METRIC_LAST_BLOCKED_IP="$ip"
    METRIC_LAST_EVENT="$reason"
    write_metrics "$now_epoch" "active"
    METRIC_LAST_FLUSH="$now_epoch"
}

init_runtime_paths() {
    if [ -n "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ]; then
        return 0
    fi

    # 1. Criação de RUNTIME_DIR
    RUNTIME_DIR=$(mktemp -d /tmp/deadshot_shield.XXXXXX 2>/dev/null)
    if [ -z "$RUNTIME_DIR" ] || [ ! -d "$RUNTIME_DIR" ]; then
        echo -e "${RED}[!] Failed to create secure runtime directory.${NC}"
        return 1
    fi
    assert_not_symlink_and_owner "$RUNTIME_DIR" "$(id -u)" "700"

    # 2. Criação e validação de BLOCKED_FILE
    BLOCKED_FILE="$RUNTIME_DIR/blocked_ips"
    umask 077
    : > "$BLOCKED_FILE"
    umask 022
    assert_not_symlink_and_owner "$BLOCKED_FILE" "$(id -u)" "600"

    # 3. Criação e validação de ENRICH_PIPE
    ENRICH_PIPE="$RUNTIME_DIR/enrich.fifo"
    rm -f "$ENRICH_PIPE" 2>/dev/null
    umask 077
    mkfifo "$ENRICH_PIPE" || { echo "[!] CRITICAL: Failed to create ENRICH_PIPE." >&2; exit 1; }
    umask 022
    assert_not_symlink_and_owner "$ENRICH_PIPE" "$(id -u)" "600"

    return 0
}

init_block_backend() {
    USE_IPSET=0

    if [ "$SHIELD_USE_IPSET" != "1" ]; then
        return 0
    fi

    if ! command -v ipset >/dev/null 2>&1; then
        return 0
    fi

    if ! sudo ipset create "$SHIELD_IPSET_NAME" hash:ip -exist 2>/dev/null; then
        return 0
    fi

    if ! sudo iptables -C INPUT -m set --match-set "$SHIELD_IPSET_NAME" src -j DROP 2>/dev/null; then
        sudo iptables -I INPUT 1 -m set --match-set "$SHIELD_IPSET_NAME" src -j DROP 2>/dev/null || return 0
    fi

    USE_IPSET=1
}

block_ip_fast() {
    local ip="$1"

    if [ "$USE_IPSET" -eq 1 ]; then
        sudo ipset add "$SHIELD_IPSET_NAME" "$ip" -exist 2>/dev/null
    else
        if ! sudo iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
            sudo iptables -A INPUT -s "$ip" -j DROP 2>/dev/null
        fi
    fi

    if ! is_blocked_ip "$ip"; then
        echo "$ip" >> "$BLOCKED_FILE"
    fi
}

run_enrichment_task() {
    local attacker_ip="$1"
    local reason="$2"
    local hit_count="$3"

    local geo_data geo_country geo_city geo_isp geo_lat geo_lon
    local ssh_fp prev_match return_note ai_response
    local fingerprint_db="$SCRIPT_DIR/Reports/Shield_Fingerprints.db"

    touch "$fingerprint_db"

    geo_data=$(curl -s --connect-timeout 2 --max-time 3 "https://ipapi.co/$attacker_ip/json/" 2>/dev/null)
    geo_country=$(echo "$geo_data" | grep -oP '"country_name":"\K[^"]+' 2>/dev/null)
    geo_city=$(echo "$geo_data" | grep -oP '"city":"\K[^"]+' 2>/dev/null)
    geo_isp=$(echo "$geo_data" | grep -oP '"org":"\K[^"]+' 2>/dev/null)
    geo_lat=$(echo "$geo_data" | grep -oP '"latitude":\K[0-9.\-]+' 2>/dev/null)
    geo_lon=$(echo "$geo_data" | grep -oP '"longitude":\K[0-9.\-]+' 2>/dev/null)

    [ -z "$geo_country" ] && geo_country="UNKNOWN"
    [ -z "$geo_city" ] && geo_city="UNKNOWN"
    [ -z "$geo_isp" ] && geo_isp="UNKNOWN"
    [ -z "$geo_lat" ] && geo_lat="0"
    [ -z "$geo_lon" ] && geo_lon="0"

    ssh_fp=$(grep "$attacker_ip" "$AUTH_LOG" 2>/dev/null | grep -oP 'SSH-2.0-\S+' | tail -1)
    [ -z "$ssh_fp" ] && ssh_fp="UNKNOWN_CLIENT"

    prev_match=$(grep "$ssh_fp" "$fingerprint_db" 2>/dev/null | grep -v "$attacker_ip" | head -1)
    if [ -n "$prev_match" ] && [ "$ssh_fp" != "UNKNOWN_CLIENT" ]; then
        return_note="RETURNING ATTACKER (prev: $prev_match)"
    else
        return_note=""
    fi

    echo "$ssh_fp | $attacker_ip | ${geo_country}/${geo_city} | $(date)" >> "$fingerprint_db"
    echo "[$(date)] BLOCKED ($reason/$SHIELD_MODE): $attacker_ip | ${geo_country}/${geo_city} | ISP: $geo_isp | GPS: ${geo_lat},${geo_lon} | FP: $ssh_fp | Hits: $hit_count | $return_note" >> "$SHIELD_LOG"

    if [ "$SHIELD_MODE" = "interactive" ]; then
        echo -e "${RED}[GEO] Country: $geo_country | City: $geo_city | ISP: $geo_isp${NC}"
        echo -e "${RED}[GPS] Lat: $geo_lat | Lon: $geo_lon${NC}"
        echo -e "${RED}[FINGERPRINT] Client: $ssh_fp${NC}"
        if [ -n "$return_note" ]; then
            echo -e "${RED}[!!!] $return_note${NC}"
        fi
    fi

    if pgrep -x "ollama" >/dev/null 2>&1; then
        ai_response=$(echo "Blocked attacker $attacker_ip for reason $reason with $hit_count hits. GEO: $geo_country/$geo_city ISP:$geo_isp FP:$ssh_fp. $return_note What should I check next? Brief tactical steps." | ollama run "$OLLAMA_MODEL" 2>/dev/null | head -20)
        if [ "$SHIELD_MODE" = "interactive" ]; then
            echo -e "${RED}[AI THREAT INTEL]:${NC}"
            echo -e "${DARK_GRAY}$ai_response${NC}"
            echo ""
        else
            echo "[$(date)] AI THREAT INTEL ($reason/$attacker_ip): $ai_response" >> "$SHIELD_LOG"
        fi
    fi
}

start_enrichment_worker() {
    if [ -z "$ENRICH_PIPE" ]; then
        return
    fi

    rm -f "$ENRICH_PIPE" 2>/dev/null
    mkfifo "$ENRICH_PIPE" 2>/dev/null || return

    (
        exec 3<>"$ENRICH_PIPE" || exit 0
        while IFS='|' read -r q_ip q_reason q_hits <&3; do
            [ -z "$q_ip" ] && continue
            run_enrichment_task "$q_ip" "$q_reason" "$q_hits"
        done
    ) &
    ENRICH_PID=$!
}

queue_enrichment() {
    local ip="$1"
    local reason="$2"
    local hits="$3"

    if [ -p "$ENRICH_PIPE" ] && [ -n "$ENRICH_PID" ] && kill -0 "$ENRICH_PID" 2>/dev/null; then
        { printf '%s|%s|%s\n' "$ip" "$reason" "$hits" > "$ENRICH_PIPE"; } 2>/dev/null &
    else
        run_enrichment_task "$ip" "$reason" "$hits" &
    fi
}

acquire_shield_lock() {
    local lock_dir old_umask

    if ! command -v flock >/dev/null 2>&1; then
        return 0
    fi

    lock_dir=$(dirname "$SHIELD_LOCK_FILE")
    case "$lock_dir" in
        /run/lock|/var/lock|/run)
            ;;
        *)
            echo -e "${RED}[!] Unsafe SHIELD_LOCK_FILE directory: $lock_dir${NC}"
            echo -e "${DARK_GRAY}[*] Use /run/lock or /var/lock for lock files.${NC}"
            return 1
            ;;
    esac

    mkdir -p "$lock_dir" 2>/dev/null || true
    if [ -L "$SHIELD_LOCK_FILE" ]; then
        echo -e "${RED}[!] Refusing to open symlinked lock file: $SHIELD_LOCK_FILE${NC}"
        return 1
    fi

    old_umask=$(umask)
    umask 077
    exec 200>>"$SHIELD_LOCK_FILE"
    umask "$old_umask"

    if ! flock -n 200; then
        echo -e "${DARK_GRAY}[*] Shield already active. Lock: $SHIELD_LOCK_FILE${NC}"
        exit 0
    fi
}

ensure_auth_log_readable() {
    if [ ! -r "$AUTH_LOG" ]; then
        echo -e "${RED}[!] Auth log not readable: $AUTH_LOG${NC}"
        echo -e "${DARK_GRAY}[*] Set AUTH_LOG in deadshot.conf (example: /var/log/auth.log or /var/log/secure).${NC}"
        return 1
    fi
    return 0
}

# ==========================================
# HONEYPOT TAUNT PAGE (The Middle Finger)
# ==========================================
start_honeypot() {
    echo -e "${RED}[!] Deploying Honeypot Taunt Servers on ports: $HONEYPOT_PORTS${NC}"

    for HP_PORT in $HONEYPOT_PORTS; do
        if ! [[ "$HP_PORT" =~ ^[0-9]{1,5}$ ]]; then
            continue
        fi
        python3 -c "
import http.server
import socketserver

TAUNT_PAGE = '''<html>
<head><title>ACCESS DENIED</title></head>
<body style=\"background:#000;color:#ff3333;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;\">
<pre style=\"font-size:16px;text-align:center;\">

 ____  _________    ____  _____ __  ______  ______ 
/ __ \/ ____/   |  / __ \/ ___// / / / __ \/_  __/ 
/ / / / __/ / /| | / / / /\__ \/ /_/ / / / / / /    
/ /_/ / /___/ ___ |/ /_/ /___/ / __  / /_/ / / /     
/_____/_____/_/  |_/_____//____/_/ /_/\____/ /_/      

+==========================================+
|                                          |
|    YOUR IP HAS BEEN LOGGED, REPORTED     |
|    AND PERMANENTLY BLACKLISTED.          |
|                                          |
|           ┌∩┐(◣_◢)┌∩┐                   |
|                                          |
|    NICE TRY, SCRIPT KIDDY.              |
|    GO HOME.                              |
|                                          |
|    -- DEADSHOT O.S. // NE0SYNC --        |
+==========================================+

</pre>
</body></html>
'''

class TauntHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(TAUNT_PAGE.encode())
        print(f'[HONEYPOT:$HP_PORT] Intruder browsed from: {self.client_address[0]}')
    def do_HEAD(self): self.do_GET()
    def log_message(self, format, *args): pass

try:
    with socketserver.TCPServer(('', $HP_PORT), TauntHandler) as httpd:
        httpd.serve_forever()
except OSError:
    pass
" >/dev/null 2>&1 &
    done
    echo -e "${DARK_GRAY}[+] Honeypots active on ports: $HONEYPOT_PORTS${NC}"
}

# ==========================================
# SSH BANNER: Taunt on every login attempt
# ==========================================
deploy_ssh_banner() {
    BANNER_FILE="/etc/ssh/deadshot_banner"
    sudo bash -c "cat > $BANNER_FILE" <<'BANNER'

+==========================================+
|                                          |
|    ┌∩┐(◣_◢)┌∩┐                           |
|                                          |
|    THIS SYSTEM IS MONITORED BY           |
|    DEADSHOT ACTIVE DEFENSE (NE0SYNC)     |
|                                          |
|    YOUR IP, FINGERPRINT AND LOCATION     |
|    HAVE BEEN LOGGED PERMANENTLY.         |
|                                          |
+==========================================+

BANNER
    if ! grep -q "deadshot_banner" /etc/ssh/sshd_config 2>/dev/null; then
        sudo bash -c 'echo "Banner /etc/ssh/deadshot_banner" >> /etc/ssh/sshd_config'
        sudo systemctl reload sshd 2>/dev/null || sudo service ssh reload 2>/dev/null
    fi
    echo -e "${DARK_GRAY}[+] SSH Banner deployed. Every login attempt now sees the taunt.${NC}"
}

# ==========================================
# WATCHDOG: SSH Brute-Force Detection
# ==========================================
run_watchdog() {
    ensure_auth_log_readable || return
    SHIELD_MODE="interactive"

    clear
    echo -e "${RED}"
    echo '  ____  _   _ ___ _____ _     ____  '
    echo ' / ___|| | | |_ _| ____| |   |  _ \ '
    echo ' \___ \| |_| || ||  _| | |   | | | |'
    echo '  ___) |  _  || || |___| |___| |_| |'
    echo ' |____/|_| |_|___|_____|_____|____/ '
    echo ""
    echo -e "${NC}"
    echo -e "${RED}[!] DEADSHOT SHIELD: ACTIVE DEFENSE MODE${NC}"
    echo -e "${DARK_GRAY}[*] Monitoring SSH brute-force + enumeration + port scans...${NC}"
    echo -e "${DARK_GRAY}[*] Threshold: $SSH_FAIL_THRESHOLD failed attempts = AUTO-BLOCK${NC}"
    echo -e "${DARK_GRAY}[*] Press Ctrl+C to deactivate shield.${NC}"
    echo ""

    deploy_ssh_banner
    start_honeypot

    init_runtime_paths || return
    init_block_backend
    start_enrichment_worker
    write_metrics "$(date +%s)" "active"

    declare -A FAIL_EVENTS
    declare -A ENUM_EVENTS
    declare -A SCAN_EVENTS

    while IFS= read -r line; do
        NOW_EPOCH=$(date +%s)
        METRIC_EVENTS=$((METRIC_EVENTS + 1))

        if [[ "$line" == *"Failed password"* ]]; then
            ATTACKER_IP=$(extract_ipv4 "$line")
            if [ -z "$ATTACKER_IP" ]; then continue; fi
            if is_blocked_ip "$ATTACKER_IP"; then continue; fi

            FAIL_EVENTS["$ATTACKER_IP"]=$(append_window_event "${FAIL_EVENTS["$ATTACKER_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
            FAIL_COUNT=$(count_window_events "${FAIL_EVENTS["$ATTACKER_IP"]}")
            echo -e "${RED}[!] INTRUSION ATTEMPT from $ATTACKER_IP (Failures: $FAIL_COUNT/$SSH_FAIL_THRESHOLD)${NC}"

            if [ "$FAIL_COUNT" -ge "$SSH_FAIL_THRESHOLD" ]; then
                echo -e "${RED}[!!!] THRESHOLD BREACHED! NEUTRALIZING $ATTACKER_IP${NC}"
                notify-send -u critical "DEADSHOT SHIELD" "INTRUSION BLOCKED: $ATTACKER_IP" 2>/dev/null
                block_ip_fast "$ATTACKER_IP"

                mark_block_metric "FAIL" "$ATTACKER_IP" "$NOW_EPOCH"
                queue_enrichment "$ATTACKER_IP" "FAIL" "$FAIL_COUNT"
                echo -e "${DARK_GRAY}[+] $ATTACKER_IP queued for async enrichment + intel.${NC}"
            fi
        fi

        if [[ "$line" == *"Invalid user"* || "$line" == *"invalid user"* ]]; then
            ENUM_IP=$(extract_ipv4 "$line")
            if [ -n "$ENUM_IP" ] && ! is_blocked_ip "$ENUM_IP"; then
                ENUM_EVENTS["$ENUM_IP"]=$(append_window_event "${ENUM_EVENTS["$ENUM_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
                ENUM_COUNT=$(count_window_events "${ENUM_EVENTS["$ENUM_IP"]}")
                echo -e "${RED}[!] USER ENUMERATION from $ENUM_IP (${ENUM_COUNT} invalid usernames tried)${NC}"
                if [ "$ENUM_COUNT" -ge "$SSH_FAIL_THRESHOLD" ]; then
                    echo -e "${RED}[!!!] ENUMERATION THRESHOLD HIT! BLOCKING $ENUM_IP${NC}"
                    block_ip_fast "$ENUM_IP"
                    mark_block_metric "ENUM" "$ENUM_IP" "$NOW_EPOCH"
                    queue_enrichment "$ENUM_IP" "ENUM" "$ENUM_COUNT"
                fi
            fi
        fi

        if [[ "$line" == *"refused connect"* || "$line" == *"Bad protocol"* || "$line" == *"Did not receive identification"* || "$line" == *"Connection closed by"* ]]; then
            SCAN_IP=$(extract_ipv4 "$line")
            if [ -n "$SCAN_IP" ] && ! is_blocked_ip "$SCAN_IP"; then
                SCAN_EVENTS["$SCAN_IP"]=$(append_window_event "${SCAN_EVENTS["$SCAN_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
                SCAN_COUNT=$(count_window_events "${SCAN_EVENTS["$SCAN_IP"]}")
                echo -e "${RED}[!] PORT SCAN / PROBE detected from $SCAN_IP (${SCAN_COUNT} events)${NC}"
                if [ "$SCAN_COUNT" -ge "${SHIELD_SCAN_THRESHOLD:-10}" ]; then
                    echo -e "${RED}[!!!] AGGRESSIVE SCANNER! AUTO-BLOCKING $SCAN_IP${NC}"
                    block_ip_fast "$SCAN_IP"
                    mark_block_metric "SCAN" "$SCAN_IP" "$NOW_EPOCH"
                    queue_enrichment "$SCAN_IP" "SCAN" "$SCAN_COUNT"
                fi
            fi
        fi

        flush_metrics_if_needed "$NOW_EPOCH"
    done < <(tail -Fn0 "$AUTH_LOG" 2>/dev/null)

}

# ==========================================
# SHIELD CLEANUP
# ==========================================
shield_cleanup() {
    # Prevent multiple executions
    if [ -n "$SHIELD_CLEANED_UP" ]; then
        return
    fi
    SHIELD_CLEANED_UP=1
    local now_epoch
    now_epoch=$(date +%s)

    echo -e "\n${DARK_GRAY}[*] Deactivating Shield...${NC}"
    pkill -f "TauntHandler" 2>/dev/null
    if [ -n "$ENRICH_PID" ]; then
        kill "$ENRICH_PID" 2>/dev/null
    fi
    [ -p "$ENRICH_PIPE" ] && rm -f "$ENRICH_PIPE" 2>/dev/null
    [ -n "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ] && rm -rf "$RUNTIME_DIR" 2>/dev/null
    write_metrics "$now_epoch" "stopped"
    echo -e "${DARK_GRAY}[+] Honeypot server terminated.${NC}"
    echo -e "${DARK_GRAY}[+] Blocked IPs remain in iptables until system reboot.${NC}"
    echo -e "${DARK_GRAY}[+] Shield deactivated. Returning to framework.${NC}"
}

trap shield_cleanup EXIT INT TERM

acquire_shield_lock || exit 1

# Main execution
if [ "$1" == "daemon" ]; then
    ensure_auth_log_readable || exit 1
    SHIELD_MODE="daemon"

    deploy_ssh_banner
    start_honeypot

    init_runtime_paths || exit 1
    init_block_backend
    start_enrichment_worker
    write_metrics "$(date +%s)" "active"

    declare -A FAIL_EVENTS
    declare -A ENUM_EVENTS
    declare -A SCAN_EVENTS

    while IFS= read -r line; do
        NOW_EPOCH=$(date +%s)
        METRIC_EVENTS=$((METRIC_EVENTS + 1))

        if [[ "$line" == *"Failed password"* ]]; then
            ATTACKER_IP=$(extract_ipv4 "$line")
            if [ -z "$ATTACKER_IP" ]; then continue; fi
            if is_blocked_ip "$ATTACKER_IP"; then continue; fi

            FAIL_EVENTS["$ATTACKER_IP"]=$(append_window_event "${FAIL_EVENTS["$ATTACKER_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
            FAIL_COUNT=$(count_window_events "${FAIL_EVENTS["$ATTACKER_IP"]}")
            if [ "$FAIL_COUNT" -ge "$SSH_FAIL_THRESHOLD" ]; then
                block_ip_fast "$ATTACKER_IP"
                mark_block_metric "FAIL" "$ATTACKER_IP" "$NOW_EPOCH"
                queue_enrichment "$ATTACKER_IP" "FAIL" "$FAIL_COUNT"
                notify-send -u critical "DEADSHOT SHIELD" "BLOCKED: $ATTACKER_IP (FAIL/$FAIL_COUNT)" 2>/dev/null
            fi
        fi

        if [[ "$line" == *"Invalid user"* || "$line" == *"invalid user"* ]]; then
            ENUM_IP=$(extract_ipv4 "$line")
            if [ -n "$ENUM_IP" ] && ! is_blocked_ip "$ENUM_IP"; then
                ENUM_EVENTS["$ENUM_IP"]=$(append_window_event "${ENUM_EVENTS["$ENUM_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
                ENUM_COUNT=$(count_window_events "${ENUM_EVENTS["$ENUM_IP"]}")
                if [ "$ENUM_COUNT" -ge "$SSH_FAIL_THRESHOLD" ]; then
                    block_ip_fast "$ENUM_IP"
                    mark_block_metric "ENUM" "$ENUM_IP" "$NOW_EPOCH"
                    queue_enrichment "$ENUM_IP" "ENUM" "$ENUM_COUNT"
                    notify-send -u critical "DEADSHOT SHIELD" "ENUM BLOCKED: $ENUM_IP" 2>/dev/null
                fi
            fi
        fi

        if [[ "$line" == *"refused connect"* || "$line" == *"Bad protocol"* || "$line" == *"Did not receive identification"* || "$line" == *"Connection closed by"* ]]; then
            SCAN_IP=$(extract_ipv4 "$line")
            if [ -n "$SCAN_IP" ] && ! is_blocked_ip "$SCAN_IP"; then
                SCAN_EVENTS["$SCAN_IP"]=$(append_window_event "${SCAN_EVENTS["$SCAN_IP"]}" "$NOW_EPOCH" "$SSH_WINDOW_SECS")
                SCAN_COUNT=$(count_window_events "${SCAN_EVENTS["$SCAN_IP"]}")
                if [ "$SCAN_COUNT" -ge "${SHIELD_SCAN_THRESHOLD:-10}" ]; then
                    block_ip_fast "$SCAN_IP"
                    mark_block_metric "SCAN" "$SCAN_IP" "$NOW_EPOCH"
                    queue_enrichment "$SCAN_IP" "SCAN" "$SCAN_COUNT"
                    notify-send -u critical "DEADSHOT SHIELD" "SCANNER BLOCKED: $SCAN_IP" 2>/dev/null
                fi
            fi
        fi

        flush_metrics_if_needed "$NOW_EPOCH"
    done < <(tail -Fn0 "$AUTH_LOG" 2>/dev/null)

else
    run_watchdog
fi
