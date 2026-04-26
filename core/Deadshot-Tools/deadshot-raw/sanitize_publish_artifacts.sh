#!/bin/bash

# Usage: ./sanitize_publish_artifacts.sh <dist_dir>
set -euo pipefail


DIST_DIR="${1:-dist}"
STAGING_DIR="$(mktemp -d)"
chmod 700 "$STAGING_DIR"

# Se fornecido, escrever STAGING_DIR para o ficheiro de output
if [ $# -ge 2 ] && [ -n "$2" ]; then
    echo "$STAGING_DIR" > "$2"
fi

# 1. deadshot.conf — regex strip/replace
if [ -f "$DIST_DIR/deadshot.conf" ]; then
    grep -Ev '^(OPSEC_|SPOOF_|PROXY_ADDR|DEFAULT_NMAP_PORTS|NUCLEI_RATE_LIMIT|HONEYPOT_PORTS|AUTH_LOG|SHIELD_|PHONEINFOGA_|OLLAMA_|RUSTSCAN_|SLIVER_|LINPEAS_|WINPEAS_|ENABLE_LOG_SCRUB|ALLOW_UNVERIFIED_DOWNLOADS|PROJECT_DISPLAY_NAME|PROJECT_CONSOLE_NAME|PROJECT_MOTTO|#|$)' \
        "$DIST_DIR/deadshot.conf" > "$STAGING_DIR/deadshot.conf"
    echo 'PROXY_ADDR="REDACTED"' >> "$STAGING_DIR/deadshot.conf"
    echo 'OPSEC_ENABLE_MAC_SPOOF="0"' >> "$STAGING_DIR/deadshot.conf"
fi

# 2. deadshot_scope.json — jq redact
if [ -f "$DIST_DIR/deadshot_scope.json" ]; then
    jq '.
        + {allowed_targets: ["0.0.0.0"], engagement_id: "REDACTED", approved_by: "REDACTED", approved_at_utc: "1970-01-01T00:00:00Z", expires_utc: "2099-01-01T00:00:00Z", notes: "REDACTED"}
        | .max_actions_per_run = 1
    ' "$DIST_DIR/deadshot_scope.json" > "$STAGING_DIR/deadshot_scope.json"
fi

# 3. deadshot_agents_policy.json — jq redact
if [ -f "$DIST_DIR/deadshot_agents_policy.json" ]; then
    jq '.
        + {allowed_actions: {"sentinel.analyze": true, "operator.plan": true}, blocked_patterns: [], require_approval_for: []}
        | .default_action = "deny"
        | .version = 1
    ' "$DIST_DIR/deadshot_agents_policy.json" > "$STAGING_DIR/deadshot_agents_policy.json"
fi

# 4. Copy all other files as-is (except the three above)
for f in "$DIST_DIR"/*; do
    base="$(basename "$f")"
    case "$base" in
        deadshot.conf|deadshot_scope.json|deadshot_agents_policy.json) ;;
        *) cp "$f" "$STAGING_DIR/" ;;
    esac
done

# 5. Validation

# IP validation: abort if any IP except 0.0.0.0 is found in deadshot_scope.json
if grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$STAGING_DIR/deadshot_scope.json" | grep -v '^0\.0\.0\.0$' | grep -q .; then
    echo "[!] Sanitization failed: Real IP found in deadshot_scope.json"
    exit 1
fi

# Internal identifier validation: only check file contents, not filenames
for file in "$STAGING_DIR"/*; do
    # Only scan text files
    if file "$file" | grep -q 'text'; then
        filename="$(basename "$file")"
        
        # Absolute leaks: Always forbidden everywhere (system paths, specific IDs)
        absolute_leaks='(owner|LOCAL-LAB|FSOS|/home/|/run/|/tmp/|/var/|/Users/|/root/|/etc/)'
        
        # Metadata keys: Required for scope JSON, forbidden elsewhere
        metadata_keys='(approved_by|engagement_id|notes)'

        # 1. Check for absolute leaks across all files
        if grep -E -i -q "$absolute_leaks" "$file"; then
            echo "[!] Sanitization failed: Internal identifier or path leakage detected in $file"
            exit 1
        fi

        # 2. Check for metadata keys ONLY if not the scope JSON
        if [ "$filename" != "deadshot_scope.json" ]; then
            if grep -E -i -q "$metadata_keys" "$file"; then
                echo "[!] Sanitization failed: Unexpected metadata key leakage detected in $file"
                exit 1
            fi
        fi
    fi
done

# 6. Regenerate manifest for the sanitized set
# Since we redacted some files, we must update the SHA256SUMS to match the new content.
echo "[*] Updating manifest for sanitized artifacts..."
(
    cd "$STAGING_DIR"
    sha256sum deadshot deadshot_shield deadshot_ui deadshot_agents deadshot.conf deadshot_agents_policy.json deadshot_scope.json LICENSE.md > SHA256SUMS
)

echo "[+] Artifacts sanitized and validated in $STAGING_DIR"
