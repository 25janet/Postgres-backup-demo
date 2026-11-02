
#!/bin/bash

# =============================================================================
# PostgreSQL Automated Backup Script
# Purpose: Create timestamped logical backups and SHA-256 checksums.
# =============================================================================

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# 1. Project configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DB_NAME="backup_lab"
DB_USER="backup_user"
DB_HOST="127.0.0.1"
DB_PORT="5432"

BACKUP_DIR="$PROJECT_DIR/backups"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/backup.log"

# ---------------------------------------------------------------------------
# 2. Prepare backup directories
# ---------------------------------------------------------------------------

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

chmod 700 "$BACKUP_DIR" "$LOG_DIR"

# ---------------------------------------------------------------------------
# 3. Generate a unique backup filename
# ---------------------------------------------------------------------------

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

BACKUP_FILE="${DB_NAME}_${TIMESTAMP}.dump"
FINAL_PATH="$BACKUP_DIR/$BACKUP_FILE"
CHECKSUM_PATH="$FINAL_PATH.sha256"

# Create a temporary file in the same directory so the final rename is atomic.
TEMP_PATH="$(mktemp "$BACKUP_DIR/.${DB_NAME}_${TIMESTAMP}.XXXXXX.part")"

# ---------------------------------------------------------------------------
# 4. Logging function
# ---------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# 5. Error handling
# ---------------------------------------------------------------------------

cleanup() {
    if [[ -n "${TEMP_PATH:-}" && -f "$TEMP_PATH" ]]; then
        rm -f "$TEMP_PATH"
    fi
}

handle_error() {
    local exit_code=$?
    log "ERROR: Backup failed. Exit code: $exit_code"
    cleanup
    exit "$exit_code"
}

trap handle_error ERR
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 6. Check required commands
# ---------------------------------------------------------------------------

for command in pg_dump pg_restore sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        log "ERROR: Required command '$command' is not installed."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# 7. Configure PostgreSQL authentication
# ---------------------------------------------------------------------------

export PGPASSFILE="${PGPASSFILE:-$HOME/.pgpass}"

if [[ ! -f "$PGPASSFILE" ]]; then
    log "ERROR: PostgreSQL password file not found: $PGPASSFILE"
    exit 1
fi

if [[ "$(stat -c '%a' "$PGPASSFILE")" != "600" ]]; then
    log "ERROR: Password file must have permissions 600."
    exit 1
fi

# ---------------------------------------------------------------------------
# 8. Create the PostgreSQL backup
# ---------------------------------------------------------------------------

log "Starting backup for database: $DB_NAME"

pg_dump \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --username="$DB_USER" \
    --no-password \
    --format=custom \
    --file="$TEMP_PATH" \
    "$DB_NAME"

# ---------------------------------------------------------------------------
# 9. Validate the generated archive
# ---------------------------------------------------------------------------

if [[ ! -s "$TEMP_PATH" ]]; then
    log "ERROR: Backup file is empty."
    exit 1
fi

pg_restore --list "$TEMP_PATH" >/dev/null

# ---------------------------------------------------------------------------
# 10. Publish the completed backup
# ---------------------------------------------------------------------------

mv "$TEMP_PATH" "$FINAL_PATH"
TEMP_PATH=""

# ---------------------------------------------------------------------------
# 11. Generate SHA-256 checksum
# ---------------------------------------------------------------------------

(
    cd "$BACKUP_DIR"
    sha256sum "$BACKUP_FILE" > "$(basename "$CHECKSUM_PATH")"
)

chmod 600 "$FINAL_PATH" "$CHECKSUM_PATH"

# ---------------------------------------------------------------------------
# 12. Report backup results
# ---------------------------------------------------------------------------

BACKUP_SIZE="$(du -h "$FINAL_PATH" | awk '{print $1}')"

log "SUCCESS: Backup completed."
log "Database: $DB_NAME"
log "Backup file: $FINAL_PATH"
log "Backup size: $BACKUP_SIZE"
log "Checksum: $CHECKSUM_PATH"
log "Backup process finished."

