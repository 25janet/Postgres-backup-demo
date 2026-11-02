#!/bin/bash

# =============================================================================
# PostgreSQL Backup Retention Script
# Purpose: Remove backup archives older than the retention period.
# Default: Dry-run only. Use --delete to remove expired backups.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BACKUP_DIR="$PROJECT_DIR/backups"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/cleanup.log"

RETENTION_DAYS=7
MODE="${1:---dry-run}"

# ---------------------------------------------------------------------------
# 1. Validate execution mode
# ---------------------------------------------------------------------------

if [[ "$MODE" != "--dry-run" && "$MODE" != "--delete" ]]; then
    echo "Usage: $0 [--dry-run|--delete]"
    exit 1
fi

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup cleanup. Mode: $MODE"
log "Retention period: $RETENTION_DAYS days"

# ---------------------------------------------------------------------------
# 2. Identify expired backups
# ---------------------------------------------------------------------------

FOUND=0
DELETED=0

while IFS= read -r -d '' BACKUP_FILE; do
    FOUND=$((FOUND + 1))

    CHECKSUM_FILE="${BACKUP_FILE}.sha256"

    log "Expired backup found: $(basename "$BACKUP_FILE")"

    if [[ "$MODE" == "--dry-run" ]]; then
        log "DRY RUN: Would delete backup and checksum."
        continue
    fi

    # Remove the backup archive.
    rm -- "$BACKUP_FILE"

    # Remove its checksum if present.
    if [[ -f "$CHECKSUM_FILE" ]]; then
        rm -- "$CHECKSUM_FILE"
    fi

    DELETED=$((DELETED + 1))
    log "Deleted expired backup: $(basename "$BACKUP_FILE")"

done < <(
    find "$BACKUP_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'backup_lab_*.dump' \
        -mmin "+$((RETENTION_DAYS * 1440))" \
        -print0
)

# ---------------------------------------------------------------------------
# 3. Report cleanup results
# ---------------------------------------------------------------------------

if [[ "$FOUND" -eq 0 ]]; then
    log "No expired backups found."
fi

log "Expired backups found: $FOUND"
log "Backups deleted: $DELETED"
log "Cleanup process finished."
