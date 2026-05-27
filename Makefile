PROJECT = Mochi.xcodeproj
SCHEME = Mochi
CONFIG = Release
SDK = macosx
BUILD_DIR = build
ARCHS = darwin-amd64 darwin-arm64 iphoneos-arm64 iphoneos-arm64e
MACOS_ARCHS = darwin-amd64 darwin-arm64
IOS_ARCHS = iphoneos-arm64 iphoneos-arm64e

.PHONY: all build-darwin-amd64 build-darwin-arm64 build-universal clean

all: build-universal

build-darwin-amd64:
	@echo "Building darwin ver for amd64..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -sdk $(SDK) -arch darwin-amd64 BUILD_DIR=$(BUILD_DIR)/x86_64 clean build

build-arm64:
	@echo "Building darwin ver for arm64..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -sdk $(SDK) -arch darwin-arm64 BUILD_DIR=$(BUILD_DIR)/arm64 clean build

build-universal: build-darwin-amd64 build-darwin-arm64
	@echo "Builds available in $(BUILD_DIR)/darwin-amd64 and $(BUILD_DIR)/darwin-arm64"

clean:
	rm -rf $(BUILD_DIR)
