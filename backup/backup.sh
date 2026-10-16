#!/bin/sh
# Dumps the database on an interval, prunes old local dumps and, if BACKUP_S3_BUCKET is set, uploads each dump to S3.
# Connection settings come from the standard PGHOST/PGUSER/PGPASSWORD/PGDATABASE variables.
set -u

BACKUP_DIR=/backups
INTERVAL="${BACKUP_INTERVAL_SECONDS:-86400}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
BUCKET="${BACKUP_S3_BUCKET:-}"

trap 'exit 0' TERM INT

log() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
}

backup_once() {
    name="${PGDATABASE}-$(date -u +%Y%m%dT%H%M%SZ).dump"
    tmp="${BACKUP_DIR}/.${name}.partial"

    # Custom format is compressed and restorable with pg_restore; write to a temp file so a failed dump never looks complete
    if ! pg_dump --format=custom --file="$tmp"; then
        log "ERROR: pg_dump failed"
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "${BACKUP_DIR}/${name}"
    log "Wrote ${BACKUP_DIR}/${name} ($(du -h "${BACKUP_DIR}/${name}" | cut -f1))"

    if [ -n "$BUCKET" ]; then
        if aws s3 cp --only-show-errors "${BACKUP_DIR}/${name}" "s3://${BUCKET}/${name}"; then
            log "Uploaded s3://${BUCKET}/${name}"
        else
            log "ERROR: upload to s3://${BUCKET} failed, local copy kept"
        fi
    fi

    find "$BACKUP_DIR" -name '*.dump' -mtime +"$KEEP_DAYS" -print -delete | while read -r old; do
        log "Pruned $old"
    done
}

log "Backing up every ${INTERVAL}s, keeping ${KEEP_DAYS} days locally${BUCKET:+, uploading to s3://$BUCKET}"
while true; do
    backup_once
    # Sleep in the background so a stop signal is handled immediately
    sleep "$INTERVAL" &
    wait $!
done
