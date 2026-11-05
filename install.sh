#!/usr/bin/env bash
# install.sh — symlink linker into a PATH dir (default: ~/.local/bin)
set -euo pipefail

dest="${1:-$HOME/.local/bin}"
src="$(cd "$(dirname "$0")" && pwd)/linker"

if [ ! -f "$src" ]; then
  echo "error: linker script not found next to install.sh" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required but not on PATH" >&2
  exit 1
fi

mkdir -p "$dest"
chmod +x "$src"
ln -sfn "$src" "$dest/linker"

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "note: $dest is not on your PATH — add it:  export PATH=\"$dest:\$PATH\"" ;;
esac

echo "✓ installed linker → $dest/linker"
echo "  try: linker add github https://github.com/you --tags dev"
if [ "$(uname -s)" = "Darwin" ]; then
  echo "  macOS tip: if 'linker' isn't found, add to ~/.zshrc or ~/.bash_profile:"
  echo "             export PATH=\"$dest:\$PATH\""
fi
