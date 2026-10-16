CODE ?= code
PREFIX ?= $(HOME)/.local
EXTENSION_DIR := .editors/vscode
EXTENSION_ID := sole-lang.sole-language

.PHONY: all bootstrap test test-syntax install up down format

all: bootstrap

format: .build/sole
	find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -exec .build/sole format {} +

.build/sole: bootstrap.sh $(shell find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print) $(wildcard runtime/*.ll runtime/*.c)
	./bootstrap.sh

bootstrap:
	./bootstrap.sh

test: bootstrap
	sh compiler/tests/syntax.sh
	sh compiler/tests/run.sh
	sh compiler/tests/format.sh

test-syntax: .build/sole
	sh compiler/tests/syntax.sh

install:
	sh install.sh "$(PREFIX)"

up:
	@command -v node >/dev/null || { echo "Install Node.js 22 or newer first."; exit 1; }
	@node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or newer is required."); process.exit(1); }'
	@command -v npm >/dev/null || { echo "Install npm first."; exit 1; }
	@command -v "$(CODE)" >/dev/null || { echo "Install the VS Code CLI or set CODE to its executable."; exit 1; }
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
