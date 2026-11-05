# Linker panel design and review

Direction: **True-black flat**, seed **1139091961**, with a corresponding light
palette. Native system typography is kept. The dealt dashboard shell was adapted
to the existing floating menu panel because Linker has one job and no navigation
destinations. There are no photographs, external fonts or generated image assets.

The screen answers: **Which saved URL do I need to copy?** The result list is the
largest region, and every row performs that action. Linker’s face is the link
symbol, short aliases paired with URLs, the tag strip and the Return key hints.
The panel stays read-only; editing and copy statistics belong to the CLI.

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
- **Colour:** neutral surfaces, neutral selection, and green only after a
  successful copy. No tinted category icons or artificial metrics.
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

Swift syntax parsing passed on Linux. macOS SDK typechecking, app launch,
menu bar positioning, global hotkeys, login registration and native pasteboard
integration remain unverified. The browser preview is an interactive recreation,
not native SwiftUI running on Linux. Browser font substitution and rendering
can differ from a Mac.

The eight aliases in `preview/sample-links.json` are demonstration data. A chosen
JSON file is read locally and never written or uploaded. Reload uses that file’s
browser snapshot; choose the file again after editing it on disk.
