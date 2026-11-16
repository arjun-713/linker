# Linker panel design and review

Direction: **Liquid Glass** (Apple, macOS 26+) for the native panel, with a solid
`windowBackgroundColor` fallback carrying the same layout on macOS 13–25. Native
system typography is kept. The panel floats under the menu bar icon; Linker has
one job and no navigation destinations. There are no photographs, external fonts
or generated image assets.

The screen answers: **Which saved URL do I need to copy?** The result list is the
largest region, and every row performs that action. Linker’s face is the link
symbol, short aliases paired with URLs, the tag strip and the Return key hints.
The panel adds links in place (**⌘N** / + button) and edits and deletes them
too (**⌘E** / **⌘⌫** with **⌘Z** undo): every write uses the CLI’s exact
`links.json` schema and validation rules. Copying updates `copy_count` /
`last_copied`, feeding the **Recent** sort; only bulk edits stay with the CLI.

## Before and after

The before reference is a browser reconstruction of the original SwiftUI source,
not a screenshot from a Mac. The original translucent material and system font
cannot be reproduced exactly here.

| Property | Original source | Updated presentation |
| --- | --- | --- |
| Panel | 380 × 460 pt | 440 × 568 pt |
| Alias / URL text | 13 / 11 pt | 14 / 12 pt |
| Tags / shortcut text | 9 / 10 pt | 11 / 11 pt or larger |
| Search | Alias, URL, tags | Alias, URL, tags, notes; combines with a tag |
| File failure | Empty library | Distinct error with retry |
| Selection | Index changed without scrolling | Selected row scrolls into view |
| Clipboard failure | Always reported success | Success is checked; failure stays open |
| Result actions | Copy | Copy and open, with keyboard hints |

## Final visual critique

- **Hierarchy:** the alias is the primary line; the actual URL is below it. Header
  and search remain compact, so the list carries the screen’s question.
- **Frame:** 20 + 400 + 20 = 440 pt; rows use 12 + 416 + 12. Height is 64 header +
  44 search + 44 tags + 28 heading + 336 results + 52 footer = 568 pt. The partial
  last row is the scrollable continuation, with the full count above the list.
- **Colour:** no opaque greys. Text uses the system label hierarchy —
  `.primary`, `.secondary`, `.tertiary` — so contrast holds on glass over any
  wallpaper in either appearance. Selection is a translucent accent tint
  (18 %), chips and keycaps are 8 % foreground tints, hairlines are 15 %.
  Green appears only after a successful copy; red only for field errors.
  No tinted category icons or artificial metrics.
- **Consistency:** the result count comes from the rendered matches. The sample
  library has eight links; the dev filter has four. Tag plus query counts update
  together. Reopening clears both filters and selects the first link.
- **States:** zero is printed as `0 links`. Missing tags are omitted. Empty,
  no-result, invalid-file and clipboard-denied states have distinct recovery paths.
- **Marks:** tag labels name the actual tag; the selected row has one Return
  affordance, which becomes a check after copying. There are no charts or legends.
- **Narrow view:** the preview fits at 390 px without page overflow. Tag filters
  scroll within their own row; URLs and long tags truncate, with full fields in
  the row tooltip. The native app remains a fixed-width macOS utility.

Both appearances passed the final rendered inspector at **1440, 768 and 390 px
with zero failures**. The retained small-text warning reflects 11–12 pt metadata
and keyboard hints in a compact native utility; primary link labels are 14 pt.
The floating panel shadow is explicitly allowed (`--allow heavy-shadow`) because
this is an actual menu panel, corresponding to `NSPanel.hasShadow`, rather than
a resting content card. Source lint reports zero failures and zero warnings.

The Impeccable `cramped-padding` finding on the outer `linker-panel` shell is a
false positive: its header and footer backgrounds intentionally reach the frame,
while their text is inset by the child containers. Browser text bounds in both
themes at 1440, 768 and 390 px measured 20 px of top clearance and 18.47 px of
bottom clearance. A `cramped-padding` value exception is scoped to
`macos/preview/index.html` in `.impeccable/config.json`; other rules and files
remain active. No padding or layout change was needed.

The browser checks exercised 13 scenarios: native-size geometry and counts;
fuzzy/note search; combined filters; keyboard scrolling and reopen; actual
clipboard copy and dismissal; Command-Return; empty/error recovery; JSON import
and long/literal fields; corrupt-file recovery; both themes at three widths;
reduced motion; browser errors; and clipboard denial. CLI tests (20) and preview
search/schema tests (4) also passed.

## Verification limits and sample data

The native app compiles and runs on macOS (built with the 27.2 SDK, deployment
target 13.0; Liquid Glass APIs are `#available(macOS 26.0, *)`-gated). The
add-link form was exercised end-to-end with real keystrokes against a
`LINKER_STORE` file and the result read back by the CLI, including duplicate
rejection and preservation of CLI-written records. Contrast on glass over
arbitrary wallpapers was reasoned from the system label hierarchy, not
screenshot-measured. The browser preview predates the Liquid Glass styling and
the add-link form; it recreates the solid list-panel look only.

The eight aliases in `preview/sample-links.json` are demonstration data. A chosen
JSON file is read locally and never written or uploaded. Reload uses that file’s
browser snapshot; choose the file again after editing it on disk.
