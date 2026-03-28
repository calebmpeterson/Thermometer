.PHONY: all clean run kill

APP_NAME = Thermometer
BUILD_DIR = build
MODULE_CACHE_DIR = $(BUILD_DIR)/ModuleCache
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
EXECUTABLE = $(MACOS_DIR)/$(APP_NAME)
SOURCES = $(wildcard src/*.swift)
INFO_PLIST = src/Info.plist

all: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES) $(INFO_PLIST)
	@echo "Building $(APP_NAME).app..."
	@mkdir -p $(MACOS_DIR) $(MODULE_CACHE_DIR)
	@swiftc $(SOURCES) -parse-as-library -module-cache-path $(MODULE_CACHE_DIR) -framework IOKit -o $(EXECUTABLE)
	@echo "Copying Info.plist..."
	@cp $(INFO_PLIST) $(CONTENTS_DIR)/Info.plist
	@echo "Signing app bundle..."
	@codesign --force --deep -s - $(APP_BUNDLE)
	@echo "Build complete: $(APP_BUNDLE)"

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

run: $(EXECUTABLE)
	@echo "Launching $(APP_NAME).app..."
	@open $(APP_BUNDLE)

kill:
	@killall $(APP_NAME) 2>/dev/null || true
	@echo "Killed any running $(APP_NAME) instances."
