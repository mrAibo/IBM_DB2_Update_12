# Comparison of DB2 Upgrade Methods: 11.5 to 12.1

**Version:** 1.0
**Date:** 2024-06-18

## Introduction

When upgrading IBM DB2 from a previous version (e.g., 11.5) to a new major version (e.g., 12.1), administrators have a few general approaches. This document compares two common methods:

1.  **Method A: In-Place Upgrade:** This involves upgrading the existing DB2 instance software and then upgrading the databases directly using IBM-provided utilities like `db2iupgrade` and `UPGRADE DATABASE`.
2.  **Method B: Recreate Instance & Restore Databases:** This involves backing up databases from the old instance, dropping the old instance, creating a new instance with the new DB2 version's software, and then restoring the databases into the new instance.

Choosing the right method depends on factors like acceptable downtime, risk tolerance, desired instance configuration state post-upgrade, and available resources.

---

## Method A: In-Place Upgrade

This method directly upgrades the existing instance and its databases. The detailed steps for this method are covered in the [Comprehensive Guide: Upgrading IBM DB2 from Version 11.5 to Version 12.1](./DB2_Upgrade_11.5_to_12.1.md). A helper script, `scripts/in_place_upgrade_helper.sh`, is also available to guide through these steps.

### Pros:
*   **Configuration Retention:** Generally preserves most instance and database configuration settings, including DBM CFG, DB CFG, `db2set` registry variables, and cataloged node/DCS database entries. This can reduce post-upgrade reconfiguration effort.
*   **Potentially Faster:** If all prerequisites are met and `db2ckupgrade` reports no issues, the actual upgrade process (`db2iupgrade` and `UPGRADE DATABASE`) can be faster than a full backup and restore cycle, especially for very large databases.
*   **IBM Recommended Path:** This is often considered the standard and most direct upgrade path documented by IBM for version-to-version upgrades.
*   **Less Disk Space (Potentially):** May require less temporary disk space compared to needing space for full backups alongside the live database during the process (though `UPGRADE DATABASE` can still consume significant transaction log space).

### Cons:
*   **"Messier" Environment:** Carries over the entire history and nuances of the old instance. If the old instance had accumulated problematic settings or minor inconsistencies, these might persist.
*   **Rollback Complexity:** If the `db2iupgrade` or `UPGRADE DATABASE` commands fail midway, rollback can be more complex. While restoring from a pre-upgrade backup is the ultimate fallback, undoing a partially completed instance or database upgrade step itself can be challenging.
*   **`db2ckupgrade` is Critical:** The success heavily relies on a clean run of `db2ckupgrade`. Any unresolved issues flagged by this tool can lead to upgrade failures.
*   **Less Flexibility with OS/Storage Changes:** If the upgrade is part of a larger migration (e.g., new server, different storage layout), this method is less adaptable than Method B.

---

## Method B: Recreate Instance & Restore Databases

This method involves building a new, clean instance with the target DB2 version and then restoring the user databases into it. The script `scripts/recreate_restore_upgrade.sh` is an example implementation of this approach, offering options for either automated or manual execution of the backup and restore phases within its workflow.

### Pros:
*   **Clean Slate Instance:** Starts with a fresh DB2 instance using default configurations for the new version (unless explicitly scripted). This can eliminate old, potentially problematic or undocumented instance-level settings.
*   **Simpler Rollback (Conceptually):** If the new instance or restore process fails, rolling back often means simply reverting to the old (still intact, if not dropped yet) instance and its databases, or restoring the pre-upgrade backups to the old version instance. The old instance is not directly modified until explicitly dropped.
*   **OS/Storage Flexibility:** This method is more amenable if the upgrade coincides with a move to new hardware, OS upgrade, or storage reconfiguration, as the new instance is built independently.
*   **Verification of Backups:** The process inherently validates the restorability of your database backups.

### Cons:
*   **Configuration Migration:** All necessary DBM CFG parameters, `db2set` variables, and other instance-level configurations from the old instance must be manually identified, validated for the new version, and reapplied to the new instance. This can be error-prone if not carefully managed. The user-provided script for this method handles some, but a full audit is needed.
*   **Potentially Longer Downtime:** The complete cycle of backup, instance creation, and database restore can result in a longer overall downtime compared to a smooth in-place upgrade, especially for numerous or very large databases.
*   **Database Cataloging:** After restoring, databases need to be cataloged if they were accessed as remote databases by clients. Node and DCS directory information might need manual recreation.
*   **Not a True "Upgrade" of System Catalogs:** While restoring a database into a newer version makes it usable, the internal database catalog structures might not be as fully transformed as they would be with the `UPGRADE DATABASE` command. `db2updv<version>` (like `db2updv121`) helps, but `UPGRADE DATABASE` is specifically designed for version-to-version catalog evolution. This might have subtle implications for new features or optimizer behavior.

---

## Summary Comparison

| Feature                 | Method A: In-Place Upgrade                 | Method B: Recreate & Restore             |
|-------------------------|--------------------------------------------|------------------------------------------|
| **Primary Commands**    | `db2iupgrade`, `UPGRADE DATABASE`          | `db2idrop`, `db2icrt`, `RESTORE DATABASE`|
| **Instance State**      | Existing instance evolved                  | New, clean instance created              |
| **Config. Retention**   | High (automatic)                           | Low (manual reapplication needed)        |
| **Potential Downtime**  | Potentially shorter                        | Potentially longer                       |
| **Rollback Simplicity** | Can be complex if mid-step failure       | Generally simpler (revert to old env)    |
| **Disk Space (Op)**     | Moderate                                   | Higher (needs space for backups)         |
| **"Cleanliness"**       | Carries over old instance history          | Fresh start                               |
| **IBM Standard Path**   | Yes                                        | Alternative/Migration strategy           |
| **Prep. Criticality**   | `db2ckupgrade` is vital                    | Backup integrity is vital                |
| **Flexibility (OS/HW)** | Lower                                      | Higher                                   |

---

## Conclusion

*   **Method A (In-Place Upgrade)** is often preferred for straightforward version upgrades on existing hardware where minimizing downtime (if all goes well) and retaining configurations are key priorities. It requires meticulous pre-upgrade checks.
*   **Method B (Recreate Instance & Restore)** is a strong candidate when a "clean slate" is desired for the instance, when migrating to new hardware/OS, or if there are concerns about the stability/history of the old instance configuration. It demands careful planning for re-applying necessary configurations.

Both methods require thorough testing in a non-production environment before attempting on production systems. Always consult the latest IBM DB2 Knowledge Center documentation.
