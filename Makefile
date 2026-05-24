PROJECT = Mochi.xcodeproj
SCHEME = Mochi
CONFIG = Release
SDK = macosx
BUILD_DIR = build

.PHONY: all build-x86_64 build-arm64 build-universal clean

all: build-universal

build-x86_64:
	@echo "Building for x86_64..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -sdk $(SDK) -arch x86_64 BUILD_DIR=$(BUILD_DIR)/x86_64 clean build

build-arm64:
	@echo "Building for arm64..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -sdk $(SDK) -arch arm64 BUILD_DIR=$(BUILD_DIR)/arm64 clean build

build-universal: build-x86_64 build-arm64
	@echo "Builds available in $(BUILD_DIR)/x86_64 and $(BUILD_DIR)/arm64"

clean:
	rm -rf $(BUILD_DIR)
