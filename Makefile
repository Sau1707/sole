CODE ?= code
PREFIX ?= $(HOME)/.local
SOLE_VERSION ?= 0.0.4
SOLE_CC ?= cc
SOLE_COMPILER ?= $(PREFIX)/bin/sole
EXTENSION_DIR := .editors/vscode
EXTENSION_ID := sole-lang.sole-language

export SOLE_CC SOLE_COMPILER

.PHONY: all test test-suite install up down format check-compiler

all: install

format: check-compiler
	find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -exec "$(SOLE_COMPILER)" format {} +

check-compiler:
	@command -v "$(SOLE_COMPILER)" >/dev/null || { echo "Install the released compiler with make install first." >&2; exit 1; }

test: test-suite

test-suite: check-compiler
	sh compiler/tests/harness.sh
	sh compiler/tests/syntax.sh
	sh compiler/tests/types.sh
	sh compiler/tests/run.sh
	sh compiler/tests/format.sh
	sh compiler/tests/install.sh

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
