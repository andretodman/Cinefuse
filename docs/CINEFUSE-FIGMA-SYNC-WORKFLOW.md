# Cinefuse ↔ Figma sync workflow

Run after UI changes in `packages/cinefuse-apple-core` (and thin hosts `apps/mac`, `apps/apple-host`).

**Target file:** `https://www.figma.com/design/0yJngv61Wo8z2vcxkeuCL5/`  
**File key:** `0yJngv61Wo8z2vcxkeuCL5`

## Steps

1. **Diff code** — Identify touched SwiftUI surfaces (`RootView.swift`, `AppComponents.swift`, `DesignTokens.swift`, `EditorMobileLayout.swift`, `HelpCenterView.swift`, etc.).
2. **Classify**
   - *Add:* New `struct` screens, sheets, or major panels.
   - *Update:* Changed layout, copy, tokens, or sheet triggers.
   - *Deprecate:* Removed or unreachable flows → move frames to `00-Archive` (create if needed); do not delete unrelated Figma nodes.
3. **Components first** — Update `99-Components` (`DS / *`) before screen frames so instances stay consistent.
4. **Screens** — Update `01-iPhone`, `02-iPad`, `03-Mac` frames named `Feature / Screen / State`.
5. **Prototypes** — Adjust `reactions` on primary navigation hotspots if flow changed.
6. **Changelog** — Fill template below, grouped by platform.

## Changelog template (copy per sync)

```markdown
## Figma sync changelog — <date> — <commit or branch>

### iPhone
- Added: …
- Updated: …
- Archived: …
- Components: …

### iPad
- Added: …
- Updated: …
- Archived: …
- Components: …

### Mac
- Added: …
- Updated: …
- Archived: …
- Components: …

### Notes / ambiguous
- …
```

## References

- Screen inventory: [CINEFUSE-FIGMA-SCREEN-INVENTORY.md](./CINEFUSE-FIGMA-SCREEN-INVENTORY.md)
