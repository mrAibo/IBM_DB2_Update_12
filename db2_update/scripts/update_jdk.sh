#!/bin/bash

# == DB2 JDK Path Update Script ==

# This script updates the Java Development Kit (JDK) path used by DB2.
# This is typically required when you've installed a new JDK and want DB2
# to use it for Java-based routines, tools, or the DB2 Java environment itself.

# --- Configuration ---
# Specify the DB2 instance for which the DBM CFG will be updated.
INSTANCE_NAME="db2inst1" # Change if your instance name is different

# Specify the new JDK path.
# This path should point to the root directory of your JDK installation
# (e.g., /opt/ibm/java-x86_64-80/jre or /usr/java/jdk-11.0.12).
# The issue mentioned: /opt/ibm/db2/V12.1/java/jdk
# This path seems to be the default internal JDK for DB2.
# If you are updating to an *external* or different JDK, change this path accordingly.
NEW_JDK_PATH="/opt/ibm/db2/V12.1/java/jdk" # Default from issue, verify this is the intended new path.

# --- Script Logic ---
echo "Starting DB2 JDK Path update process..."
echo "Timestamp: $(date)"
echo ""

echo "Instance to update: $INSTANCE_NAME"
echo "New JDK Path to set: $NEW_JDK_PATH"
echo ""

# Validate if the NEW_JDK_PATH exists (basic check)
if [ ! -d "$NEW_JDK_PATH" ]; then
  echo "ERROR: The specified NEW_JDK_PATH '$NEW_JDK_PATH' does not seem to be a valid directory."
  echo "Please verify the path and try again."
  exit 1
fi

# Display current JDK_PATH (if set)
echo "Querying current JDK_PATH for instance '$INSTANCE_NAME'..."
su - $INSTANCE_NAME -c "db2 get dbm cfg" | grep "JDK_PATH"
echo ""

echo "Attempting to update DBM CFG for JDK_PATH..."
su - $INSTANCE_NAME -c "db2 update dbm cfg using JDK_PATH $NEW_JDK_PATH"
UPDATE_RC=$?

if [ $UPDATE_RC -eq 0 ]; then
  echo "DBM CFG update for JDK_PATH command executed. Return Code: $UPDATE_RC"
  echo "Successfully updated JDK_PATH for instance '$INSTANCE_NAME' to '$NEW_JDK_PATH'."
  echo ""
  echo "IMPORTANT: A DB2 instance restart (db2stop/db2start) is typically required for this change to take full effect."
  echo "You can restart the instance manually when appropriate:"
  echo "  su - $INSTANCE_NAME -c "db2stop""
  echo "  su - $INSTANCE_NAME -c "db2start""
else
  echo "ERROR: Failed to update JDK_PATH for instance '$INSTANCE_NAME'."
  echo "Return Code: $UPDATE_RC"
  echo "Please check the DB2 diagnostic log for more details."
  exit 1
fi

echo ""
echo "JDK Path update script finished."
echo "Timestamp: $(date)"
