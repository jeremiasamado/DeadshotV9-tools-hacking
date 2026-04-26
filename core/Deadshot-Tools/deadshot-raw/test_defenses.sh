#!/bin/bash
# test_defenses.sh — Red Team Dynamic Defense Validation for Deadshot Tools

set -euo pipefail

SHIELD_SCRIPT="./deadshot_shield.sh"
AGENTS_PY="./deadshot_agents.py"
TEST_USER="deadshot"

# GUARANTEED CLEANUP TRAP
trap 'if [ -f "${SHIELD_SCRIPT}.bak" ]; then mv "${SHIELD_SCRIPT}.bak" "$SHIELD_SCRIPT"; echo "[*] Cleanup: Restored original shield script."; fi' EXIT

echo "=== [1] Privilege Drop Validation ==="
sudo bash -c "
    $SHIELD_SCRIPT daemon &
    sleep 2
    # Specifically target the process running as the dropped user
    SHIELD_PID=\$(pgrep -u $TEST_USER -f \"deadshot_shield\" | head -n 1)
    
    if [ -z \"$SHIELD_PID\" ]; then
        echo '[!] Honeypot process not found running under $TEST_USER.' >&2
        pkill -f \"deadshot_shield\" || true
        exit 1
    fi
    
    PROC_USER=\$(ps -o user= -p $SHIELD_PID | tr -d ' ')
    if [ \"$PROC_USER\" != \"$TEST_USER\" ]; then
        echo '[FAIL] Privilege drop failed: honeypot running as '$PROC_USER', expected $TEST_USER.' >&2
        pkill -f \"deadshot_shield\" || true
        exit 1
    fi
    echo '[OK] Honeypot privilege drop enforced: running as $TEST_USER.'
    pkill -f \"deadshot_shield\" || true
"

echo "=== [2] Environment Injection Test ==="
export TOOLS_DIR='../../etc'
# Run without sudo so runuser doesn't strip the environment before the check
if $SHIELD_SCRIPT daemon 2>&1 | grep -q 'CRITICAL: TOOLS_DIR'; then
    echo '[OK] Environment variable injection correctly blocked.'
else
    echo '[FAIL] Environment variable injection was not blocked!' >&2
    exit 1
fi
unset TOOLS_DIR

echo "=== [3] Trust Anchor / Hash Bypass Test ==="
cp "$SHIELD_SCRIPT" "${SHIELD_SCRIPT}.bak"
echo "# redteam" >> "$SHIELD_SCRIPT"

if python3 "$AGENTS_PY" --shield-daemon 2>&1 | grep -q 'Integrity check failed\|No hash entry\|SHA256SUMS'; then
    echo '[OK] Hash mismatch correctly blocked execution.'
else
    echo '[FAIL] Hash mismatch did NOT block execution!' >&2
    exit 1
fi

echo "=== All dynamic defense tests completed successfully. ==="
