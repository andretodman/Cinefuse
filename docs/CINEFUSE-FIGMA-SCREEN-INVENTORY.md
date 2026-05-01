# Cinefuse screen inventory and code → Figma mapping

**Baseline Figma output:** see [CINEFUSE-FIGMA-BASELINE-REPORT.md](./CINEFUSE-FIGMA-BASELINE-REPORT.md).

Source: production + dev-wired UI in `packages/cinefuse-apple-core` (shared by `apps/mac` and `apps/apple-host`). Entry: `CinefuseRootView` → `LoginScreen` or `ProjectWorkspaceScreen`.

**Naming convention for frames:** `Feature / Screen / State`

## Layout rules by platform (code)

| Platform | Source | Behavior |
|----------|--------|----------|
| **iPhone** | `EditorLayoutTraits.iOS` (phone) | `useSheetBasedSidePanels=true`, `useInlineBottomRegion=false`, `useCompactWorkspaceChrome=true` |
| **iPad compact** | `horizontalSizeClass == .compact` | Same as iPhone for side panels / chrome |
| **iPad regular** | `horizontalSizeClass == .regular` | Inline split panes, `desktopLike`-style chrome (`CreationModeBinarySwitch`, `EditorWorkspacePresetSegmentSwitch` visible) |
| **Mac** | `EditorLayoutTraits.desktopLike` | Inline splits, bottom region inline, popover settings |

See [`EditorMobileLayout.swift`](../packages/cinefuse-apple-core/Sources/CinefuseAppleCore/EditorMobileLayout.swift).

## Screen / surface inventory

| Code symbol | Feature | User-facing role | Typical states |
|-------------|---------|------------------|----------------|
| `CinefuseRootView` | App shell | Auth gate | authenticated / unauthenticated |
| `LoginScreen` | Auth | Email auth | Sign In / Sign Up / Forgot Password; loading; error; success |
| `ResetPasswordSheet` | Auth | Password reset | content; loading; error |
| `ProjectWorkspaceScreen` | Workspace | Header + global sheets | error banner; server badge; onboarding trigger |
| `ProjectSidebar` | Workspace | Project list | loading; empty (`EmptyStateCard`); list + selection |
| `ProjectDetailScreen` | Editor | Main timeline + panes | no project (`ContentUnavailableView`); loading; preset × creation mode variants |
| `StoryboardPanel` | Editor | Storyboard | content / empty |
| `CharacterPanel` | Editor | Cast | content / empty |
| `SoundBlueprintsPanel` | Editor | Audio blueprint tools | audio creation mode |
| `ShotsPanel` | Editor | Shots / sounds | `ShotsPanelMode` variants |
| `EditorPreviewPanel` | Editor | Video preview | collapsed / fullscreen |
| `EditorAudioPreviewPanel` | Editor | Audio preview | — |
| `HorizontalTimelineTrack` + `TimelineClipCard` | Editor | Timeline | clip density variants |
| `JobsPanel` | Editor | Jobs queue | — |
| `AudioLaneView` + lanes UI | Editor | Audio lanes | sheet vs inline |
| `HelpCenterSheet` | Help | WKWebView help | loading / error (see `HelpCenterView.swift`) |
| `createProjectSheet` (workspace) | Workspace | New project | default |
| `onboardingSheet` | Workspace | First run | content |
| `workspaceSettingsPanel` | Settings | Editor settings | iOS sheet / macOS popover |
| `DebugGenerationWindow` | Dev | Debug log | dev-facing |
| `StatusDetailsSheet` | Diagnostics | Job/shot diagnostics | item-driven |
| `VideoPreviewSheet` | Media | Full-screen clip preview | — |
| `TimelinePanel` | Editor | (defined in `RootView`) | **Confirm:** may be unused in current flows |
| Preview popout (`PreviewPopoutWindowController` etc.) | Editor | Separate preview window | **Mac native only** (not Catalyst path) |

### Sheet attachment points (`RootView.swift`)

- Workspace-level `.sheet`: Create Project, Debug, Help, Onboarding; iOS Settings sheet.
- Login: Reset Password sheet.
- `ProjectDetailScreen`: `mobileEditorPresentedPanel` (left/right inspector, audio lanes, jobs); `selectedDiagnostics`; `VideoPreviewSheet`.

