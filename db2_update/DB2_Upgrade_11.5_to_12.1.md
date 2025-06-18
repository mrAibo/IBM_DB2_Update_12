# Comprehensive Guide: Upgrading IBM DB2 from Version 11.5 to Version 12.1

**Version:** 1.0
**Date:** 2024-06-18

## 1. Introduction

This guide provides a comprehensive overview and step-by-step considerations for upgrading an IBM DB2 environment from version 11.5 to version 12.1. A major version upgrade is a significant undertaking and requires careful planning, execution, and verification.

**Disclaimer:** This guide is for informational purposes. Always refer to the official IBM DB2 Knowledge Center for your specific DB2 edition, FixPak level, and operating system for the most accurate and detailed instructions. Perform thorough testing in a non-production environment before attempting an upgrade in production.

### Key Stages of Upgrade:
1.  **Pre-Upgrade Tasks:** Preparing your current environment and databases.
2.  **Installing DB2 Version 12.1 Software:** Setting up the new DB2 binaries.
3.  **Upgrading DB2 Instances:** Migrating your existing instances to the new version.
4.  **Upgrading Databases:** Migrating the actual databases to the new version.
5.  **Post-Upgrade Tasks:** Verification, optimization, and final steps.

---

## 2. Phase 1: Pre-Upgrade Tasks

Thorough preparation is crucial for a smooth upgrade.

### 2.1. System Requirements for DB2 12.1
*   **Operating System:** Verify that your OS version is supported by DB2 12.1. Refer to IBM's system requirements documentation.
*   **Memory & Disk Space:** Ensure sufficient free memory and disk space for the DB2 12.1 installation, instance upgrade, and database upgrade (which can temporarily require more space).
*   **Software Prerequisites:** Check for any required libraries, compilers, or OS patches for DB2 12.1.

### 2.2. Full System Backup
*   **Database Backups:** Perform full, offline (if possible) backups of ALL databases managed by the DB2 11.5 instance(s) you intend to upgrade.
    *   You can use the `backup_db2.sh` script provided in the `scripts/` directory as a template. Ensure it's configured for your 11.5 environment.
    *   Example: `su - db2inst1 -c "./scripts/backup_db2.sh"`
    *   Verify backup completion and integrity.
*   **Operating System & Application Backups:** Consider full system backups or backups of critical application components.

### 2.3. Run `db2ckupgrade` Utility
The `db2ckupgrade` command is essential. It checks if your databases are ready for an upgrade to the new version.
*   **Obtain `db2ckupgrade`:** This utility is included with the DB2 Version 12.1 installation media. You do not need to install v12.1 yet; you can typically extract it from the installation image.
*   **Execution:**
    ```bash
    # As instance owner of the 11.5 instance
    su - <your_11.5_instance_owner>
    # Path to db2ckupgrade from v12.1 media
    /path_to_v12.1_media/server/db2ckupgrade <database_name> -l /tmp/db2ckupgrade_<database_name>.log -u <admin_user> -p <password>
    ```
*   **Review Logs:** Carefully examine the log file (e.g., `/tmp/db2ckupgrade_<database_name>.log`) for any errors or warnings.
*   **Resolve Issues:** Address ALL issues reported by `db2ckupgrade` before proceeding. Common issues might include outdated table definitions, invalid objects, or features that need manual migration.

### 2.4. Save DB2 Configuration
Capture the current configuration of your DB2 environment.
*   **Database Manager (DBM) Configuration:**
    ```bash
    su - <your_11.5_instance_owner> -c "db2 GET DBM CFG > /path_to_config_backup/dbm_cfg_11.5.txt"
    ```
*   **Database Configuration (for each database):**
    ```bash
    su - <your_11.5_instance_owner> -c "db2 CONNECT TO <database_name>; db2 GET DB CFG FOR <database_name> SHOW DETAIL > /path_to_config_backup/db_cfg_<database_name>_11.5.txt; db2 CONNECT RESET"
    ```
