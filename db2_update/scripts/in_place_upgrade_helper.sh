#!/bin/bash
# Helper Script for DB2 In-Place Upgrade (e.g., 11.5 to 12.1)
# This script provides guidance and commands for an in-place DB2 upgrade.
# It is NOT fully automated. You must run steps, verify, and make decisions.
# Always consult official IBM documentation and test thoroughly in non-prod.

# --- Configuration Variables ---
# TODO: SET THESE VARIABLES BEFORE RUNNING ANY PART OF THIS SCRIPT
OLD_DB2_PATH="/opt/ibm/db2/V11.5"                 # Path to your current (old) DB2 version
NEW_DB2_PATH="/opt/ibm/db2/V12.1"                 # Path to your NEWLY INSTALLED DB2 version software
INSTANCE_NAME="db2inst1"                          # DB2 instance name to upgrade
# DATABASE_NAMES=("SAMPLEDB" "MYDB2")               # This is now dynamically populated below. Old: Array of database names to upgrade (e.g., ("DB1" "DB2"))
ADMIN_USER=""                                     # Admin user for db2ckupgrade, if needed (leave blank if not)
ADMIN_PASS=""                                     # Admin password for db2ckupgrade (will prompt if blank and user is set)

# Path to db2ckupgrade from the NEW DB2 version's installation media (before full install, or from an installed V12.1)
# Example: /mnt/db2_v12_media/server/db2ckupgrade or /opt/ibm/db2/V12.1/bin/db2ckupgrade (if V12.1 already installed)
# TODO: Ensure this path is correct.
DB2CKUPGRADE_PATH="${NEW_DB2_PATH}/bin/db2ckupgrade" # Adjust if V12.1 is not yet installed and using media path

LOG_DIR="/tmp/db2_upgrade_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
MASTER_LOG="${LOG_DIR}/upgrade_master.log"

# --- Helper Functions ---
log_master() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MASTER_LOG"
}

run_as_instance() {
    local cmd="$1"
    log_master "Attempting to run as instance user '$INSTANCE_NAME': $cmd"
    su - "$INSTANCE_NAME" -c "$cmd" >> "$MASTER_LOG" 2>&1
    # Capture and check return code more reliably if needed
}

run_as_root() {
    local cmd="$1"
    log_master "Attempting to run as root: $cmd"
    eval "$cmd" >> "$MASTER_LOG" 2>&1
    # Capture and check return code
}

pause_and_confirm() {
    log_master "PAUSE: $1"
    log_master "Review the output in $MASTER_LOG and specific log files in $LOG_DIR."
    read -p "  Press Enter to continue, or Ctrl+C to abort..."
}

# --- Main Script ---
log_master "=== DB2 In-Place Upgrade Helper Started ==="
log_master "Instance: $INSTANCE_NAME"
log_master "Old DB2 Path: $OLD_DB2_PATH"
log_master "New DB2 Path: $NEW_DB2_PATH"
log_master "Log Directory: $LOG_DIR"
log_master "--- IMPORTANT: This script is a HELPER, not a fully automated solution. ---"
log_master "--- You MUST verify each step and consult IBM documentation. ---"

# Check if running as root for steps that require it
if [ "$(id -u)" -ne 0 ]; then
    log_master "WARNING: Some steps require root privileges. This script should ideally be run as root, or parts requiring root executed manually."
    # For now, we'll continue, but specific commands might fail.
fi

pause_and_confirm "Initial setup verified. Ready to begin pre-upgrade tasks."

# --- Phase 1: Pre-Upgrade Tasks ---
log_master "--- Phase 1: Pre-Upgrade Tasks ---"

log_master "Step 1.1: Ensure System Requirements for new DB2 version are met (OS, memory, disk)."
log_master "  Action: Manual check. Refer to IBM documentation for DB2 $NEW_DB2_PATH."
pause_and_confirm "System requirements checked?"

log_master "Step 1.2: Perform FULL DATABASE BACKUPS for all databases."
log_master "  Refer to 'backup_db2.sh' or your standard backup procedures."
log_master "  Example for a database 'MYDB': su - $INSTANCE_NAME -c "db2 backup database MYDB to /your_backup_location online""
# Add loop if you want to provide example for all
pause_and_confirm "Full backups completed and verified?"

log_master "Step 1.2a: Discovering user databases from instance '$INSTANCE_NAME'..."
# Ensure this command is run in the context of the old DB2 environment
# The grep -vE is an attempt to filter out common system/sample DBs. Adjust regex if needed.
# Common system DB name patterns: SQL#####N, DSN#####N (e.g. SQL00001N for sample, DSN1GWIN for some z/OS related tools if cataloged)
# It's safer to list all and let user be aware. For now, keeping a basic filter.
DB_LIST_CMD="db2 list db directory | awk '/Database alias|Aliasname der Datenbank/ {print \$NF}' | grep -vE '^SQL[0-9]{5}N\$|^DSN[0-9]{4,5}[A-Z0-9]\$' | sort -u"

