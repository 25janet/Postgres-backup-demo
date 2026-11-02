#!/bin/bash

# =============================================================================
# PostgreSQL Backup Verification Script
# Purpose: Verify backup existence, checksum and archive readability.
# =============================================================================

set -Eeuo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../backups" && pwd)"

# Use the supplied backup filename, or select the most recent one.
if [[ $# -ge 1 ]]; then
    BACKUP_FILE="$1"
else
    BACKUP_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f \
        -name 'backup_lab_*.dump' -printf '%T@ %p\n' |
        sort -nr | head -n 1 | cut -d' ' -f2-)"
fi

if [[ -z "${BACKUP_FILE:-}" || ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: No valid backup file found."
    exit 1
fi

CHECKSUM_FILE="${BACKUP_FILE}.sha256"

echo "Starting backup verification..."
echo "Backup: $BACKUP_FILE"

# Check that the backup is not empty.
if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file is empty."
    exit 1
fi

echo "[1/3] Backup file exists and is not empty: OK"

# Verify the checksum from the backup's directory.
if [[ ! -f "$CHECKSUM_FILE" ]]; then
    echo "ERROR: Checksum file is missing: $CHECKSUM_FILE"
    exit 1
fi

(
    cd "$(dirname "$BACKUP_FILE")"
    sha256sum -c "$(basename "$CHECKSUM_FILE")"
)

echo "[2/3] SHA-256 checksum: OK"

# Check that PostgreSQL can read the archive's table of contents.
pg_restore --list "$BACKUP_FILE" >/dev/null

echo "[3/3] PostgreSQL archive inspection: OK"

echo "SUCCESS: All backup verification checks passed."
