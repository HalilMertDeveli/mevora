#!/bin/sh
# Copies the flavor-specific GoogleService-Info.plist into Runner.
FLAVOR="$1"
SRC="${PROJECT_DIR}/../flavors/${FLAVOR}/GoogleService-Info.plist"
DEST="${PROJECT_DIR}/GoogleService-Info.plist"

if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST"
fi
