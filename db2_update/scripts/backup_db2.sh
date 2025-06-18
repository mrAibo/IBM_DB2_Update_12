#!/bin/bash

# == Configuration Variables ==
# DB2 instance name
INSTANCE="db2inst1"

# Database name to be backed up.
# Set to "ALL" (case-insensitive) or leave empty to back up all user databases in the instance.
DB_NAME="LARGEDB"

# Backup target directory/directories.
# For multiple paths, separate them with commas (e.g., "/backup/path1,/backup/path2").
# If "ALL" databases are backed up to a single path, subdirectories per DB will be created.
BACKUP_DIR="/backup/fast1,/backup/fast2,/backup/fast3"

# UTIL_HEAP_SZ configuration for the database manager.
UTIL_HEAP="400000" # Example: 400000 * 4KB = ~1.56GB. Adjust as needed.

# Backup parameters
NUM_BUFFERS=16
# BUFFER_SIZE_PAGES is hardcoded to 256 (1MB) in the backup command below.
PARALLELISM_LEVEL=8     # Number of parallel operations

# --- Global Variables & Logging Setup ---
LOG_FILE="/tmp/db2_backup_script_${INSTANCE}_$(date +%Y%m%d_%H%M%S).log"
ALL_DBS_MODE=false # Flag to indicate if we are in "ALL databases" mode

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - $1" | tee -a "$LOG_FILE"
}

# --- Backup Function for a Single Database ---
process_single_database() {
    local current_db_name="$1"
    log_message "Processing backup for database: '$current_db_name'..."

    local effective_backup_dir="$BACKUP_DIR"
    # If ALL_DBS_MODE is true and BACKUP_DIR is a single path (no commas), create a subdirectory.
    if [ "$ALL_DBS_MODE" = true ] && [[ "$BACKUP_DIR" != *","* ]]; then
        effective_backup_dir="${BACKUP_DIR}/${current_db_name}"
        log_message "Adjusted backup directory for $current_db_name to: $effective_backup_dir"
        if ! mkdir -p "$effective_backup_dir"; then
            log_message "  ERROR: Could not create subdirectory $effective_backup_dir. Using $BACKUP_DIR. This may cause issues if multiple DBs are backed up to the same single path without subdirectories."
            effective_backup_dir="$BACKUP_DIR" # Fallback
        fi
    fi

    log_message "Starting backup for database '$current_db_name' to '$effective_backup_dir'..."
    log_message "Buffers: $NUM_BUFFERS, Buffer Size (pages): 256 (for 1MB), Parallelism: $PARALLELISM_LEVEL"

    local backup_output
    # Ensure the heredoc does not expand variables locally by quoting HEREDOC_END or parts of it.
    # Variables like $INSTANCE, $current_db_name, $effective_backup_dir, etc., ARE intended for expansion here.
    backup_output=$(su - "$INSTANCE" <<HEREDOC_END
. \$HOME/sqllib/db2profile # Source profile for the instance user
db2 backup db "$current_db_name" \
  to "$effective_backup_dir" \
  with $NUM_BUFFERS buffers \
  buffer 256 \
  parallelism $PARALLELISM_LEVEL \
  compress \
  include logs \
  without prompting
echo "DB2_BACKUP_RC:\$?_DB2_BACKUP_RC"
HEREDOC_END
    )

    echo "$backup_output" >> "$LOG_FILE" # Log all output from su block

    local THE_BACKUP_RC=99 # Default to unknown error

    if [[ "$backup_output" =~ DB2_BACKUP_RC:([0-9]+)_DB2_BACKUP_RC ]]; then
        THE_BACKUP_RC=${BASH_REMATCH[1]}
    else
        log_message "WARNING: Could not determine specific DB2 backup RC for $current_db_name from output marker."
        if echo "$backup_output" | grep -q -E "SQL[0-9]{4,5}[NECWF]|DBA[0-9]{4,5}|ERROR|failed|abend"; then
             log_message "Error pattern detected in backup output for $current_db_name."
             THE_BACKUP_RC=1
        elif echo "$backup_output" | grep -q -E "Backup successful|completed successfully"; then
             log_message "Success pattern detected in backup output for $current_db_name, but RC marker was missing."
             THE_BACKUP_RC=0
        else
             log_message "No clear success/failure pattern or RC marker in backup output for $current_db_name. Check logs thoroughly. Output was: $backup_output"
        fi
    fi

    if [ "$THE_BACKUP_RC" -eq 0 ]; then
        log_message "DB2 backup command for '$current_db_name' completed successfully (RC: $THE_BACKUP_RC)."
        return 0
    else
        log_message "ERROR during DB2 backup for '$current_db_name'. Effective Return Code: $THE_BACKUP_RC"
        log_message "Please check DB2 diagnostic logs and $LOG_FILE for full output."
        return 1
    fi
}

