# Linker for macOS

A small menu bar app for the links you reach for every day. Click the link icon or
press **⌘⇧L**, find an alias, and press Return to copy its URL. The panel has a
readable two-line list, tag filters, and light and dark appearances that follow
your Mac’s settings. On macOS 26 and newer the panel is drawn in Apple’s
**Liquid Glass** style; on macOS 13–25 it falls back to a solid panel with the
same layout.

You can **add links right in the panel** — click the **+** button or press
**⌘N**, fill in an alias, URL, tags and an optional note, and it is saved to the
same store the CLI uses (same schema, same validation, atomic 0600 writes).
Edits and removals stay in the terminal.

It reads the **same store as the CLI**: `~/.config/linker/links.json`, or the path
in `LINKER_STORE` when that environment variable is passed to the app.

## See it without a Mac

From the project root:

```sh
python3 macos/preview.py --open
```

Open **http://127.0.0.1:4178**. Use `--port 4180` if that port is occupied. The
preview needs Python 3 and a modern browser, with no dependencies to install.
Stop the server with Ctrl+C.

The browser preview mirrors the native panel’s 440 × 568 pt layout, palette,
labels and fuzzy ranking. It predates the native app’s Liquid Glass styling and
add-link form, so it shows the solid list-panel look only. On narrow browser
windows it fits the available width.
Use the sun/moon controls to compare appearances and the state selector to see an
empty library, an unsuccessful search or a file error. Search, tag filtering,
arrow navigation, clipboard copying and opening URLs all work. On Linux/Windows,
Ctrl can substitute for Command within the page; some browser shortcuts may take
precedence. Clipboard access requires the localhost URL and browser permission.

**Load links.json** accepts a CLI export or store file. It reads the chosen file
inside your browser, without uploading it or changing it. The reload button uses
that snapshot; load the file again to see later edits. **Reset preview** restores
the eight sample links in [`preview/sample-links.json`](preview/sample-links.json):
apple-docs, figma, github, linear, linkedin, localhost, notion and swift. These are
demonstration data, including the GitHub alias from the CLI README.

These screenshots come from the browser preview. Native system typography,
menu bar placement, the global hotkey, login registration and pasteboard behavior
still require a Mac to verify. The native application cannot be built or run on
Linux or Windows.

| Dark appearance | Light appearance |
| --- | --- |
| ![Dark Linker preview](preview/screenshots/linker-dark.png) | ![Light Linker preview](preview/screenshots/linker-light.png) |

## Build and install the native app

Requirements: macOS 13 (Ventura) or newer and Xcode Command Line Tools
(`xcode-select --install`). Python 3 is used by the companion CLI.

```sh
# From the project root:
./macos/build.sh                 # → macos/build/Linker.app
./macos/build.sh --install       # → /Applications/Linker.app, then launches it
```

The build compiles `LinkerApp.swift` (store, actions, AppKit lifecycle and hotkey)
and `LinkerViews.swift` (SwiftUI presentation, including the Liquid Glass
styling and the add-link form) and targets macOS 13 explicitly. Liquid Glass
APIs are gated behind `#available(macOS 26.0, *)`, so the same binary runs on
older systems with the solid fallback.

After launching, right-click the menu bar icon for **Add Link…**, **Launch at
Login**, **Open links.json**, and **Quit Linker**. Launch at Login requires the
app to live in `/Applications`.

## Controls

| Input | Action |
| --- | --- |
| Menu bar icon or **⌘⇧L** | Show/hide the panel |
| **+** button or **⌘N** | Open the add-link form |
| Type | Fuzzy search alias, URL, tags and notes |
| Tag button | Combine a tag filter with the current search |
| **A–Z / Recent** button or **⌘S** | Toggle between alphabetical and recently-copied order |
| ↑ / ↓ or hover | Select a link; keyboard selection scrolls into view |
| Return, click a row, or Copy | Copy the selected URL, confirm, then hide |
| **⌘Return** or Open | Open the selected link in your browser |
| **⌘E** | Edit the selected link in the panel |
| **⌘⌫** | Delete the selected link (**⌘Z** or **Undo** puts it back) |
| Right-click a row | Copy, open, edit or delete that link |
| **⌘R** or reload icon | Reread the store |
| **⌘F** | Focus search |
| Escape / click outside | Close the add form, then hide the panel |

Right-clicking the menu bar icon also lists your first links as one-click
**Copy …** items, without opening the panel.

In the add form: Return advances from alias → URL, and Return in any field after
the URL saves. The alias checks format and duplicates while you type; a URL on
the pasteboard when the form opens pre-fills the URL field. A bare domain such
as `example.com/foo` gets `https://` added automatically; `git@host:user/repo.git`
becomes an HTTPS URL, like the CLI.

Copying from the panel updates the link's `copy_count` and `last_copied` in the
store, which feeds the **Recent** sort and the `N×` marker shown on each row.

An unreadable store shows a retry action. A missing store offers **Add your
first link**. A search with no results offers **Clear filters**. Copy failures
keep the panel open so you can retry.

## Validation

```sh
python3 -m unittest discover -s tests   # CLI regressions
node --test tests/test_preview.mjs     # preview ranking / schema checks (optional Node 18+)
```

The preview was checked in local Chrome at 1440, 768 and 390 px in both
appearances, including local JSON import, clipboard success/denial, keyboard
scrolling, opening links, and empty/error recovery. The native build compiles
and runs on macOS; the add-link form was exercised end-to-end against a
`LINKER_STORE` file and read back by the CLI.

Presentation uses the system font, simple outline symbols and neutral surfaces.
Implementation references: Apple’s [ScrollViewReader documentation](https://developer.apple.com/documentation/swiftui/scrollviewreader)
and [pasteboard API](https://developer.apple.com/documentation/appkit/nspasteboard/setstring(_:fortype:)).

## Troubleshooting

- **Build errors:** keep the `swiftc` output for diagnosis. Syntax checks on Linux
  do not verify macOS types or SDK availability.
- **Hotkey does nothing:** another app may have claimed ⌘⇧L. Change
  `registerHotKey()` in `LinkerApp.swift` and rebuild.
- **A different store:** a Finder-launched app does not inherit a terminal’s
  environment. Run its executable with `LINKER_STORE` set to use an alternate path.
- **Panel placement:** the panel uses the status icon’s screen and clamps its
  origin to that display’s visible area.
- **Uninstall:** quit Linker, then remove `/Applications/Linker.app`.
