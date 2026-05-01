---
name: cinefuse-apple-ui-polish
description: Cinefuse Apple (SwiftUI) UI polish — readable controls in sheets and narrow widths, panel button patterns, and avoiding truncated inspector actions.
---

# Cinefuse Apple UI polish

Use when editing `packages/cinefuse-apple-core` SwiftUI (especially sheets, inspectors, `SectionCard`, split panels, or toolbars with several text buttons).

## Principles

1. **Never rely on a single horizontal row of long-label buttons** on iPhone or sheet-presented panels. `ViewThatFits(in: .horizontal)` can still choose a variant that truncates titles (“Generate Di…”).
2. **Sheets and `editorMobileInspectorSheet == true`**: stack primary actions **vertically**, one button per row, **full width**, using `PanelSecondaryButtonStyle` (see `AppComponents.swift`).
3. **Inline / desktop**: use `LazyVGrid` with `GridItem(.adaptive(minimum: ~168))` so buttons wrap into multiple columns instead of squeezing one row.
4. **Sliders**: avoid fixed narrow widths (e.g. 120pt) when the layout is compact—give the track `frame(maxWidth: .infinity)`. Label **Lane volume** / **Master volume** explicitly; show percentage with monospaced digits for stability.
5. **Lane / list rows**: when `editorMobileInspectorSheet` is true, prefer a **stacked** layout (header row + full-width slider) over one crowded `HStack`.
6. **Tokens**: keep spacing, typography, and colors on `CinefuseTokens`; match existing button styles unless introducing a deliberate panel-specific style (document it next to the style struct).

## Reference implementation

- **Audio Lanes** toolbar: `ProjectDetailScreen.audioLanesGenerationToolbar` / `audioLanesPanelActionButton` in `RootView.swift`.
- **Panel buttons**: `PanelSecondaryButtonStyle` in `AppComponents.swift`.
- **Lane cards**: `AudioLaneView` compact vs inline layouts keyed off `EnvironmentValues.editorMobileInspectorSheet`.

## Copy voice

Follow `AGENTS.md` Cinefuse voice for any new user-visible strings: direct, no fluff, no emoji in chrome.
