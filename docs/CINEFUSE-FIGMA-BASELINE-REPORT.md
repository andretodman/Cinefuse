# Cinefuse → Figma baseline sync report

**Figma file:** [Untitled design](https://www.figma.com/design/0yJngv61Wo8z2vcxkeuCL5/Untitled?node-id=0-1) (`fileKey`: `0yJngv61Wo8z2vcxkeuCL5`)

**Repo docs:** [Screen inventory & mapping](./CINEFUSE-FIGMA-SCREEN-INVENTORY.md) · [Ongoing sync workflow](./CINEFUSE-FIGMA-SYNC-WORKFLOW.md)

## Pages created / organized

| Page | Purpose |
|------|---------|
| `01-iPhone` | Compact / sheet-first layouts (**landscape** `852×393` frames) |
| `02-iPad` | Regular split + compact sidebar variant (**landscape** `1194×834`) |
| `03-Mac` | Windowed workspace + popover + preview popout (`1280×832` main; auth/popover sized for landscape) |
| `99-Components` | `— Cinefuse DS —` library container |

Original empty **Page 1** was renamed to **`01-iPhone`** (non-destructive).

## Layout fidelity vs the app (`RootView.swift`)

Frames were rebuilt to follow the real SwiftUI hierarchy, not a generic mockup.

| Region | Code reference | Figma treatment |
|--------|----------------|-----------------|
| Workspace shell | `ProjectWorkspaceScreen`: **VStack** → `header` → `NavigationSplitView` | Global header bar (logo, Sparks, controls) above **split**: sidebar **~280pt** + detail |
| Sidebar | `ProjectSidebar`: “Project Gallery” title card + list / empty | Title + subtitle in card; list or `EmptyStateCard` |
| Detail (no project) | `ContentUnavailableView` (“Select a Project”) | Centered copy in detail column |
| Editor | `ProjectDetailScreen` | **Project header** (title, ID line, Close) → **timeline strip on top** (`HorizontalTimelineTrack`) → **HStack** left pane \| handle \| **preview** \| handle \| right pane → optional **bottom** audio lanes + jobs |
| iPhone | `EditorLayoutTraits` sheet-style panels | Timeline-on-top + **full-width preview** + **icon toolbar** (stand-in for compact chrome) |

Remaining gaps: real SF Symbols, exact `460pt` side defaults, live waveform/video cells, and scroll clipping are still schematic. For pixel-perfect captures, mirror from a running build or screenshots.

## Components created (`99-Components`)

Inside frame **`— Cinefuse DS —`** (library container):

| Component | Maps to code |
|-----------|----------------|
| `DS / Button / Primary` | `PrimaryActionButtonStyle` |
| `DS / Button / Secondary` | `SecondaryActionButtonStyle` |
| `DS / Button / Destructive` | `DestructiveActionButtonStyle` |
| `DS / IconCommandButton` | `IconCommandButton` |
| `DS / EmptyStateCard` | `EmptyStateCard` |
| `DS / ErrorBanner` | `ErrorBanner` |
| `DS / SectionCard` | `SectionCard` |
| `DS / StatusBadge` | `StatusBadge` |
| `DS / TimelineClipCard` | `TimelineClipCard` |

Sizing/colors approximate [`DesignTokens.swift`](../packages/cinefuse-apple-core/Sources/CinefuseAppleCore/DesignTokens.swift) (spacing 8–16, radius 8–16, button min 88×34). Typography uses **Inter** in Figma as a stand-in for SF system fonts.

**Not built as separate components (reuse / simplify later):** `TimelineRulerStrip`, `PubfuseLogoBadge` (placeholder rects/text on screens), `GenerationActivityProgressRow`.

## Screens created (representative frames)

### iPhone (`01-iPhone`)

- `Auth / Login / SignIn`
- `Workspace / SplitView / NoProjectSelected`
- `Editor / Main / VideoPresetEditing`
- `Sheet / CreateProject / Default`
- `Editor / MobileSheet / StoryAndCharacters`
- `Sheet / Help / Default`

### iPad (`02-iPad`)

- `Auth / Login / SignIn`
- `Workspace / SplitView / ProjectSelected` (inline chrome: Video/Audio + Edit/Audio/Review/Render)
- `Workspace / SplitView / CompactSidebar` (narrow rail / compact behavior)
- `Sheet / Settings / Default`

### Mac (`03-Mac`)

- `Auth / Login / SignIn`
- `Workspace / SplitView / ProjectSelected` (title strip + three-column body + timeline strip)
- `Popover / Settings / Default`
- `Window / PreviewPopout / Default`

Additional flows from code are listed in the inventory doc and can be duplicated from these templates.

## Prototype links (primary flows)

| Flow | Trigger | Action |
|------|---------|--------|
| Auth → Workspace (iPhone) | Click **Sign In / Demo** row (`INSTANCE` row on login screen) | Navigate → `Workspace / SplitView / NoProjectSelected` |
| Workspace → Editor (iPhone) | Click **detail** pane (Select a Project area) | Navigate → `Editor / Main / VideoPresetEditing` |
| Editor → Create project sheet (iPhone) | Click **4th icon** on **iOS toolbar** row | **Overlay** → `Sheet / CreateProject / Default` |
| Auth → Workspace (iPad) | Click primary button instance on login | Navigate → `Workspace / SplitView / ProjectSelected` |
| Auth → Workspace (Mac) | Click login frame hotspot (`13:22` — full-card tap) | Navigate → `Workspace / SplitView / ProjectSelected` |

Add more links (Help, Settings, diagnostics, video preview) by cloning frames and attaching `setReactionsAsync` the same way.

## Inferred / missing screens — confirm manually

- Full **`Auth / Login / SignUp`** and **`ForgotPassword`** frames (only Sign In hero built on phone).
- **`Sheet / Onboarding / Default`**, **`Sheet / DebugLog / Default`**, **`Sheet / Diagnostics / Default`**, **`Sheet / VideoPreview / Default`**
- **`Editor / Main / AudioPresetEditing`** and preset variants **Review / Render** as distinct frames
- **`TimelinePanel`** usage if still reachable in app
- **`ResetPasswordSheet`** modal
- Pixel parity for **`HelpCenterSheet`** mins on small devices

## Ambiguities (code → design)

- **`PubfuseLogoImage`** uses filesystem paths + SF Symbol fallback; logo asset for designers still TBD.
- Mixed **token vs literal** values in `RootView.swift` (some controls use ad hoc radii/opacities).
- **SF Pro vs Inter** in Figma; swap text styles if you publish an Apple system font library.

## Initial changelog (baseline)

### iPhone

- Added: Auth, workspace empty, editor compact, create-project sheet, mobile inspector sheet, Help sheet; DS instances on screens.
- Prototypes: Login → Workspace → Editor; toolbar → Create Project overlay.

### iPad

- Added: Auth, full split editor with segmented chrome, compact sidebar variant, Settings sheet.
- Prototypes: Login → Workspace (project selected).

### Mac

- Added: Auth, desktop split workspace, Settings popover frame, Preview popout window frame.
- Prototypes: Login → Workspace (whole-frame hotspot).

### Components

- Added: Primary/Secondary/Destructive buttons, icon command, empty state, error banner, section card, status badge, timeline clip card.

---

*Next UI change:* follow [CINEFUSE-FIGMA-SYNC-WORKFLOW.md](./CINEFUSE-FIGMA-SYNC-WORKFLOW.md) and append a dated changelog section.
