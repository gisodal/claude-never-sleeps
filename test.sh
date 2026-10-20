#!/bin/bash
# Runs every test file; no sudo needed and nothing outside temporary directories changes.
cd "$(dirname "$0")" || exit 1
status=0
for file in tests/*.test.sh; do /bin/bash "$file" || status=1; done
exit $status
