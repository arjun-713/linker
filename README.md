# linker

Store your links (github, linkedin, portfolio, resume, …) under short aliases and
copy them to the clipboard from **anywhere in the terminal**.

```console
$ linker add github https://github.com/arjun --tags dev,identity -n "main profile"
✓ added github → https://github.com/arjun
  tags dev, identity · note main profile

$ linker cp github          # from any directory
✓ github · https://github.com/arjun

$ linker cp git             # unambiguous prefix works too
```

Single-file python 3 tool, standard library only — no venv, no pip, no app.

## Install

```console
$ ./install.sh              # symlinks into ~/.local/bin (pass another dir to override)
```

Copy-paste equivalent: drop the `linker` file anywhere on your `PATH`.

## Usage

| command | does |
|---|---|
| `linker add <alias> <url> [-t a,b] [-n note]` | save a link |
| `linker cp <alias>` | copy to clipboard (`--stdout` to just print, `--json` for `{alias,url,copied_via}`) |
| `linker ls [query] [--tag t] [--sort alpha\|recent\|created]` | list; `recent` shows a LAST column |
| `linker search <query>` | fuzzy search over alias / url / tags / note |
| `linker show <alias>` | full card (`--json`, or `--plain` for url-only) |
| `linker edit <alias> [--url …] [--tags a,b] [--add-tags t] [--note …] [--alias new]` | change fields; `--tags` replaces, `--add-tags` appends |
| `linker rm <alias> [-y]` | remove (confirms unless `-y`; non-interactive shells must pass `-y`) |
| `linker open <alias>` | open in browser |
| `linker tags` | tag counts |
| `linker export [file]` | json to stdout or a file |
| `linker import file [--dry-run]` | merge/upsert; keeps local copy stats |
| `linker completions bash\|zsh` | shell completion (see below) |

Every list command accepts `--json` (machine) and `--plain` (tab-separated, no styling).
Exit codes: `0` ok · `1` error · `2` no/ambiguous alias · `3` clipboard failure.

## Storage

`~/.config/linker/links.json` — one JSON file, atomic writes, 0600. If it becomes
unreadable it gets quarantined as `links.json.broken-<timestamp>` and the tool
continues with an empty store.

## Environment

| variable | meaning |
|---|---|
| `LINKER_STORE` | alt store path (per-project stores become trivial) |
| `LINKER_CLIPBOARD` | pin one clipboard tool; it receives the url as its last argument |
| `LINKER_OPEN` | browser command for `open` (default `xdg-open`) |
| `NO_COLOR` / `--plain` | disable styling (also automatic when piped) |
| `LINKER_FORCE_COLOR` | force styling, e.g. for demos in captured output |

## Clipboard chain

`$LINKER_CLIPBOARD` → `pbcopy` (macOS) / `wl-copy` (Wayland) → `xclip` → `xsel` → OSC52
escape (tty only). On a failure the command still prints the url to stdout and exits `3`,
so scripts can recover.

## macOS

The CLI is macOS-ready: `pbcopy` for the clipboard and `open` for `linker open`,
auto-detected (`python3` needs the Xcode Command Line Tools). There is also a native
menu bar app with a compact, keyboard-first panel, light and dark appearances, tag
filters, a global **⌘⇧L** hotkey, and the same `~/.config/linker/links.json` store:

```console
$ ./macos/build.sh --install    # needs macOS 13+ and Xcode CLT; see macos/README.md
```

**No Mac available?** View and try the interface on Linux, Windows, or macOS:

```console
$ python3 macos/preview.py --open    # → http://127.0.0.1:4178
```

The interactive browser preview includes search, tag filters, keyboard navigation,
clipboard copying, light/dark controls, and empty/error examples. You can load a
Linker JSON export locally. It needs only Python 3 and a browser; no npm or build
step. This is a recreation of the native UI; it does not execute SwiftUI or test
macOS integration. See [the macOS guide](macos/README.md) for screenshots and details.

## Completions

```console
$ eval "$(linker completions bash)"     # .bashrc   (zsh: eval; compdef runs inside the script)
```

Completes commands, flags, and your saved aliases (fetched live via `linker --completion-words`).

## Tests

```console
$ python3 -m unittest discover -s tests
```

## Uninstall

Remove the symlink from `~/.local/bin` and `rm -rf ~/.config/linker`.
