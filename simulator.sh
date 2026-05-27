#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA_PATH="$PROJECT_DIR/BuildDerivedData"
SCHEME="Mochi iOS"
CONFIG="Debug"
SDK="iphonesimulator"
OS_VERSION="18"
DEVICE_TYPE="iPhone"
TARGET_PLATFORM="iOS"

for arg in "$@"; do
  case "$arg" in
    --15) OS_VERSION="15" ;;
    --16) OS_VERSION="16" ;;
    --17) OS_VERSION="17" ;;
    --18) OS_VERSION="18" ;;
    --26) OS_VERSION="26" ;;
    --iphone) DEVICE_TYPE="iPhone" ;;
    --ipad) DEVICE_TYPE="iPad" ;;
    --watch) 
        DEVICE_TYPE="Watch"
        SDK="watchsimulator"
        TARGET_PLATFORM="watchOS"
        ;;    
    --tv)
        DEVICE_TYPE="Apple TV"
        SDK="appletvsimulator"
        TARGET_PLATFORM="tvOS"
        ;;
    --debug) CONFIG="Debug" ;;
    --release) CONFIG="Release" ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

echo "Project: $PROJECT_DIR"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIG"
echo "Target: $DEVICE_TYPE simulator (platform=$TARGET_PLATFORM version=$OS_VERSION)"

echo "Building ${SCHEME} (${CONFIG}) for ${SDK}..."
# If user requested a special platform (watchOS or tvOS), try to auto-detect a scheme name
if [ "$TARGET_PLATFORM" = "watchOS" ] || [ "$TARGET_PLATFORM" = "tvOS" ]; then
    SCHEMES_LIST=$(xcodebuild -list -project "$PROJECT_DIR/Mochi.xcodeproj" 2>/dev/null | awk '/Schemes:/{flag=1; next} flag && NF==0{exit} flag{print}')
    POSSIBLE=""
    if [ "$TARGET_PLATFORM" = "watchOS" ]; then
        # Prefer a scheme with "watch" in the name (case-insensitive)
        POSSIBLE=$(printf "%s\n" "$SCHEMES_LIST" | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -i watchos | head -n1 || true)
        if [ -z "$POSSIBLE" ]; then
            POSSIBLE=$(printf "%s\n" "$SCHEMES_LIST" | grep -i watch | grep -vi watchkit | head -n1 || true)
        fi
    else
        # tvOS: prefer a scheme with "tvos" or "tv" in the name
        POSSIBLE=$(printf "%s\n" "$SCHEMES_LIST" | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -i tvos | head -n1 || true)
        if [ -z "$POSSIBLE" ]; then
            POSSIBLE=$(printf "%s\n" "$SCHEMES_LIST" | grep -i tv | grep -vi "tv" | head -n1 || true)
        fi
        if [ -z "$POSSIBLE" ]; then
            POSSIBLE=$(printf "%s\n" "$SCHEMES_LIST" | grep -i appletv | head -n1 || true)
        fi
    fi
    if [ -n "$POSSIBLE" ]; then
        SCHEME="$POSSIBLE"
        echo "Auto-selected $TARGET_PLATFORM scheme: $SCHEME"
    else
        echo "No explicit $TARGET_PLATFORM scheme found. Add a target/scheme or pass a platform-capable scheme."
        exit 1
    fi
fi

xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk $SDK \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -UseModernBuildSystem=YES \
    clean build

PRODUCT_SUFFIX="iphonesimulator"
if [ "$TARGET_PLATFORM" = "watchOS" ]; then
    PRODUCT_SUFFIX="watchsimulator"
elif [ "$TARGET_PLATFORM" = "tvOS" ]; then
    PRODUCT_SUFFIX="appletvsimulator"
fi

APP_PATH=$(ls -d "$DERIVED_DATA_PATH"/Build/Products/${CONFIG}-${PRODUCT_SUFFIX}/*.app 2>/dev/null | head -n1 || true)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Built app not found. Expected at $DERIVED_DATA_PATH/Build/Products/${CONFIG}-${PRODUCT_SUFFIX}/"
    exit 1
fi

if [ "$TARGET_PLATFORM" = "watchOS" ]; then
    APP_MIN_VERSION=$(xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
            -scheme "$SCHEME" \
            -showBuildSettings 2>/dev/null | \
            awk -F ' = ' '/^    WATCHOS_DEPLOYMENT_TARGET = / { print $2; exit }')
elif [ "$TARGET_PLATFORM" = "tvOS" ]; then
    APP_MIN_VERSION=$(xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
            -scheme "$SCHEME" \
            -showBuildSettings 2>/dev/null | \
            awk -F ' = ' '/^    TVOS_DEPLOYMENT_TARGET = / { print $2; exit }')
else
    APP_MIN_VERSION=$(xcodebuild -project "$PROJECT_DIR/Mochi.xcodeproj" \
            -scheme "$SCHEME" \
            -showBuildSettings 2>/dev/null | \
            awk -F ' = ' '/^    IPHONEOS_DEPLOYMENT_TARGET = / { print $2; exit }')
fi
if [ -z "$APP_MIN_VERSION" ]; then
        APP_MIN_VERSION="$OS_VERSION"
fi

PLATFORM_HEADER="iOS"
if [ "$TARGET_PLATFORM" = "watchOS" ]; then
    PLATFORM_HEADER="watchOS"
elif [ "$TARGET_PLATFORM" = "tvOS" ]; then
    PLATFORM_HEADER="tvOS"
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
    header = re.match(r"^-- " + re.escape(sys.argv[4]) + r" ([0-9.]+) --$", line.strip())
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
' "$DEVICE_TYPE" "$OS_VERSION" "$APP_MIN_VERSION" "$PLATFORM_HEADER") || true

if [ -z "$DEVICE" ]; then
    echo "No available $DEVICE_TYPE simulator found for $PLATFORM_HEADER $OS_VERSION."
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

if [ "$TARGET_PLATFORM" = "watchOS" ]; then
    EXT_APPEX=$(ls -d "$APP_PATH"/PlugIns/*.appex 2>/dev/null | head -n1 || true)
    if [ -n "$EXT_APPEX" ] && [ -d "$EXT_APPEX" ]; then
        PREVIEW="$EXT_APPEX/__preview.dylib"
        if [ -f "$PREVIEW" ]; then
            echo "Removing preview injection: $PREVIEW"
            rm -f "$PREVIEW" || true
            echo "Re-signing extension and app (ad-hoc) to update CodeResources..."
            codesign --force --sign - --preserve-metadata=identifier,entitlements "$EXT_APPEX" || true
            codesign --force --sign - --preserve-metadata=identifier,entitlements "$APP_PATH" || true
        fi
    fi
fi
	xcrun simctl install "$DEVICE" "$APP_PATH"

echo "Launching bundle: $APP_BUNDLE_ID"
LAUNCH_ARGS=()
if [ "$DEVICE_TYPE" = "iPad" ]; then
    LAUNCH_ARGS+=("--mochi-force-ipad-root")
fi
if [ ${#LAUNCH_ARGS[@]} -gt 0 ]; then
    xcrun simctl launch "$DEVICE" "$APP_BUNDLE_ID" "${LAUNCH_ARGS[@]}"
else
    xcrun simctl launch "$DEVICE" "$APP_BUNDLE_ID"
fi

echo "Done."