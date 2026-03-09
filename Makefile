.PHONY: help build install clean run

APP_NAME = Watcher.app
BUILD_DIR = build/macos/Build/Products/Release
INSTALL_DIR = /Applications

.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

build: ## Build the macOS release app
	@echo "Building $(APP_NAME) for macOS..."
	flutter build macos --release

install: build ## Build and install to /Applications
	@echo "Installing $(APP_NAME) to $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)/$(APP_NAME)
	@cp -R $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/
	@echo "Installed successfully! You can now open $(APP_NAME) from your Applications folder."

run: ## Run the app in debug mode
	flutter run -d macos

clean: ## Clean the Flutter build cache
	flutter clean
