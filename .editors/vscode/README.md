# Sole for Visual Studio Code

Syntax coloring for `.sole` files, using your current editor theme. Includes
variables, fields, functions, classes, structs, type annotations, built-in types and functions,
imports, control flow, operators, numbers, strings, escapes, and comments.

Shared syntax uses VS Code's Python TextMate scopes so themes can reuse their
Python colors. Sole's explicit built-in types use Python's built-in type colors.
Python language-server semantic coloring and Python-only editor settings do not
apply to Sole.

Also provides `#` comment toggling, bracket/quote completion, indentation-based
folding, and four-space indentation. No language server or compiler is required.
Diagnostics, completion, formatting, and debugging are not included.

## Try it

Open this directory (`.editors/vscode`) in VS Code and press **F5**. In the
Extension Development Host, open a `.sole` file from the repository's `compiler/`
directory. You can also select **Sole** from the language mode menu.

## Install locally

Requires Node.js 22 or newer, npm, Make, and the VS Code `code` CLI.
From the repository root:

```sh
make up
make down
```

`make up` installs local build dependencies, runs tests, packages the extension,
and installs it in VS Code. `make down` uninstalls the extension and removes its
local `node_modules` and generated VSIX files; it leaves system tools untouched.
Set `CODE` for another VS Code executable, for example `make up CODE=code-insiders`.

To build and install manually:

```sh
cd .editors/vscode
npm ci
npm test
npm run package
code --install-extension sole-language.vsix
```

Alternatively, use **Extensions: Install from VSIX...** in VS Code and select
the generated file. This extension is not published to the Marketplace; the
manifest's publisher is a placeholder for local packaging.
