#!/bin/sh
# Copies the flavor-specific GoogleService-Info.plist into Runner.
# SRCROOT is the ios/ directory. FLUTTER_FLAVOR is set by Flutter when
# running with --flavor. Unflavored builds default to development to match
# lib/main.dart and the committed Runner plist.
set -e
FLAVOR="${1:-${FLUTTER_FLAVOR:-development}}"
SRC="${SRCROOT}/flavors/${FLAVOR}/GoogleService-Info.plist"
DEST="${SRCROOT}/Runner/GoogleService-Info.plist"

if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST"
else
  echo "warning: GoogleService-Info.plist not found for flavor '${FLAVOR}' at ${SRC}" >&2
fi
