#!/bin/bash

# == Configuration Variables ==
# It's recommended to review and adjust these variables to match your environment.

# DB2 instance name
INSTANCE="db2inst1"

# Database name to be restored
DB_NAME="LARGEDB"

# Backup directory/directories from where to restore.
# This should match the BACKUP_DIR used in the backup script.
BACKUP_DIR="/backup/fast1,/backup/fast2,/backup/fast3"

# Directory containing DB2 data - WILL BE WIPED!
DB2_DATA_DIR="/db2data" # Example, adjust to your environment

# Directory containing DB2 logs - WILL BE WIPED!
DB2_LOGS_DIR="/db2logs" # Example, adjust to your environment

# Restore parameters
# The issue suggests 1.5x Backup-Buffers for restore. If backup used 16, then 1.5*16 = 24.
NUM_BUFFERS=24
# Buffer size in pages (1MB per buffer = 256 pages of 4KB).
BUFFER_SIZE_PAGES=256
# Parallelism for restore, suggested as 75% of CPU cores.
PARALLELISM_LEVEL=12

# == Script Start ==
echo "Starting DB2 restore process for database '$DB_NAME'..."
echo "Timestamp: $(date)"

# --- WARNING ---
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! WARNING: This script will stop the DB2 instance and ERASE all data in  !!!"
echo "!!! $DB2_DATA_DIR and $DB2_LOGS_DIR before starting the restore.        !!!"
echo "!!! Ensure you have a valid backup and understand the consequences.        !!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "You have 10 seconds to cancel (Ctrl+C)..."
sleep 10
echo "Proceeding with restore..."
# --- END WARNING ---

# Preparation
echo "Stopping DB2 instance '$INSTANCE' (force)..."
su - $INSTANCE -c "db2stop force"
if [ $? -ne 0 ]; then
  echo "Error stopping DB2 instance. This might not be critical if instance was already stopped."
  # Not exiting, as the main goal is to ensure it's stopped.
fi
echo "DB2 instance stopped."

echo "Cleaning database and log directories..."
echo "Removing contents of $DB2_DATA_DIR/* ..."
rm -rf ${DB2_DATA_DIR}/*
if [ $? -ne 0 ]; then
  echo "Error removing data from $DB2_DATA_DIR. Please check permissions and path. Exiting."
  exit 1
fi
echo "Removing contents of $DB2_LOGS_DIR/* ..."
rm -rf ${DB2_LOGS_DIR}/*
if [ $? -ne 0 ]; then
  echo "Error removing data from $DB2_LOGS_DIR. Please check permissions and path. Exiting."
  exit 1
fi
echo "Database and log directories cleaned."

# Restore command
echo "Starting restore for database '$DB_NAME'..."
echo "Restore from: $BACKUP_DIR"
echo "Buffers: $NUM_BUFFERS"
echo "Buffer Size (pages): $BUFFER_SIZE_PAGES (for 1MB per buffer)"
echo "Parallelism: $PARALLELISM_LEVEL"

su - $INSTANCE << EOF
db2 restore db $DB_NAME   from $BACKUP_DIR   with $NUM_BUFFERS buffers   buffer $BUFFER_SIZE_PAGES   parallelism $PARALLELISM_LEVEL   without prompting   replace existing
EOF

RESTORE_RC=$?

if [ $RESTORE_RC -eq 0 ]; then
  echo "DB2 restore command completed successfully."
else
  echo "Error during DB2 restore. Return Code: $RESTORE_RC"
  echo "Please check DB2 diagnostic logs for more details."
  # Consider what to do here. If restore fails, db2updv121 and db2start might not be appropriate.
  exit 1
fi

# Post-Restore
echo "Running post-restore operations..."

# The db2updv121 command is specific for V12.1.
# Add a condition or comment if this script is to be more generic.
echo "Running db2updv121 -d $DB_NAME (specific to DB2 V12.1)..."
su - $INSTANCE -c "db2updv121 -d $DB_NAME"
if [ $? -ne 0 ]; then
  echo "Warning: db2updv121 returned an error. This might be an issue depending on the restore scenario."
  # Not exiting, as the database might still be usable or require manual checks.
fi

echo "Starting DB2 instance '$INSTANCE'..."
su - $INSTANCE -c "db2start"
if [ $? -ne 0 ]; then
  echo "Error starting DB2 instance post-restore. Please check DB2 logs."
  exit 1
fi
echo "DB2 instance started."

echo "Restore process for database '$DB_NAME' finished."
echo "Timestamp: $(date)"
# == Script End ==
