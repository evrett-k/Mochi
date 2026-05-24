#!/bin/bash
set -e

ROOTHELPER=$(ls -1 "$HOME/Library/Developer/Xcode/DerivedData"/*/Build/Products/Debug/RootHelper 2>/dev/null | head -n1)
APP_RES=$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/*/Build/Products/Debug/Mochi.app 2>/dev/null | head -n1)/Contents/Resources

if [ -z "$ROOTHELPER" ] || [ ! -f "$ROOTHELPER" ]; then
  echo "Built RootHelper not found in DerivedData. Build RootHelper first." >&2
  exit 1
fi

if [ -z "$APP_RES" ] || [ ! -d "$APP_RES" ]; then
  echo "Mochi.app Resources folder not found in DerivedData. Build Mochi first." >&2
  exit 1
fi

echo "Copying $ROOTHELPER -> $APP_RES/RootHelper"
cp "$ROOTHELPER" "$APP_RES/RootHelper"
chmod 0755 "$APP_RES/RootHelper"
echo "Done. Relaunch Mochi from Xcode to pick up bundled helper."

exit 0
