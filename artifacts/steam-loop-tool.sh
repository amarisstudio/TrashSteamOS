#!/bin/bash
# steam-loop-tool.sh — diagnose and (optionally) fix the Steam client
# update/re-login loop on the trash can.
#
# Usage (run as deck, NOT with sudo):
#   bash steam-loop-tool.sh           # report only — changes nothing
#   bash steam-loop-tool.sh fix       # report + park stale bootstrap.tar.xz
#
# Writes a full report next to this script (i.e. onto the USB stick if you
# run it from there), so it can be carried back for analysis.
set -u

MODE=${1:-report}
STEAMROOT="$HOME/.local/share/Steam"
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$SCRIPTDIR/steam-report-$STAMP.txt"
# Fall back to /tmp if the stick is somehow read-only
touch "$REPORT" 2>/dev/null || REPORT="/tmp/steam-report-$STAMP.txt"

log() { echo "$@" | tee -a "$REPORT"; }
section() { log ""; log "===== $* ====="; }

log "steam-loop-tool $STAMP  mode=$MODE  host=$(uname -r)"

section "Is Steam running?"
if pgrep -f "$STEAMROOT" > /dev/null 2>&1 || pgrep -x steam > /dev/null 2>&1; then
    STEAM_RUNNING=1
    log "YES — Steam appears to be running. Report will proceed; fix will be SKIPPED."
    pgrep -af "steam" | head -5 | tee -a "$REPORT"
else
    STEAM_RUNNING=0
    log "No Steam client processes found."
fi

section "Staged bootstrap archive (the prime suspect)"
if [ -f "$STEAMROOT/bootstrap.tar.xz" ]; then
    ls -la "$STEAMROOT/bootstrap.tar.xz" | tee -a "$REPORT"
else
    log "bootstrap.tar.xz NOT present."
fi

section "Update channel state (package/)"
log "beta file: $(cat "$STEAMROOT/package/beta" 2>/dev/null || echo '<missing>')"
ls -la "$STEAMROOT/package/" 2>/dev/null | head -10 | tee -a "$REPORT"

section "Steam root — what changed recently"
ls -la "$STEAMROOT" 2>/dev/null | head -25 | tee -a "$REPORT"

section "Bootstrap log (this session's reasoning)"
head -25 "$STEAMROOT/logs/bootstrap_log.txt" 2>/dev/null | tee -a "$REPORT" \
    || log "bootstrap_log.txt missing (logs dir wiped since last exit)"

section "Login state files"
ls -la "$HOME/.steam/registry.vdf" "$STEAMROOT/config/loginusers.vdf" 2>&1 | tee -a "$REPORT"

section "Extraction errors in journal (this boot)"
journalctl --user -b --no-pager 2>/dev/null | grep "tar:" | head -6 | tee -a "$REPORT"
journalctl --user -b --no-pager 2>/dev/null | grep -c "tar:" | xargs -I{} log "total tar error lines this boot: {}"

section "Disk sanity"
df -h /home | tee -a "$REPORT"

section "Launcher script wipe-condition (context for analysis)"
grep -n "Setting up Steam content" /usr/bin/steam 2>/dev/null | tee -a "$REPORT"
BLINE=$(grep -n "Setting up Steam content" /usr/bin/steam 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "${BLINE:-}" ]; then
    START=$((BLINE > 30 ? BLINE - 30 : 1))
    sed -n "${START},$((BLINE + 20))p" /usr/bin/steam | tee -a "$REPORT"
fi

if [ "$MODE" = "fix" ]; then
    section "FIX: parking stale bootstrap.tar.xz"
    if [ "$STEAM_RUNNING" = 1 ]; then
        log "SKIPPED: exit Steam first, then re-run: bash $0 fix"
    elif [ -f "$STEAMROOT/bootstrap.tar.xz" ]; then
        mv -v "$STEAMROOT/bootstrap.tar.xz" "$HOME/parked-bootstrap-$STAMP.tar.xz" | tee -a "$REPORT"
        log "Parked (not deleted) to ~/parked-bootstrap-$STAMP.tar.xz — reversible with mv."
        log "NOW: launch Steam. If it opens fast, with no 'packaging update', still logged in"
        log "     (or remembering you after one final login) -> loop confirmed dead."
    else
        log "Nothing to park — bootstrap.tar.xz not present."
    fi
fi

section "Done"
log "Report saved to: $REPORT"
log "Bring this file back for analysis."
