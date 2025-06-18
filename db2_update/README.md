# DB2 Administration Scripts and Guides

This directory contains a collection of scripts and instructions to assist with common IBM DB2 database administration tasks.

**IMPORTANT**:
*   Review and customize all scripts before execution to match your specific environment, instance names, database names, paths, and versions.
*   Most scripts require execution as the DB2 instance owner or a user with equivalent privileges.
*   Always back up your data and configurations before performing significant operations like restores or FixPak installations.
*   Make scripts executable using `chmod +x <script_name.sh>`.

## Table of Contents

1.  [Scripts Overview](#scripts-overview)
2.  [Backup Script (`scripts/backup_db2.sh`)](#backup-script-scriptsbackup_db2sh)
3.  [Restore Script (`scripts/restore_db2.sh`)](#restore-script-scriptsrestore_db2sh)
4.  [Monitoring Backup/Restore Progress](#monitoring-backuprestore-progress)
5.  [FixPak Installation Guide (`scripts/install_fixpak.sh`)](#fixpak-installation-guide-scriptsinstall_fixpaksh)
6.  [JDK Update Script (`scripts/update_jdk.sh`)](#jdk-update-script-scriptsupdate_jdksh)
7.  [WebSphere JDBC Update](#websphere-jdbc-update)
8.  [DB2 Version Upgrade (11.5 to 12.1)](#db2-version-upgrade-115-to-121)
    *   [Upgrade Methods Comparison](#db2-version-upgrade-methods-comparison)
    *   [Method A: In-Place Upgrade Guide & Helper Script](#method-a-in-place-upgrade-guide--helper-script)
    *   [Method B: Recreate Instance & Restore Upgrade Script](#method-b-recreate-instance--restore-upgrade-script)

## Scripts Overview

All executable scripts are located in the `scripts/` subdirectory.

*   `backup_db2.sh`: Performs an online backup of a specified DB2 database.
*   `restore_db2.sh`: Restores a DB2 database from a backup. **Caution: This script can be destructive as it may remove existing data.**
*   `install_fixpak.sh`: A placeholder script and guide for installing DB2 FixPaks. **Requires significant user customization.**
*   `update_jdk.sh`: Updates the JDK path configuration for a DB2 instance.

## Backup Script (`scripts/backup_db2.sh`)

This script automates the online backup of a DB2 database.

### Configuration
Open `scripts/backup_db2.sh` and modify the following variables at the beginning of the script:
*   `INSTANCE`: Your DB2 instance name (e.g., `db2inst1`).
*   `DB_NAME`: The name of the database to back up (e.g., `LARGEDB`).
*   `BACKUP_DIR`: Comma-separated list of directories where backup images will be stored (e.g., `/backup/fast1,/backup/fast2`). Using multiple paths to different physical devices can improve I/O.
*   `UTIL_HEAP`: The `UTIL_HEAP_SZ` DBM CFG parameter value (in 4KB pages). The script default is `400000`. The original issue description suggested this should result in ~4GB, but 400000 * 4KB = 1.56GB. For ~4GB, use `1048576`. Adjust as needed for your system's memory.
*   `NUM_BUFFERS`: Number of buffers for the backup process (e.g., `16`).
*   `PARALLELISM_LEVEL`: Parallelism level for the backup (e.g., `8`, often related to CPU cores).

### DB2 Restart Note
The script, as per the original requirement, updates `UTIL_HEAP_SZ` and then performs a `db2stop force` followed by `db2start`. This restart ensures the `UTIL_HEAP_SZ` change is applied if it's not dynamically updateable in your DB2 version. However, forcing an instance stop can be disruptive.
*   **Verify**: Check if `UTIL_HEAP_SZ` is dynamic for your DB2 version/FixPak. If it is, you might be able to remove the `db2stop force` and `db2start` commands, or apply the configuration change with `db2 attach to $INSTANCE; db2 update dbm cfg using UTIL_HEAP_SZ $UTIL_HEAP immediate; db2 detach`.
*   If a restart is necessary, schedule backups during maintenance windows if possible.

### Backup Parameters
*   `with X buffers`: Allocates X buffers for the backup.
*   `buffer Y`: Sets the size of each buffer to Y (in 4KB pages). The script uses `256` pages, which equals 1MB per buffer (1048576 bytes / 4096 bytes/page = 256 pages).
*   `parallelism Z`: Specifies the number of concurrent operations.
*   `compress`: Compresses the backup image to save disk space. This adds CPU overhead.
*   `include logs`: Includes necessary log files in the backup for consistency.
*   `without prompting`: Suppresses interactive prompts.

### How to Run
1.  Configure the variables in the script.
2.  Ensure the script is executable: `chmod +x scripts/backup_db2.sh`
3.  Run the script: `./scripts/backup_db2.sh`

## Restore Script (`scripts/restore_db2.sh`)

This script automates the restoration of a DB2 database from a backup.

### !!! WARNING: DATA LOSS RISK !!!
This script is configured to **ERASE** data from specified database and log directories (`DB2_DATA_DIR`, `DB2_LOGS_DIR`) before performing the restore. This is a destructive operation.
*   **TRIPLE-CHECK** the `DB2_DATA_DIR` and `DB2_LOGS_DIR` variables in the script.
*   Ensure you are restoring to the correct environment.
*   The script includes a 10-second delay before data removal for a final chance to cancel.

### Configuration
Open `scripts/restore_db2.sh` and modify these variables:
*   `INSTANCE`: Your DB2 instance name.
*   `DB_NAME`: The name of the database to restore.
*   `BACKUP_DIR`: Directory where the backup images are located.
*   `DB2_DATA_DIR`: Path to the DB2 data directory (e.g., `/db2data`). **Contents will be wiped.**
*   `DB2_LOGS_DIR`: Path to the DB2 log directory (e.g., `/db2logs`). **Contents will be wiped.**
*   `NUM_BUFFERS`: Number of buffers (e.g., `24`, typically 1.5x backup buffers).
*   `BUFFER_SIZE_PAGES`: Size of each buffer in 4KB pages (e.g., `256` for 1MB buffers).
*   `PARALLELISM_LEVEL`: Parallelism for restore (e.g., `12`, typically higher than backup).

### Post-Restore `db2updv121`
The script includes a command `db2updv121 -d $DB_NAME`. This utility is specific to DB2 Version 12.1 and is used to update database metadata after certain operations like restores from older versions or FixPak applications.
*   If you are not on V12.1 or this command is not relevant to your restore scenario, you may comment it out or replace it with the appropriate `db2upd<version>` command if needed.

### How to Run
1.  Configure all variables carefully, especially `DB2_DATA_DIR` and `DB2_LOGS_DIR`.
2.  Ensure the script is executable: `chmod +x scripts/restore_db2.sh`
3.  Run the script: `./scripts/restore_db2.sh` (Be prepared for the warning and data deletion).

## Monitoring Backup/Restore Progress

The issue description provided an example for monitoring:
```bash
watch -n 5 "grep 'Total bytes' $LOG_FILE | tail -n $MAX_PARALLEL"
```
To use this:
*   `$LOG_FILE`: This variable needs to be defined. It should point to the DB2 diagnostic log (`db2diag.log`) or a specific log file where backup/restore progress messages are written. The exact message ("Total bytes") might vary by DB2 version or configuration. You might need to inspect `db2diag.log` during a backup/restore to find a suitable pattern to grep for.
*   `$MAX_PARALLEL`: This should roughly correspond to the parallelism level set in your backup/restore script to see progress for each parallel task.
*   Alternatively, you can use DB2 tools like `db2pd -db <dbname> -backup` or `db2pd -db <dbname> -restore` (if available and appropriate for your version) or monitor `db2 list utilities show detail`.

## FixPak Installation Guide (`scripts/install_fixpak.sh`)

The `scripts/install_fixpak.sh` script is **not a runnable script** as-is. It's a template and guide.

### Purpose
DB2 FixPaks are critical for bug fixes, security patches, and new features. The installation process requires careful planning and execution.

### Before You Begin
1.  **Download**: Get the correct FixPak for your DB2 version and operating system from IBM Support.
2.  **Read Documentation**: Thoroughly read the FixPak's own README or installation guide provided by IBM.
3.  **Backup**: Perform a full backup of ALL databases managed by the DB2 instance being updated. Also, consider backing up DB2 configuration.
4.  **Extract**: Extract the FixPak archive to a temporary location (e.g., `/tmp/FP_files`).

### Using the Script
1.  Open `scripts/install_fixpak.sh`. It contains detailed comments.
2.  **Customize the `installFixPack` command**:
    *   The core command is `./installFixPack`.
    *   `-b <DB2_INSTALL_PATH>`: **Required**. Path to your DB2 installation (e.g., `/opt/ibm/db2/V12.1`).
    *   `-p <FIXPAK_EXTRACT_PATH>`: Path where you extracted the FixPak files.
    *   Use other parameters like `-L` (license), `-n` (non-interactive), `-l <logfile>` as needed.
3.  The script provides examples and lists common parameters.

### Post-Installation
1.  Verify the new DB2 level: `db2level`.
2.  Restart instances if they were stopped.
3.  Check installation logs.
4.  Run `db2upd<version> -d <dbname>` for each database if required by the FixPak notes (e.g., `db2updv121 -d MYDB`).
5.  Test applications.

## JDK Update Script (`scripts/update_jdk.sh`)

This script updates the `JDK_PATH` database manager configuration parameter for a DB2 instance. This tells DB2 which Java Development Kit to use.

### Configuration
Open `scripts/update_jdk.sh` and modify:
*   `INSTANCE_NAME`: The DB2 instance to update.
*   `NEW_JDK_PATH`: The full path to the root directory of the new JDK installation.
    *   The script defaults to `/opt/ibm/db2/V12.1/java/jdk` (DB2's internal JDK).
    *   If you're pointing to an external JDK (e.g., system Java or another IBM JDK), update this path. Ensure DB2 has permissions to access this path.

### How to Run
1.  Configure the variables.
2.  Make executable: `chmod +x scripts/update_jdk.sh`
3.  Run: `./scripts/update_jdk.sh`
4.  **Restart Required**: After the script successfully updates the configuration, you must stop and start the DB2 instance for the change to take full effect:
    ```bash
    su - <INSTANCE_NAME> -c "db2stop"
    su - <INSTANCE_NAME> -c "db2start"
    ```

## DB2 Version Upgrade (11.5 to 12.1)

Upgrading a DB2 instance from a major version like 11.5 to 12.1 is a significant operation that requires careful planning. There are two primary methods to achieve this, each with its own set of procedures, benefits, and drawbacks.

### DB2 Version Upgrade Methods Comparison
Before choosing an upgrade path, it's crucial to understand the differences between the available methods. We provide a detailed comparison document that outlines the pros and cons of each approach:
*   **Read the Comparison Guide:** [DB2 Upgrade Methods Comparison](./DB2_Upgrade_Methods_Comparison.md)

### Method A: In-Place Upgrade Guide & Helper Script
For administrators looking to perform a major version upgrade of their DB2 environment from version 11.5 to 12.1, a detailed step-by-step guide is available. This guide covers critical phases including pre-upgrade preparations, software installation, instance upgrade, database upgrade, and post-upgrade tasks.

*   **Read the full guide here:** [Comprehensive Guide: Upgrading IBM DB2 from Version 11.5 to 12.1](./DB2_Upgrade_11.5_to_12.1.md)

**Note:** Major version upgrades are complex and should be thoroughly tested in a non-production environment first. Always refer to the official IBM DB2 Knowledge Center for the most current and detailed instructions specific to your environment.

To assist with the step-by-step execution of the in-place upgrade, a helper script is provided. This script is not fully automated but guides you through the necessary commands and checks.
*   **Helper Script:** `scripts/in_place_upgrade_helper.sh`
*   **Usage:** Review and configure the script variables, then execute it, following the prompts and performing manual verifications as required. It's designed to be run alongside the detailed guide.

### Method B: Recreate Instance & Restore Upgrade Script
This method involves creating a fresh DB2 instance with the new version software and then restoring your databases from backups taken from the old instance. This approach can be preferable for a "clean slate" or when migrating hardware/OS.

A script is provided to automate many steps of this process:
*   **Script:** `scripts/recreate_restore_upgrade.sh`
*   **Functionality:** This script manages dropping the old DB2 instance, creating a new instance with the new DB2 version, and applying post-restore configurations. It can *optionally* handle the database backup (from the old instance) and restore (to the new instance) steps automatically. By default, automated backup/restore are disabled, requiring manual intervention for these critical data operations.
*   **Caution:** This script is destructive as it involves dropping the existing instance. Ensure you have full, verified backups and understand the script's operations by reviewing its content and the [Upgrade Methods Comparison](./DB2_Upgrade_Methods_Comparison.md) document. TEST THOROUGHLY in a non-production environment.
*   **Backup and Restore Flexibility:**
    *   The script includes two boolean variables to control data handling:
        *   `PERFORM_AUTOMATED_BACKUP` (default: `false`): If set to `true`, the script will attempt to back up databases from the old instance.
        *   `PERFORM_AUTOMATED_RESTORE` (default: `false`): If set to `true`, the script will attempt to restore databases into the new instance.
    *   **Default Manual Mode:** With defaults set to `false`, the script will prompt you to:
        1.  Manually back up your databases from the old instance before the old instance is dropped. You can use the `backup_db2.sh` script or your own methods. Ensure backups are placed in the directory specified by the `BACKUP_DIR` variable in `recreate_restore_upgrade.sh`.
        2.  Manually restore your databases into the newly created instance. You can use the `restore_db2.sh` script or your own methods, using backups from the `BACKUP_DIR`.
    *   The script will continue with instance management (drop/create) and post-restore configurations (like `db2updv121`, `NEWLOGPATH` updates, `db2rbind`) regardless of these settings, assuming the databases are made available in the new instance.

*   **Configuration:** You MUST configure variables at the beginning of the script to match your environment (paths, instance names, `PERFORM_AUTOMATED_BACKUP`, `PERFORM_AUTOMATED_RESTORE`, etc.).

## WebSphere JDBC Update

The issue description mentions: "Websphere JDBC Update: „Resources > JDBC > JDBC Provider“ #if possible".

Automating WebSphere Application Server (WAS) configuration changes like JDBC provider updates typically requires using WebSphere's administrative scripting tools, such as `wsadmin` with Jython or Jacl. This is beyond the scope of simple shell scripts.

**Manual Steps for WebSphere (General Guidance):**

1.  **Access the WebSphere Admin Console**: Open a web browser and navigate to your WAS admin console URL (e.g., `http://yourserver:9060/ibm/console`).
2.  **Navigate to JDBC Providers**:
    *   In the console, look for a path similar to: `Resources > JDBC > JDBC Providers`. The exact navigation might vary slightly based on your WAS version.
3.  **Select the Provider**: Choose the JDBC provider that your applications use to connect to DB2 (e.g., "DB2 Universal JDBC Driver Provider").
4.  **Update Class Path**:
    *   You'll typically find a "Class path" field. This field contains paths to the JDBC driver JAR files (e.g., `db2jcc4.jar`, `db2jcc_license_cu.jar`).
    *   If you've updated DB2 or moved your DB2 client/driver installation, you may need to update these paths to point to the new location of the JAR files.
    *   Ensure the paths are correct and the WebSphere server has read access to them.
5.  **Save and Synchronize**:
    *   Save the changes to the master configuration.
    *   If in a networked deployment (ND) environment, ensure the changes are synchronized to all nodes.
6.  **Restart Servers**: Restart the application servers that use this JDBC provider for the changes to take effect.

**Note**: If you frequently update DB2 and need to update WebSphere JDBC paths, consider investing time in learning `wsadmin` scripting for automation.
