GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
CYAN   := \033[36m
NC     := \033[0m

BUILD_DIR         := build
BUILD_TYPE        ?= RelWithDebInfo
DEPLOYMENT_TARGET ?= 11.0
SKIA_BUILD        := Release

ARCH         := $(shell uname -m)
SKIA_TAG     := $(shell cat laf/misc/skia-tag.txt)
SKIA_DIR     := $(CURDIR)/.deps/skia-$(firstword $(subst -, ,$(SKIA_TAG)))
SKIA_LIB_DIR := $(SKIA_DIR)/out/$(SKIA_BUILD)-$(ARCH)
SKIA_LIB     := $(SKIA_LIB_DIR)/libskia.a
SKIA_URL      = $(shell bash laf/misc/skia-url.sh $(SKIA_BUILD))

SDK_PATH   := $(shell xcrun --show-sdk-path)
APP        := $(BUILD_DIR)/bin/Aseprite.app
EXECUTABLE := $(APP)/Contents/MacOS/aseprite
NINJA_FILE := $(BUILD_DIR)/build.ninja

CMAKE_FLAGS := \
	-G Ninja \
	-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
	-DCMAKE_OSX_ARCHITECTURES=$(ARCH) \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) \
	-DCMAKE_OSX_SYSROOT=$(SDK_PATH) \
	-DLAF_BACKEND=skia \
	-DSKIA_DIR=$(SKIA_DIR) \
	-DSKIA_LIBRARY_DIR=$(SKIA_LIB_DIR) \
	-DSKIA_LIBRARY=$(SKIA_LIB) \
	-DPNG_ARM_NEON:STRING=on \
	-DENABLE_TESTS=$(if $(TESTS),ON,OFF)

.DEFAULT_GOAL := help

.PHONY: help \
        deps submodules skia doctor \
        configure build rebuild run open debug test b r \
        clean distclean

help: ## Display this help screen
	@printf '$(CYAN)aseprite$(NC)\n\n'
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make $(GREEN)<target>$(NC)\n"} \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\n$(YELLOW)Order$(NC)\n'
	@printf '  new machine       $(GREEN)doctor$(NC) -> $(GREEN)deps$(NC) -> $(GREEN)run$(NC)\n'
	@printf '  day to day        $(GREEN)run$(NC) (rebuilds what changed, then launches)\n'
	@printf '  laf/skia bumped   $(GREEN)deps$(NC) -> $(GREEN)rebuild$(NC)\n'
	@printf '  build acting odd  $(GREEN)distclean$(NC) -> $(GREEN)build$(NC)\n'
	@printf '\n  Overrides: BUILD_TYPE=Debug|Release|$(GREEN)RelWithDebInfo$(NC)  DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET)  TESTS=1\n'
	@printf '  $(GREEN)test$(NC) reconfigures with tests $(RED)on$(NC) — run $(GREEN)configure$(NC) afterwards to drop them again.\n'

##@ Setup

deps: submodules skia ## Install cmake/ninja, init submodules, download prebuilt Skia
	@command -v cmake >/dev/null || brew install cmake
	@command -v ninja >/dev/null || brew install ninja
	@printf '$(GREEN)Dependencies ready$(NC) (Skia at %s)\n' "$(SKIA_DIR)"

submodules: ## Sync and update git submodules
	git submodule update --init --recursive

skia: $(SKIA_LIB) ## Download the prebuilt Skia that laf/misc/skia-tag.txt pins into .deps/

$(SKIA_LIB):
	@printf '$(CYAN)Downloading Skia$(NC) %s (%s-%s)\n' "$(SKIA_TAG)" "$(SKIA_BUILD)" "$(ARCH)"
	mkdir -p $(SKIA_DIR)
	curl -fL -o $(SKIA_DIR)/skia.zip $(SKIA_URL)
	unzip -q -o -d $(SKIA_DIR) $(SKIA_DIR)/skia.zip
	rm $(SKIA_DIR)/skia.zip

doctor: ## Sanity-check required tooling is installed
	@printf 'cmake:  ' ; cmake --version 2>/dev/null | head -1 || printf '$(RED)MISSING$(NC)\n'
	@printf 'ninja:  ' ; ninja --version 2>/dev/null || printf '$(RED)MISSING$(NC)\n'
	@printf 'curl:   ' ; curl --version  2>/dev/null | head -1 || printf '$(RED)MISSING$(NC)\n'
	@printf 'sdk:    ' ; xcrun --show-sdk-version 2>/dev/null || printf '$(RED)MISSING$(NC) (install Xcode)\n'
	@printf 'skia:   ' ; test -f $(SKIA_LIB) && printf '%s\n' "$(SKIA_TAG)" || printf '$(YELLOW)not downloaded$(NC) (make deps)\n'

##@ Build

$(NINJA_FILE): $(SKIA_LIB)
	cmake -S . -B $(BUILD_DIR) --fresh $(CMAKE_FLAGS)

configure: $(SKIA_LIB) ## (Re)configure the CMake build from scratch
	cmake -S . -B $(BUILD_DIR) --fresh $(CMAKE_FLAGS)

build: $(NINJA_FILE) ## Build aseprite (configures first if needed)
	cmake --build $(BUILD_DIR) --target aseprite

rebuild: configure build ## Reconfigure and build

test: ## Reconfigure with tests on, build everything and run ctest
	$(MAKE) configure TESTS=1
	cmake --build $(BUILD_DIR)
	cd $(BUILD_DIR) && ctest --output-on-failure

clean: ## Remove compiled objects (keeps configuration)
	@test -f $(NINJA_FILE) && cmake --build $(BUILD_DIR) --target clean || printf '$(YELLOW)Nothing to clean$(NC) (not configured)\n'

distclean: ## Remove the whole build directory
	rm -rf $(BUILD_DIR)

##@ Run

run: build ## Build and run with console output in the terminal
	./$(EXECUTABLE)

open: build ## Build and launch the .app bundle via Finder
	open $(APP)

debug: build ## Build and launch under lldb
	lldb -o run -- ./$(EXECUTABLE)

##@ Aliases

b: build ## build
r: run ## run