## Figma frame mapping matrix (baseline)

Use these names on the platform pages (`01-iPhone`, `02-iPad`, `03-Mac`). Sheets/modals can live under a **Sheet /** prefix or nested section.

| Code path | Figma frame name (example) | Page |
|-----------|---------------------------|------|
| `LoginScreen` authMode `.signIn` | `Auth / Login / SignIn` | all platforms |
| `LoginScreen` `.signUp` | `Auth / Login / SignUp` | all platforms |
| `LoginScreen` `.forgotPassword` | `Auth / Login / ForgotPassword` | all platforms |
| `ResetPasswordSheet` | `Auth / ResetPassword / Default` | all platforms |
| `ProjectWorkspaceScreen` + sidebar + no detail | `Workspace / SplitView / NoProjectSelected` | all platforms |
| `ProjectWorkspaceScreen` + sidebar + detail | `Workspace / SplitView / ProjectSelected` | all platforms |
| `ProjectSidebar` loading | `Workspace / ProjectGallery / Loading` | all platforms |
| `ProjectSidebar` empty | `Workspace / ProjectGallery / Empty` | all platforms |
| `ProjectDetailScreen` video + preset editing | `Editor / Main / VideoPresetEditing` | all platforms |
| `ProjectDetailScreen` audio + preset editing | `Editor / Main / AudioPresetEditing` | all platforms |
| Mobile sheet `leftInspector` | `Editor / MobileSheet / StoryAndCharacters` | iPhone, iPad compact |
| Mobile sheet `rightInspector` | `Editor / MobileSheet / ShotsAndExport` | iPhone, iPad compact |
| Mobile sheet `audioLanes` | `Editor / MobileSheet / AudioLanes` | iPhone, iPad compact |
| Mobile sheet `jobs` | `Editor / MobileSheet / Jobs` | iPhone, iPad compact |
| `createProjectSheet` | `Sheet / CreateProject / Default` | all platforms |
| `onboardingSheet` | `Sheet / Onboarding / Default` | all platforms |
| `workspaceSettingsPanel` | `Sheet / Settings / Default` (iOS) / `Popover / Settings / Default` (Mac) | platform-specific |
| `HelpCenterSheet` | `Sheet / Help / Default` | all platforms |
| `DebugGenerationWindow` | `Sheet / DebugLog / Default` | dev |
| `StatusDetailsSheet` | `Sheet / Diagnostics / Default` | all platforms |
| `VideoPreviewSheet` | `Sheet / VideoPreview / Default` | all platforms |

## Components (code → Figma `99-Components`)

| Code | Suggested Figma component |
|------|-------------------------|
| `PrimaryActionButtonStyle` | `DS / Button / Primary` |
| `SecondaryActionButtonStyle` | `DS / Button / Secondary` |
| `DestructiveActionButtonStyle` | `DS / Button / Destructive` |
| `IconCommandButton` | `DS / IconButton / Default` |
| `SectionCard` | `DS / SectionCard` |
| `EmptyStateCard` | `DS / EmptyStateCard` |
| `ErrorBanner` | `DS / ErrorBanner` |
| `StatusBadge` + `StatusStyle` | `DS / StatusBadge` (variants per status) |
| `PubfuseLogoBadge` | `DS / Logo / PubfuseBadge` |
| `TimelineClipCard` | `DS / TimelineClipCard` |
| `TimelineRulerStrip` | `DS / TimelineRulerStrip` |

Token reference: [`DesignTokens.swift`](../packages/cinefuse-apple-core/Sources/CinefuseAppleCore/DesignTokens.swift) (`Spacing` 4–32, `Radius` 8/12/16, `Control` sizes).

## Manual confirmation / ambiguity

1. **`TimelinePanel`**: Present in code; verify if still reachable vs legacy.
2. **Preview popout**: Mac-only; include separate frame on `03-Mac` if product wants it documented.
3. **`HelpCenterSheet`**: Large `minWidth`/`minHeight` in code — phone behavior may scale; Figma uses simplified chrome.
4. **`PubfuseLogoImage`**: Loads from local filesystem paths with SF Symbol fallback — final marketing asset TBD.
5. **Dev-only `DebugGenerationWindow`**: Included as optional sheet frame for parity with dev builds.