*   **`db2look` Output (for each database):** This utility generates DDL and statistics.
    ```bash
    su - <your_11.5_instance_owner> -c "db2look -d <database_name> -e -l -x -o /path_to_config_backup/db2look_<database_name>_11.5.sql"
    ```
*   **Registry Variables:**
    ```bash
    su - <your_11.5_instance_owner> -c "db2set -all > /path_to_config_backup/db2set_11.5.txt"
    ```
*   **Instance and System Information:** Note down OS version, DB2 FixPak level, disk layout, etc.

### 2.5. Check for DPF (Database Partitioning Feature)
*   If your DB2 11.5 environment uses DPF, the upgrade process is more complex and requires specific DPF upgrade procedures. This guide primarily focuses on non-DPF environments. Consult IBM documentation if you use DPF.

### 2.6. Final Checks
*   Ensure all applications are disconnected or quiesced.
*   No outstanding transactions or utilities running on the databases.
*   Sufficient downtime window approved for the upgrade.

---

## 3. Phase 2: Installing DB2 Version 12.1 Software

### 3.1. Obtain DB2 12.1 Software
*   Download the appropriate DB2 Version 12.1 edition (e.g., Standard, Advanced, Enterprise Server Edition) and FixPak level from IBM Passport Advantage or Fix Central.

### 3.2. Installation Process
*   It's common practice to install the new DB2 version in a separate directory from the old version. This allows for easier rollback if needed.
*   **Example Installation Path:**
    *   DB2 11.5 might be in: `/opt/ibm/db2/V11.5`
    *   Install DB2 12.1 to: `/opt/ibm/db2/V12.1`
*   **Run Installer:**
    *   Extract the installation files.
    *   Use `db2_install` (for non-interactive) or `db2setup` (for GUI).
    ```bash
    # Example using db2_install (as root)
    cd /path_to_v12.1_extracted_media/server
    ./db2_install -b /opt/ibm/db2/V12.1 -p SERVER -L EN -n
    ```
    Consult the `db2_install` documentation for specific product codes (`-p`).

### 3.3. Verification of New Installation
*   **`db2ls`:** (as root) List all DB2 installations on the server. Verify V12.1 is listed.
    ```bash
    /opt/ibm/db2/V12.1/install/db2ls -q -b /opt/ibm/db2/V12.1
    ```
*   **`db2level`:** (from new path) Check the version of the newly installed software.
    ```bash
    /opt/ibm/db2/V12.1/bin/db2level
    ```

---

## 4. Phase 3: Upgrading DB2 Instances

This phase upgrades your existing DB2 11.5 instance(s) to use the new DB2 12.1 software.

### 4.1. Stop the DB2 11.5 Instance
*   Ensure all applications are disconnected.
*   Stop the instance cleanly:
    ```bash
    su - <your_11.5_instance_owner>
    db2 force application all
    db2 terminate
    db2stop force # 'force' if necessary, prefer clean stop
    # db2admin stop # If DAS is used and needs upgrade
    ```

### 4.2. Upgrade the Instance using `db2iupgrade`
*   This command must be run as **root** from the DB2 Version 12.1 installation path.
    ```bash
    # As root
    /opt/ibm/db2/V12.1/instance/db2iupgrade [options] <instance_name_11.5>
    ```
    *   Example: `/opt/ibm/db2/V12.1/instance/db2iupgrade db2inst1`
    *   If you use a fenced user, you might need the `-u <fenced_user>` option.
*   The `db2iupgrade` command updates the instance configuration to point to the new DB2 software version.

### 4.3. Verify Instance Upgrade
*   **Start the Upgraded Instance:**
    ```bash
    su - <instance_owner> # Instance owner should be the same
    db2start
    ```
*   **Check `db2level`:**
    ```bash
    db2level
    ```
    This should now show DB2 Version 12.1.
*   Check DBM CFG: `db2 GET DBM CFG`. Some parameters might have new defaults or ranges.

---

## 5. Phase 4: Upgrading Databases

Once the instance is upgraded and running on DB2 12.1, you need to upgrade each database.

