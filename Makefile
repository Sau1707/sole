.PHONY: install up down format

format:
	find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -exec "$(HOME)/.local/bin/sole" format {} +

install:
	SOLE_VERSION=0.0.5 sh install.sh "$(HOME)/.local"

up:
	@command -v code >/dev/null || { echo "Install the VS Code CLI first."; exit 1; }
	SOLE_VERSION=0.0.5 sh install.sh "$(HOME)/.local"
	npm --prefix .editors/vscode ci
	npm --prefix .editors/vscode test
	npm --prefix .editors/vscode run package
	code --install-extension .editors/vscode/sole-language.vsix --force

down:
	@command -v code >/dev/null || { echo "Install the VS Code CLI first."; exit 1; }
	@extensions=$$(code --list-extensions) || exit $$?; \
	if printf '%s\n' "$$extensions" | grep -Fxiq sole-lang.sole-language; then \
		code --uninstall-extension sole-lang.sole-language || exit $$?; \
	fi
	rm -rf -- .editors/vscode/node_modules
	rm -f -- .editors/vscode/*.vsix
