#!/bin/sh
# Writes the ABIs the app and the verifier use to abi/*.json.
set -e
cd "$(dirname "$0")"
mkdir -p abi
for c in CheckInLauncherFactory CheckInLauncher StreakVaultFactory StreakVault IPortal; do
  forge inspect "$c" abi --json > "abi/$c.json"
done
ls -l abi