# --- Main Script Logic ---
log_message "DB2 Backup Script started."
log_message "Instance: $INSTANCE, Configured DB_NAME: '$DB_NAME', Backup Dir: $BACKUP_DIR, Log: $LOG_FILE"

log_message "Updating DBM CFG for UTIL_HEAP_SZ to $UTIL_HEAP for instance '$INSTANCE'..."
if ! su - "$INSTANCE" -c ". \$HOME/sqllib/db2profile; db2 update dbm cfg using UTIL_HEAP_SZ $UTIL_HEAP" >> "$LOG_FILE" 2>&1; then
    log_message "ERROR: Failed to update DBM CFG for UTIL_HEAP_SZ. Exiting."
    exit 1
fi

log_message "Restarting DB2 instance '$INSTANCE' to apply DBM CFG changes..."
log_message "NOTE: This involves a 'db2stop force'. Ensure this is acceptable for your environment."
if ! su - "$INSTANCE" -c ". \$HOME/sqllib/db2profile; db2stop force" >> "$LOG_FILE" 2>&1; then
    log_message "WARNING: 'db2stop force' failed for instance '$INSTANCE'. Continuing with caution, but this may affect DBM CFG application or db2start."
fi
if ! su - "$INSTANCE" -c ". \$HOME/sqllib/db2profile; db2start" >> "$LOG_FILE" 2>&1; then
    log_message "ERROR: 'db2start' failed for instance '$INSTANCE'. Exiting."
    exit 1
fi
log_message "DB2 instance '$INSTANCE' restarted and DBM CFG should be applied."

overall_rc=0
UC_DB_NAME="${DB_NAME^^}" # Convert DB_NAME to uppercase for case-insensitive "ALL" check

if [ -z "$DB_NAME" ] || [ "$UC_DB_NAME" = "ALL" ]; then # Check original DB_NAME for empty, UC_DB_NAME for "ALL"
    log_message "DB_NAME is '$DB_NAME' (interpreted as ALL). Attempting to back up all user databases for instance '$INSTANCE'."
    ALL_DBS_MODE=true

    DB_LIST_CMD="db2 list db directory | awk '/Database alias/ {print \\$NF}' | grep -vE '^SQL[0-9]{5}N\$|^DSN[0-9]{4,5}[A-Z0-9]\$' | sort -u"

    mapfile_output=$(su - "$INSTANCE" -c ". \$HOME/sqllib/db2profile; $DB_LIST_CMD")
    su_rc=$? # Capture exit status of the su command itself

    if [ $su_rc -ne 0 ] || ([ $su_rc -eq 0 ] && [ -z "$mapfile_output" ]); then
        log_message "  WARNING/ERROR: Failed to list databases or no databases found for instance '$INSTANCE'. SU RC: $su_rc. Output: '$mapfile_output'."
        # If mapfile_output is empty and su_rc is 0, it means no DBs were found by the command.
        # If su_rc is non-zero, the command itself failed.
    fi

    DATABASE_NAMES=()
    mapfile -t DATABASE_NAMES < <(printf '%s\n' "$mapfile_output")

    if [ ${#DATABASE_NAMES[@]} -eq 0 ]; then
        log_message "  No user databases discovered or instance unavailable. No backups will be performed based on dynamic discovery."
        # If DB_NAME was explicitly "ALL" or empty, this is an issue.
        if [ "$UC_DB_NAME" = "ALL" ] || [ -z "$DB_NAME" ]; then
             overall_rc=1 # Consider this a failure if "ALL" was intended but no DBs found/listed
             log_message "  ERROR: Expected to back up ALL databases but none were found or listing failed."
        fi
    else
        log_message "  Discovered databases to back up: ${DATABASE_NAMES[*]}"
        for current_db in "${DATABASE_NAMES[@]}"; do
            if ! process_single_database "$current_db"; then
                log_message "Backup failed for database $current_db. See logs above."
                overall_rc=1
            fi
        done
    fi
else
    log_message "Processing single database as specified: $DB_NAME"
    ALL_DBS_MODE=false
    if ! process_single_database "$DB_NAME"; then
        overall_rc=1
    fi
fi

if [ "$overall_rc" -eq 0 ]; then
    log_message "All designated backup operations completed successfully."
else
    log_message "One or more backup operations failed. Please check logs at $LOG_FILE."
fi

log_message "DB2 Backup Script finished."
exit $overall_rc
