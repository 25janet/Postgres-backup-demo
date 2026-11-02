#!/bin/bash

# =============================================================================
# PostgreSQL Recovery Script
# Purpose: Restore a custom-format backup into the backup_lab database.
# WARNING: The existing backup_lab database will be replaced.
# =============================================================================

set -Eeuo pipefail

TARGET_DB="backup_lab"

# ---------------------------------------------------------------------------
# 1. Select the backup file
# ---------------------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/backup_file.dump"
    exit 1
fi

BACKUP_FILE="$(realpath "$1")"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file does not exist or is empty."
    exit 1
fi

if [[ ! -f "$CHECKSUM_FILE" ]]; then
    echo "ERROR: Checksum file is missing."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Verify the backup before recovery
# ---------------------------------------------------------------------------

echo "Verifying backup before restoration..."

(
    cd "$(dirname "$BACKUP_FILE")"
    sha256sum -c "$(basename "$CHECKSUM_FILE")"
)

pg_restore --list "$BACKUP_FILE" >/dev/null

echo "Backup verification successful."

# ---------------------------------------------------------------------------
# 3. Require explicit confirmation
# ---------------------------------------------------------------------------

echo
echo "WARNING: This operation will replace database: $TARGET_DB"
echo "All existing data in that database will be lost."
echo "Backup selected: $BACKUP_FILE"
echo

read -r -p "Type RESTORE to continue: " CONFIRMATION

if [[ "$CONFIRMATION" != "RESTORE" ]]; then
    echo "Recovery cancelled."
    exit 0
fi

# ---------------------------------------------------------------------------
# 4. Stop active database connections
# ---------------------------------------------------------------------------

echo "Terminating active connections..."

sudo -u postgres psql \
    -v ON_ERROR_STOP=1 \
    -d postgres \
    -c "SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$TARGET_DB'
        AND pid <> pg_backend_pid();"

# ---------------------------------------------------------------------------
# 5. Recreate the target database
# ---------------------------------------------------------------------------

echo "Dropping existing database..."

sudo -u postgres dropdb --if-exists "$TARGET_DB"

echo "Creating fresh database..."

sudo -u postgres createdb "$TARGET_DB"

# ---------------------------------------------------------------------------
# 6. Restore the backup
# ---------------------------------------------------------------------------

echo "Restoring PostgreSQL backup..."

sudo -u postgres pg_restore \
    --exit-on-error \
    --no-owner \
    --dbname="$TARGET_DB" \
    "$BACKUP_FILE"

# ---------------------------------------------------------------------------
# 7. Confirm successful recovery
# ---------------------------------------------------------------------------

echo "Recovery completed successfully."

sudo -u postgres psql \
    -v ON_ERROR_STOP=1 \
    -d "$TARGET_DB" \
    -c "SELECT COUNT(*) AS recovered_employee_records FROM employees;"

echo "Database recovery process finished."