### 5.1. Connect to Each Database
*   Databases from the 11.5 instance will be cataloged but are in an "upgrade pending" state.
    ```bash
    su - <instance_owner>
    db2 connect to <database_name>
    ```
    You might receive SQL1499W (SQLCODE for upgrade pending) on connection, which is expected.

### 5.2. Run `UPGRADE DATABASE` Command
*   This command performs the actual metadata and structural changes for the database.
    ```bash
    db2 UPGRADE DATABASE <database_name> [USER <user> USING <password>]
    ```
    *   The user specified needs SYSADM, DBADM, or equivalent authority.
*   This step can take a significant amount of time depending on database size and complexity.

### 5.3. Monitor Upgrade Progress
*   Check the `db2diag.log` for progress and any errors.
*   You can list utilities: `db2 list utilities show detail`.

### 5.4. Resolve Issues During Database Upgrade
*   If the `UPGRADE DATABASE` command fails, check `db2diag.log` for detailed error messages.
*   Common issues could be related to tablespace states, invalid objects that `db2ckupgrade` didn't catch, or resource limitations.
*   Address the issues and attempt the `UPGRADE DATABASE` command again.

---

## 6. Phase 5: Post-Upgrade Tasks

After successfully upgrading the instance(s) and database(s).

### 6.1. Run `db2updv121` (if applicable)
*   The `db2updv121` command (located in `/opt/ibm/db2/V12.1/bin/`) updates database objects to the current FixPak level of V12.1. It's good practice to run this after a version upgrade and after applying new FixPaks.
    ```bash
    su - <instance_owner>
    db2updv121 -d <database_name>
    ```

### 6.2. Rebind Packages
*   Rebind all packages to take advantage of new optimizer features and ensure compatibility.
    ```bash
    su - <instance_owner>
    db2rbind <database_name> -l /tmp/db2rbind_<database_name>.log all
    ```
*   Check the log file for any errors.

### 6.3. Update Database Configuration (Optional)
*   Review the database configuration (`db2 GET DB CFG FOR <database_name>`). New parameters or functionalities might be available in DB2 12.1.
*   Adjust configurations based on performance testing and new features you wish to utilize.

### 6.4. Full Post-Upgrade Backup
*   Perform a full backup of each upgraded database using the new DB2 12.1 environment.
    *   Use the `backup_db2.sh` script (ensure it's now using the V12.1 paths/environment if necessary, though the script itself is instance-dependent).

### 6.5. Verify Application Connectivity and Functionality
*   Thoroughly test all applications that connect to the upgraded databases.
*   Check for any performance regressions or unexpected behavior.

### 6.6. Clean Up Old DB2 11.5 Installation (Optional)
*   Once you are confident that the DB2 12.1 environment is stable and you no longer need to roll back, you can plan to uninstall the old DB2 11.5 software.
    ```bash
    # As root, from the 11.5 installation path
    /opt/ibm/db2/V11.5/install/db2_deinstall -a
    ```
    **Caution:** Ensure you have no intention of rolling back before doing this.

---

## 7. Rollback Strategy Considerations

A rollback typically means reverting to the state before the upgrade attempt.
*   **Instance Rollback:** If `db2iupgrade` fails, you might be able to run `db2iurevert` (consult IBM docs). If not, you would typically uninstall the failed V12.1 instance attempt and restore the V11.5 instance configuration if it was altered, or rely on OS-level backups.
*   **Database Rollback:** The primary method is to restore from the full backups taken during the pre-upgrade phase (Phase 1).
    1.  Uninstall/remove the V12.1 instance or ensure it's stopped.
    2.  Reinstall or ensure the V11.5 instance is functional.
    3.  Restore the V11.5 databases using the V11.5 instance from the pre-upgrade backups.
*   **Thorough Backups are Key:** A successful rollback heavily depends on the quality and completeness of your pre-upgrade backups.

---

This guide provides a structured approach to upgrading DB2. Always consult the official IBM documentation and tailor the process to your specific environment. Good luck!
