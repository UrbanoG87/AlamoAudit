#!/usr/bin/env bash
set -u
TOOL_NAME="AlamoAudit"
zenity --info --width=360 --title="$TOOL_NAME" \
  --text="$TOOL_NAME has started." \
  2>/dev/null || echo "[$TOOL_NAME] started"
sudo -v
WORKDIR="$HOME/${TOOL_NAME}_reports"
mkdir -p "$WORKDIR"
REPORT="$WORKDIR/report_$(date +%F_%H%M%S).txt"
touch "$REPORT"

log() {
    echo "$*" | tee -a "$REPORT"
}

section() {
    log ""
    log "===== $* ====="
}

log "$TOOL_NAME security report"
log "Generated: $(date)"
log "Host: $(hostname)"
log "Run by: $(whoami)"
section "System administration"
log "Operating system: $(uname -srm)"
log "Uptime: $(uptime -p)"
log "Disk usage on /:"
df -h / | tee -a "$REPORT"

log "Accounts with root privileges (UID 0):"
awk -F: '$3 == 0 {print "  " $1}' /etc/passwd | tee -a "$REPORT"

log "Members of the sudo group:"
getent group sudo | cut -d: -f4 | tr ',' '\n' | tee -a "$REPORT"

UPGRADES=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
log "Packages that can be upgraded: $UPGRADES"
section "Process control"
log "Total running processes: $(ps -e --no-headers | wc -l)"

log "Top 5 processes by CPU:"
ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6 | tee -a "$REPORT"

log "Top 5 processes by memory:"
ps -eo pid,comm,%mem --sort=-%mem | head -n 6 | tee -a "$REPORT"

log "Network services that are listening:"
ss -tuln | tee -a "$REPORT"

log "Starting a temporary background watcher..."
sleep 120 &
WATCHER_PID=$!
log "Watcher started as PID $WATCHER_PID"
kill "$WATCHER_PID" && log "Watcher (PID $WATCHER_PID) stopped"
section "File and permission audit"

WORLD_WRITABLE=$(find /home -xdev -type f -perm -0002 2>/dev/null | wc -l)
log "World writable files under /home: $WORLD_WRITABLE"
find /home -xdev -type f -perm -0002 2>/dev/null | tee -a "$REPORT"

log "SUID programs under /usr/bin and /usr/sbin:"
find /usr/bin /usr/sbin -xdev -type f -perm -4000 2>/dev/null | tee -a "$REPORT"

log "Permissions on sensitive files:"
ls -l /etc/passwd /etc/shadow | tee -a "$REPORT"
section "Hardening actions"

FW_ENABLED=0
if command -v ufw >/dev/null; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    FW_STATUS=$(sudo ufw status verbose)
    log "$FW_STATUS"
    if grep -qx 'Status: active' <<< "$FW_STATUS"; then
        FW_ENABLED=1
    fi
else
    log "UFW is not installed."
fi

if sudo test -f /var/log/auth.log; then
    FAILED=$(sudo awk '/sshd.*Failed password/ {n++} END {print n+0}' /var/log/auth.log)
else
    FAILED=$(sudo journalctl -u ssh.service --no-pager | awk '/Failed password/ {n++} END {print n+0}')
fi
log "Failed SSH login attempts on record: $FAILED"

EMPTY=$(sudo awk -F: '$2 == "" {n++} END {print n+0}' /etc/shadow)
log "Accounts with an EMPTY password: $EMPTY (should be 0)"
section "Security score"
SCORE=100

[ "$UPGRADES" -gt 0 ] && SCORE=$((SCORE - 10))
[ "$WORLD_WRITABLE" -gt 0 ] && SCORE=$((SCORE - 15))
[ "$FAILED" -gt 20 ] && SCORE=$((SCORE - 10))
[ "$EMPTY" -gt 0 ] && SCORE=$((SCORE - 30))
[ "$FW_ENABLED" -eq 0 ] && SCORE=$((SCORE - 20))
[ "$SCORE" -lt 0 ] && SCORE=0

if [ "$SCORE" -ge 90 ]; then
    RATING="STRONG"
elif [ "$SCORE" -ge 70 ]; then
    RATING="MODERATE"
else
    RATING="NEEDS WORK"
fi

log "Security score: $SCORE / 100 ($RATING)"
section "Finishing up"
chmod 600 "$REPORT"
log "Report locked to owner only (chmod 600)."
log "Report saved to: $REPORT"

zenity --info --width=420 --title="$TOOL_NAME" \
    --text="$TOOL_NAME has completed.
Security score: $SCORE / 100 ($RATING)
Report saved to: $REPORT" \
    2>/dev/null || echo "[$TOOL_NAME] completed. Score: $SCORE/100"