# Attempt to get database list as instance user. This dynamically discovers all user databases from the instance.
mapfile_output=$(su - "$INSTANCE_NAME" -c ". ${OLD_DB2_PATH}/db2profile; $DB_LIST_CMD")
if [ $? -ne 0 ]; then
    log_master "  ERROR: Failed to execute 'db2 list db directory' as instance user '$INSTANCE_NAME'."
    log_master "  Please ensure the instance is available and profile path is correct."
    # Decide on behavior: exit or continue with empty list and let user manually input?
    # For a helper script, prompting or exiting might be best. For now, log and continue, subsequent steps will show no DBs.
    DATABASE_NAMES=()
else
    mapfile -t DATABASE_NAMES < <(printf '%s\n' "$mapfile_output")
fi

if [ ${#DATABASE_NAMES[@]} -eq 0 ]; then
    log_master "  WARNING: No user databases discovered for instance '$INSTANCE_NAME' or failed to list them."
    log_master "  Database-specific steps will be skipped. Ensure this is expected."
    # Optionally, add a pause_and_confirm here if no DBs are found.
else
    log_master "  Discovered databases to process: ${DATABASE_NAMES[*]}"
fi
# This pause is generally good after discovery or if no DBs found.
pause_and_confirm "Database discovery complete. Review the list above."

log_master "Step 1.3: Run db2ckupgrade for each database."
log_master "  Using db2ckupgrade from: $DB2CKUPGRADE_PATH"
if [ ! -f "$DB2CKUPGRADE_PATH" ]; then
    log_master "  ERROR: db2ckupgrade utility not found at $DB2CKUPGRADE_PATH. Please correct the DB2CKUPGRADE_PATH variable."
    exit 1
fi
for db_name in "${DATABASE_NAMES[@]}"; do
    log_master "  Running db2ckupgrade for database: $db_name"
    CKUPGRADE_LOG="${LOG_DIR}/db2ckupgrade_${db_name}.log"
    cmd_opts=""
    if [ -n "$ADMIN_USER" ]; then
        cmd_opts="-u $ADMIN_USER"
        if [ -n "$ADMIN_PASS" ]; then
            cmd_opts="$cmd_opts -p $ADMIN_PASS"
        else
            # Prompt for password if user is set but pass is not
            read -s -p "Enter password for $ADMIN_USER for $db_name db2ckupgrade: " temp_pass
            echo
            cmd_opts="$cmd_opts -p $temp_pass"
            unset temp_pass
        fi
    fi
    # db2ckupgrade must be run as instance owner, or user with connect & sysadm/sysctrl
    # Assuming instance owner context here by not using run_as_instance for this specific command path
    log_master "  Command: $DB2CKUPGRADE_PATH $db_name -l $CKUPGRADE_LOG $cmd_opts"
    # This command often needs to be run by a user who can connect to the DB, typically the instance owner
    # If this script is run as root, 'su - instance' is needed for this specific tool
    su - "$INSTANCE_NAME" -c "$DB2CKUPGRADE_PATH $db_name -l $CKUPGRADE_LOG $cmd_opts" >> "$MASTER_LOG" 2>&1
    log_master "  db2ckupgrade for $db_name log: $CKUPGRADE_LOG"
    log_master "  IMPORTANT: Review $CKUPGRADE_LOG carefully. Resolve ALL issues before proceeding."
    pause_and_confirm "db2ckupgrade for $db_name reviewed and issues resolved?"
done

log_master "Step 1.4: Save all DB2 configurations."
CONFIG_BACKUP_DIR="${LOG_DIR}/config_backup_11.5"
mkdir -p "$CONFIG_BACKUP_DIR"
log_master "  Saving DBM CFG..."
run_as_instance "db2 GET DBM CFG > ${CONFIG_BACKUP_DIR}/dbm_cfg.txt"
log_master "  Saving db2set variables..."
run_as_instance "db2set -all > ${CONFIG_BACKUP_DIR}/db2set_all.txt"
for db_name in "${DATABASE_NAMES[@]}"; do
    log_master "  Saving DB CFG for $db_name..."
    run_as_instance "db2 CONNECT TO $db_name; db2 GET DB CFG FOR $db_name SHOW DETAIL > ${CONFIG_BACKUP_DIR}/db_cfg_${db_name}.txt; db2 CONNECT RESET"
    log_master "  Saving db2look for $db_name..."
    run_as_instance "db2look -d $db_name -e -l -x -o ${CONFIG_BACKUP_DIR}/db2look_${db_name}.sql"
done
log_master "  Configuration saved to: $CONFIG_BACKUP_DIR"
pause_and_confirm "All configurations saved?"

# --- Phase 2: Installing DB2 New Version Software ---
log_master "--- Phase 2: Installing DB2 New Version Software ---"
log_master "Step 2.1: Install the new DB2 version software (e.g., V12.1) into a NEW path ($NEW_DB2_PATH)."
log_master "  Action: Manual step. Use db2_install or db2setup from the new version's media."
log_master "  Ensure this is done BEFORE proceeding with instance upgrade."
log_master "  Verify new installation with ${NEW_DB2_PATH}/bin/db2level and db2ls."
pause_and_confirm "New DB2 version software installed and verified at $NEW_DB2_PATH?"

# --- Phase 3: Upgrading DB2 Instance ---
log_master "--- Phase 3: Upgrading DB2 Instance ($INSTANCE_NAME) ---"
log_master "Step 3.1: Stop the DB2 instance ($INSTANCE_NAME) running under old version."
log_master "  Ensure all applications are disconnected."
run_as_instance "db2 force application all"
run_as_instance "db2 terminate"
run_as_instance "db2stop force" # Or a clean 'db2stop' if possible
# run_as_instance "db2admin stop" # If applicable
pause_and_confirm "Instance $INSTANCE_NAME stopped?"

log_master "Step 3.2: Upgrade the instance using db2iupgrade. THIS REQUIRES ROOT PRIVILEGES."
log_master "  Command: ${NEW_DB2_PATH}/instance/db2iupgrade $INSTANCE_NAME"
log_master "  Log file for db2iupgrade will typically be in /tmp/db2iupgrade.log.<instance>"
log_master "  If you are not root, you must execute this command manually as root."
if [ "$(id -u)" -eq 0 ]; then
    run_as_root "${NEW_DB2_PATH}/instance/db2iupgrade $INSTANCE_NAME"
else
    log_master "  ACTION REQUIRED: Run the above db2iupgrade command as root."
fi
pause_and_confirm "db2iupgrade command executed? Review its log for success."

log_master "Step 3.3: Verify instance upgrade by starting instance and checking db2level."
log_master "  The instance $INSTANCE_NAME should now be associated with $NEW_DB2_PATH."
run_as_instance "db2start"
run_as_instance "db2level"
log_master "  Review output of db2level. It should show the NEW DB2 version."
pause_and_confirm "Instance $INSTANCE_NAME started and db2level shows new version?"

# --- Phase 4: Upgrading Databases ---
log_master "--- Phase 4: Upgrading Databases ---"
for db_name in "${DATABASE_NAMES[@]}"; do
    log_master "Step 4.1 for $db_name: Upgrade the database."
    log_master "  Command: db2 UPGRADE DATABASE $db_name"
    run_as_instance "db2 UPGRADE DATABASE $db_name" # Add USER ... USING ... if needed
    log_master "  Monitor db2diag.log for progress and errors during database upgrade."
    pause_and_confirm "UPGRADE DATABASE command for $db_name completed? Review logs."
done

# --- Phase 5: Post-Upgrade Tasks ---
log_master "--- Phase 5: Post-Upgrade Tasks ---"
log_master "Step 5.1: Run db2updv<version> (e.g., db2updv121) for each database."
DB2UPDV_CMD="${NEW_DB2_PATH}/bin/db2updv121" # Adjust version number if different
if [ ! -f "$DB2UPDV_CMD" ]; then
    log_master "  WARNING: $DB2UPDV_CMD not found. Skipping this step. Ensure it's run if applicable."
else
    for db_name in "${DATABASE_NAMES[@]}"; do
        log_master "  Running $DB2UPDV_CMD for $db_name..."
        run_as_instance "$DB2UPDV_CMD -d $db_name"
    done
fi
pause_and_confirm "db2updv<version> completed for all databases?"

log_master "Step 5.2: Rebind all packages."
for db_name in "${DATABASE_NAMES[@]}"; do
    log_master "  Rebinding packages for $db_name..."
    REBIND_LOG="${LOG_DIR}/rebind_${db_name}.log"
    run_as_instance "db2rbind $db_name -l $REBIND_LOG all"
    log_master "  Rebind log for $db_name: $REBIND_LOG. Check for errors."
done
pause_and_confirm "Rebind packages completed for all databases?"

log_master "Step 5.3: Review and update database/DBM configurations if needed."
log_master "  Compare with configurations saved in $CONFIG_BACKUP_DIR."
log_master "  Action: Manual review and `db2 update ...` commands if necessary."
pause_and_confirm "Configurations reviewed and updated?"

log_master "Step 5.4: Perform FULL DATABASE BACKUPS for all upgraded databases."
log_master "  Example for a database 'MYDB': su - $INSTANCE_NAME -c "db2 backup database MYDB to /your_post_upgrade_backup_location online""
pause_and_confirm "Post-upgrade backups completed?"

log_master "Step 5.5: Thoroughly test all applications."
log_master "  Action: Manual step."

log_master "--- DB2 In-Place Upgrade Helper Finished ---"
log_master "Review all logs in $LOG_DIR for details and any errors."
log_master "Remember to consult official IBM documentation throughout this process."

# Make the script executable after creation
# chmod +x db2_update/scripts/in_place_upgrade_helper.sh
