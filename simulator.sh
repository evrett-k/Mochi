#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Mochi iOS"
CONFIG="Debug"
SDK="iphonesimulator"
OS_VERSION="18"
DEVICE_TYPE="iPhone"

for arg in "$@"; do
  case "$arg" in
    --iphoneos-15) OS_VERSION="15" ;;
    --iphoneos-16) OS_VERSION="16" ;;
    --iphoneos-17) OS_VERSION="17" ;;
    --iphoneos-18) OS_VERSION="18" ;;
    --iphoneos-26) OS_VERSION="26" ;;
    --iphone) DEVICE_TYPE="iPhone" ;;
    --ipad) DEVICE_TYPE="iPad" ;;
    --debug) CONFIG="Debug" ;;
    --release) CONFIG="Release" ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

echo "Project: $PROJECT_DIR"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIG"
echo "Target: $DEVICE_TYPE simulator (iOS $OS_VERSION)"

echo "Building ${SCHEME} (${CONFIG}) for ${SDK}..."
xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk $SDK \
  -UseModernBuildSystem=YES \
  clean build

APP_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/Mochi-*/Build/Products/${CONFIG}-iphonesimulator/Mochi.app 2>/dev/null | head -n1 || true)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Built app not found. Expected at ~/Library/Developer/Xcode/DerivedData/.../Build/Products/${CONFIG}-iphonesimulator/Mochi.app"
    exit 1
fi

APP_MIN_VERSION=$(xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
    -scheme "$SCHEME" \
    -showBuildSettings 2>/dev/null | \
    awk -F ' = ' '/^    IPHONEOS_DEPLOYMENT_TARGET = / { print $2; exit }')
if [ -z "$APP_MIN_VERSION" ]; then
        APP_MIN_VERSION="$OS_VERSION"
fi

DEVICE=$(xcrun simctl list devices available | /usr/bin/python3 -c '
import re
import sys

device_type = sys.argv[1]
requested = tuple(int(part) for part in sys.argv[2].split("."))
minimum = tuple(int(part) for part in sys.argv[3].split("."))

def parse_version(text):
    return tuple(int(part) for part in text.split("."))

sections = {}
current_version = None

for raw_line in sys.stdin:
    line = raw_line.rstrip("\n")
    header = re.match(r"^-- iOS ([0-9.]+) --$", line.strip())
    if header:
        current_version = parse_version(header.group(1))
        sections.setdefault(current_version, [])
        continue

    if current_version is None:
        continue

    if device_type not in line:
        continue

    matches = re.findall(r"[0-9A-Fa-f-]{36}", line)
    if matches:
        sections[current_version].append(matches[-1])

if not sections:
    sys.exit(0)

family_versions = sorted(version for version in sections if version[:1] == requested[:1])
chosen_version = family_versions[0] if family_versions else None

if chosen_version is None:
    eligible_versions = sorted(version for version in sections if version >= minimum)
    chosen_version = eligible_versions[0] if eligible_versions else None

if chosen_version is None:
    chosen_version = sorted(sections)[-1]

devices = sections.get(chosen_version, [])
if devices:
    print(devices[0])
' "$DEVICE_TYPE" "$OS_VERSION" "$APP_MIN_VERSION") || true

if [ -z "$DEVICE" ]; then
    echo "No available $DEVICE_TYPE simulator found for iOS $OS_VERSION."
    echo "Run 'xcrun simctl list devices available' to see what's installed."
    exit 2
fi

echo "Using simulator: $DEVICE"

echo "Booting simulator (if needed)..."
xcrun simctl boot "$DEVICE" || true
open -a Simulator --args -CurrentDeviceUDID "$DEVICE" || true

APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")
echo "Removing any existing install: $APP_BUNDLE_ID"
xcrun simctl terminate "$DEVICE" "$APP_BUNDLE_ID" || true
xcrun simctl uninstall "$DEVICE" "$APP_BUNDLE_ID" || true

echo "Installing app: $APP_PATH"
xcrun simctl install "$DEVICE" "$APP_PATH"

echo "Launching bundle: $APP_BUNDLE_ID"
LAUNCH_ARGS=()
if [ "$DEVICE_TYPE" = "iPad" ]; then
    LAUNCH_ARGS+=("--mochi-force-ipad-root")
fi

xcrun simctl launch "$DEVICE" "$APP_BUNDLE_ID" "${LAUNCH_ARGS[@]}"

echo "Done."