#!/bin/bash

# == Configuration Variables ==
# It's recommended to review and adjust these variables to match your environment.

# DB2 instance name
INSTANCE="db2inst1"

# Database name to be backed up
DB_NAME="LARGEDB"

# Backup target directory/directories.
# For multiple paths, separate them with commas (e.g., "/backup/path1,/backup/path2").
# Using multiple paths to different physical devices can improve I/O performance.
BACKUP_DIR="/backup/fast1,/backup/fast2,/backup/fast3"

# UTIL_HEAP_SZ configuration for the database manager.
# This value is in 4KB pages. 400000 * 4KB = 1,600,000 KB ~ 1.56 GB.
# The issue description mentioned ~4GB (400,000 * 4KB), which seems to be a miscalculation.
# Let's use a value that would be closer to 4GB if that was the intent.
# 1048576 * 4KB = 4194304 KB = 4GB. So, UTIL_HEAP should be 1048576.
# The original script had 400000. We will stick to the original script's value for now,
# but add a comment highlighting this.
UTIL_HEAP="400000" # Original value from issue. For ~4GB, this would be 1048576.

# Backup parameters
NUM_BUFFERS=16
BUFFER_SIZE_PAGES=1048576 # Buffer size in pages (1048576 * 4KB = 4GB per buffer -- this seems too large for a *single* buffer. The issue has 1MB per buffer, which is 1048576 bytes / 4096 bytes/page = 256 pages)
                          # Let's use 256 pages for 1MB buffer size, as commented in the issue.
PARALLELISM_LEVEL=8     # Number of parallel operations, typically related to CPU cores.

# == Script Start ==
echo "Starting DB2 backup process for database '$DB_NAME'..."
echo "Timestamp: $(date)"

# Configuration before backup
echo "Updating DBM CFG for UTIL_HEAP_SZ to $UTIL_HEAP..."
su - $INSTANCE -c "db2 update dbm cfg using UTIL_HEAP_SZ $UTIL_HEAP"
if [ $? -ne 0 ]; then
  echo "Error updating DBM CFG. Exiting."
  exit 1
fi

echo "Restarting DB2 instance '$INSTANCE' to apply DBM CFG changes..."
echo "NOTE: This involves a 'db2stop force'. Ensure this is acceptable for your environment."
su - $INSTANCE -c "db2stop force"
if [ $? -ne 0 ]; then
  echo "Error stopping DB2 instance. Continuing with caution, but db2start might fail or config might not be applied."
  # Not exiting here, as db2start might still recover or the user might want to intervene.
fi
su - $INSTANCE -c "db2start"
if [ $? -ne 0 ]; then
  echo "Error starting DB2 instance. Exiting."
  exit 1
fi
echo "DB2 instance restarted."

# Backup command
echo "Starting backup for database '$DB_NAME'..."
echo "Backup directory: $BACKUP_DIR"
echo "Buffers: $NUM_BUFFERS"
echo "Buffer Size (pages): 256 (for 1MB)" # Corrected based on issue comment
echo "Parallelism: $PARALLELISM_LEVEL"

# The issue had "buffer 1048576" which implies bytes for the 'buffer' parameter in db2 backup.
# The db2 backup command's "BUFFER" parameter is in 4KB pages.
# So, 1MB buffer = 1048576 bytes / 4096 bytes/page = 256 pages.

su - $INSTANCE << EOF
db2 backup db $DB_NAME   to $BACKUP_DIR   with $NUM_BUFFERS buffers   buffer 256   parallelism $PARALLELISM_LEVEL   compress   include logs   without prompting
EOF

BACKUP_RC=$?

if [ $BACKUP_RC -eq 0 ]; then
  echo "DB2 backup command completed successfully."
else
  echo "Error during DB2 backup. Return Code: $BACKUP_RC"
  echo "Please check DB2 diagnostic logs for more details."
  exit 1
fi

echo "Backup process for database '$DB_NAME' finished."
echo "Timestamp: $(date)"
# == Script End ==
