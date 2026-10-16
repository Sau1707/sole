CODE ?= code
PREFIX ?= $(HOME)/.local
SOLE_VERSION ?= 0.0.3
SOLE_CC ?= cc
SOLE_SEED ?= 0
EXTENSION_DIR := .editors/vscode
EXTENSION_ID := sole-lang.sole-language

export SOLE_CC SOLE_LLVM_LIB SOLE_BOOTSTRAP SOLE_SEED

.PHONY: all bootstrap test test-suite test-syntax install up down format

all: bootstrap

format: .build/sole
	find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -exec .build/sole format {} +

.build/sole: Makefile $(shell find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print) $(wildcard lib/runtime/*.ll lib/runtime/*.c) bootstrap/sole bootstrap/SHA256SUMS
	@set -eu; \
	mkdir -p .build; \
	cc=$${SOLE_CC:-cc}; \
	llvm_library=$${SOLE_LLVM_LIB:-}; \
	if [ -z "$$llvm_library" ]; then \
		for candidate in LLVM-22 LLVM-21 LLVM-20 LLVM-19 LLVM-18 LLVM; do \
			found=$$("$$cc" -print-file-name="lib$$candidate.so"); \
			if [ "$$found" != "lib$$candidate.so" ]; then \
				llvm_library=$$candidate; \
				break; \
			fi; \
		done; \
	fi; \
	if [ -z "$$llvm_library" ]; then \
		echo "Install a shared LLVM library (e.g. libllvm21), or set SOLE_LLVM_LIB to its linker name." >&2; \
		exit 1; \
	fi; \
	if [ -n "$${SOLE_BOOTSTRAP:-}" ]; then \
		seed=$$SOLE_BOOTSTRAP; \
	elif [ -x .build/sole ] && [ "$$SOLE_SEED" != 1 ]; then \
		seed=.build/sole; \
	else \
		if [ "$$(uname -s)" != Linux ] || [ "$$(uname -m)" != x86_64 ]; then \
			echo "The bundled seed requires Linux x86-64. Set SOLE_BOOTSTRAP to a compatible Sole compiler." >&2; \
			exit 1; \
		fi; \
		sha256sum -c bootstrap/SHA256SUMS; \
		seed=bootstrap/sole; \
	fi; \
	export SOLE_HOME="$$PWD" SOLE_LIB="$$PWD/lib"; \
	echo "Bootstrapping with $$seed (native Sole)."; \
	seed_home=$$(mktemp -d "$$PWD/.build/seed-home-XXXXXX"); \
	trap 'rm -rf -- "$$seed_home"' EXIT HUP INT TERM; \
	ln -s "$$PWD/lib" "$$seed_home/lib"; \
	ln -s "$$PWD/lib/runtime" "$$seed_home/runtime"; \
	SOLE_HOME="$$seed_home" "$$seed" build compiler/main.sole --link "$$llvm_library" -o .build/sole-stage1; \
	.build/sole-stage1 build compiler/main.sole --link "$$llvm_library" -o .build/sole-stage2; \
	.build/sole-stage2 build compiler/main.sole --link "$$llvm_library" -o .build/sole-stage3; \
	cmp .build/sole-stage2 .build/sole-stage3; \
	install -m 755 .build/sole-stage3 .build/sole; \
	sha256sum .build/sole-stage2 .build/sole-stage3 > .build/bootstrap-proof.txt; \
	find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print | LC_ALL=C sort | while IFS= read -r source; do \
		sha256sum "$$source"; \
	done >> .build/bootstrap-proof.txt; \
	sha256sum lib/runtime/*.ll lib/runtime/system.c >> .build/bootstrap-proof.txt; \
	rm -- .build/sole-stage1; \
	echo "Verified: stage 2 and stage 3 are byte-for-byte identical. Compiler: .build/sole"

bootstrap:
	$(MAKE) --no-print-directory -B .build/sole

test: bootstrap
	$(MAKE) test-suite

test-suite:
	sh compiler/tests/syntax.sh
	sh compiler/tests/types.sh
	sh compiler/tests/run.sh
	sh compiler/tests/format.sh
	sh compiler/tests/install.sh

test-syntax: .build/sole
	sh compiler/tests/syntax.sh

install:
	SOLE_VERSION="$(SOLE_VERSION)" sh install.sh "$(PREFIX)"

up:
	@command -v node >/dev/null || { echo "Install Node.js 22 or newer first."; exit 1; }
	@node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or newer is required."); process.exit(1); }'
	@command -v npm >/dev/null || { echo "Install npm first."; exit 1; }
	@command -v "$(CODE)" >/dev/null || { echo "Install the VS Code CLI or set CODE to its executable."; exit 1; }
	SOLE_VERSION="$(SOLE_VERSION)" sh install.sh "$(PREFIX)"
	npm --prefix "$(EXTENSION_DIR)" ci
	npm --prefix "$(EXTENSION_DIR)" test
	npm --prefix "$(EXTENSION_DIR)" run package
	"$(CODE)" --install-extension "$(EXTENSION_DIR)/sole-language.vsix" --force

down:
	@command -v "$(CODE)" >/dev/null || { echo "Install the VS Code CLI or set CODE to its executable."; exit 1; }
	@extensions=$$("$(CODE)" --list-extensions) || exit $$?; \
	if printf '%s\n' "$$extensions" | grep -Fxiq "$(EXTENSION_ID)"; then \
		"$(CODE)" --uninstall-extension "$(EXTENSION_ID)" || exit $$?; \
	fi
	rm -rf -- "$(EXTENSION_DIR)/node_modules"
	rm -f -- "$(EXTENSION_DIR)/"*.vsix
