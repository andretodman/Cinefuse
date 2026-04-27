import SwiftUI
import UniformTypeIdentifiers
#if canImport(AVKit)
import AVKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

public struct CinefuseRootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Group {
            if model.isAuthenticated {
                ProjectWorkspaceScreen()
            } else {
                LoginScreen()
            }
        }
        .background(CinefuseTokens.ColorRole.canvas)
    }
}

struct TimelineRulerView: View {
    let shots: [Shot]
    let trimByShotId: [String: ClosedRange<Double>]
    let palette: CinefuseTokens.ThemePalette

    private var totalDuration: Int {
        shots.reduce(0) { $0 + max($1.durationSec ?? 5, 1) }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let seconds = max(totalDuration, 1)
            let step = width / CGFloat(seconds)
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(palette.timelineRuler.opacity(0.14))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0...seconds, id: \.self) { second in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(palette.timelineRuler.opacity(second % 5 == 0 ? 0.9 : 0.55))
                                .frame(
                                    width: 1,
                                    height: second % 5 == 0
                                        ? CinefuseTokens.Control.timelineNotchMajor
                                        : CinefuseTokens.Control.timelineNotchMinor
                                )
                            if second % 5 == 0 {
                                Text("\(second)s")
                                    .font(CinefuseTokens.Typography.micro)
                                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            } else {
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(width: step, alignment: .leading)
                    }
                }
                .padding(.horizontal, CinefuseTokens.Spacing.xs)
                .padding(.vertical, CinefuseTokens.Spacing.xxs)
            }
            .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
        }
        .frame(height: CinefuseTokens.Control.timelineRulerHeight)
    }
}

struct LoginScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage("cinefuse.server.mode") private var apiServerModeRaw = APIServerMode.local.rawValue
    @AppStorage("cinefuse.server.customBaseURL") private var customServerBaseURL = ""
    @AppStorage("cinefuse.auth.demoEmail") private var demoEmail = "tester@pubfuse.com"
    @AppStorage("cinefuse.auth.demoPassword") private var demoPassword = "pubfuseguest"
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var signupUsername = ""
    @State private var signupDisplayName = ""
    @State private var forgotEmail = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp
        case forgotPassword

        var id: String { rawValue }

        var label: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Sign Up"
            case .forgotPassword: return "Forgot Password"
            }
        }
    }

    private var localCinefuseBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000"
    }

    private var productionCinefuseBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_PROD_BASE_URL"] ?? "https://api.pubfuse.com"
    }

    private var selectedCinefuseBaseURL: String {
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .local {
        case .local:
            return localCinefuseBaseURL
        case .production:
            return productionCinefuseBaseURL
        case .custom:
            return normalizedURL(customServerBaseURL) ?? localCinefuseBaseURL
        }
    }

    private var selectedAuthBaseURL: String {
        let explicitAuthBase = normalizedURL(ProcessInfo.processInfo.environment["CINEFUSE_AUTH_BASE_URL"] ?? "")
        if let explicitAuthBase {
            return explicitAuthBase
        }
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .local {
        case .local:
            return "https://www.pubfuse.com"
        case .production:
            return productionCinefuseBaseURL
        case .custom:
            return normalizedURL(customServerBaseURL) ?? "https://www.pubfuse.com"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Welcome to Cinefuse")
                .font(CinefuseTokens.Typography.screenTitle)

            Text("Sign in with your Pubfuse account. Cinefuse will use your authenticated user ID for projects, jobs, and Sparks tracking.")
                .font(CinefuseTokens.Typography.body)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

            Picker("Mode", selection: $authMode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch authMode {
            case .signIn:
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: CinefuseTokens.Spacing.s) {
                    Button {
                        Task { await signInWithEmail() }
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button {
                        Task { await signInDemoUser() }
                    } label: {
                        Label("Demo Sign In", systemImage: "sparkles")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(isLoading || demoEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || demoPassword.isEmpty)
                }

            case .signUp:
                TextField("Username", text: $signupUsername)
                    .textFieldStyle(.roundedBorder)

                TextField("Display Name", text: $signupDisplayName)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await signUpWithEmail() }
                } label: {
                    Label("Create Account", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(
                    isLoading
                        || signupUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || signupDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.count < 6
                )

            case .forgotPassword:
                TextField("Email", text: $forgotEmail)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await requestPasswordReset() }
                } label: {
                    Label("Send Reset Link", systemImage: "envelope.badge")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isLoading || forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let successMessage {
                Text(successMessage)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(.green)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.danger)
            }

            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Label("Auth server: \(selectedAuthBaseURL)", systemImage: "network")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                Label("Cinefuse API: \(selectedCinefuseBaseURL)", systemImage: "server.rack")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
        }
        .padding(CinefuseTokens.Spacing.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            email = model.userEmail
            forgotEmail = model.userEmail
        }
    }

    private func normalizedURL(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.scheme != nil, url.host != nil else {
            return nil
        }
        return withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    @MainActor
    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private func signInWithEmail() async {
        await MainActor.run {
            isLoading = true
            clearMessages()
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let auth = try await APIClient(baseURLString: selectedCinefuseBaseURL)
                .loginPubfuse(
                    authBaseURLString: selectedAuthBaseURL,
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            await MainActor.run {
                model.signInPubfuse(
                    userId: auth.user.id,
                    accessToken: auth.token,
                    email: auth.user.email,
                    displayName: auth.user.resolvedDisplayName
                )
                successMessage = "Signed in as \(auth.user.resolvedDisplayName)."
                password = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signInDemoUser() async {
        await MainActor.run {
            isLoading = true
            clearMessages()
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let auth = try await APIClient(baseURLString: selectedCinefuseBaseURL)
                .loginPubfuse(
                    authBaseURLString: selectedAuthBaseURL,
                    email: demoEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: demoPassword
                )
            await MainActor.run {
                model.signInPubfuse(
                    userId: auth.user.id,
                    accessToken: auth.token,
                    email: auth.user.email,
                    displayName: auth.user.resolvedDisplayName
                )
                successMessage = "Signed in with demo account."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signUpWithEmail() async {
        await MainActor.run {
            isLoading = true
            clearMessages()
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let auth = try await APIClient(baseURLString: selectedCinefuseBaseURL)
                .signupPubfuse(
                    authBaseURLString: selectedAuthBaseURL,
                    username: signupUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    displayName: signupDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            await MainActor.run {
                model.signInPubfuse(
                    userId: auth.user.id,
                    accessToken: auth.token,
                    email: auth.user.email,
                    displayName: auth.user.resolvedDisplayName
                )
                successMessage = "Account created and signed in."
                password = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestPasswordReset() async {
        await MainActor.run {
            isLoading = true
            clearMessages()
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            try await APIClient(baseURLString: selectedCinefuseBaseURL)
                .requestPubfusePasswordReset(
                    authBaseURLString: selectedAuthBaseURL,
                    email: forgotEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            await MainActor.run {
                successMessage = "Password reset email sent. Check your inbox."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ProjectWorkspaceScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var titleDraft = ""
    @State private var isCreateProjectSheetPresented = false
    @FocusState private var isCreateProjectTitleFocused: Bool

    @State private var selectedProjectId: String?
    @State private var scenes: [StoryScene] = []
    @State private var characters: [CharacterProfile] = []
    @State private var shots: [Shot] = []
    @State private var audioTracks: [AudioTrack] = []
    @State private var jobs: [Job] = []
    @State private var shotPromptDraft = "Establishing shot of the location"
    @State private var shotModelTierDraft = "standard"
    @State private var quotedShotCost: ShotQuote?
    @State private var newCharacterName = ""
    @State private var newCharacterDescription = ""
    @State private var selectedCharacterLockId = ""
    @State private var audioTrackTitleDraft = "Dialogue pass"
    @AppStorage("cinefuse.editor.export.resolution") private var exportResolution = "1080p"
    @AppStorage("cinefuse.editor.export.captionsEnabled") private var exportCaptionsEnabled = false
    @AppStorage("cinefuse.editor.export.transitionStyle") private var transitionStyle = "crossfade"
    @AppStorage("cinefuse.editor.export.includeArchive") private var exportIncludeArchive = true
    @AppStorage("cinefuse.editor.export.publishTarget") private var exportPublishTarget = "none"
    @AppStorage("cinefuse.editor.selectedThemeMode") private var timelineThemeModeRaw = TimelineThemeMode.system.rawValue
    @AppStorage("cinefuse.editor.lastProjectId") private var lastProjectId = ""
    @AppStorage("cinefuse.editor.showLeftPane") private var showLeftPane = true
    @AppStorage("cinefuse.editor.showRightPane") private var showRightPane = true
    @AppStorage("cinefuse.editor.showBottomPane") private var showBottomPane = true
    @AppStorage("cinefuse.editor.swapSidePanes") private var swapSidePanes = false
    @AppStorage("cinefuse.editor.workspacePreset") private var workspacePresetRaw = EditorWorkspacePreset.editing.rawValue
    @State private var jobKindDraft = "clip"
    @State private var isLoadingProjectDetails = false
    @State private var isRefreshingProjectDetails = false
    @State private var hasLiveEventsConnection = false
    @State private var editorSettings = EditorSettingsModel()
    @State private var showSettingsPanel = false
    @State private var isCheckingServerHealth = false
    @State private var isServerReachable: Bool?
    @AppStorage("cinefuse.server.mode") private var apiServerModeRaw = APIServerMode.local.rawValue
    @AppStorage("cinefuse.server.customBaseURL") private var customServerBaseURL = ""

    private let inFlightStatuses: Set<String> = ["queued", "generating", "running"]
    private var localServerBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000"
    }
    private var productionServerBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_PROD_BASE_URL"] ?? "https://api.pubfuse.com"
    }
    private var activeServerBaseURL: String {
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .local {
        case .local:
            return localServerBaseURL
        case .production:
            return productionServerBaseURL
        case .custom:
            return normalizedServerURL(customServerBaseURL) ?? localServerBaseURL
        }
    }
    private var api: APIClient {
        APIClient(baseURLString: activeServerBaseURL)
    }
    private var serverModeLabel: String {
        (APIServerMode(rawValue: apiServerModeRaw) ?? .local).label
    }

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return model.projects.first(where: { $0.id == selectedProjectId })
    }

    private var hasInFlightWork: Bool {
        shots.contains(where: { inFlightStatuses.contains($0.status) })
            || jobs.contains(where: { inFlightStatuses.contains($0.status) })
    }
    private var timelineThemeMode: TimelineThemeMode {
        TimelineThemeMode(rawValue: timelineThemeModeRaw) ?? .system
    }
    private var timelineThemeModeBinding: Binding<TimelineThemeMode> {
        Binding(
            get: { timelineThemeMode },
            set: { timelineThemeModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            header

            if let errorMessage = model.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            NavigationSplitView {
                ProjectSidebar(
                    projects: model.projects,
                    selectedProjectId: $selectedProjectId,
                    isLoading: model.isLoading
                )
            } detail: {
                ProjectDetailScreen(
                    project: selectedProject,
                    isLoadingProjectDetails: isLoadingProjectDetails,
                    scenes: scenes,
                    characters: characters,
                    shots: shots,
                    audioTracks: audioTracks,
                    jobs: jobs,
                    shotPromptDraft: $shotPromptDraft,
                    shotModelTierDraft: $shotModelTierDraft,
                    selectedCharacterLockId: $selectedCharacterLockId,
                    audioTrackTitleDraft: $audioTrackTitleDraft,
                    exportResolution: $exportResolution,
                    exportCaptionsEnabled: $exportCaptionsEnabled,
                    transitionStyle: $transitionStyle,
                    exportIncludeArchive: $exportIncludeArchive,
                    exportPublishTarget: $exportPublishTarget,
                    timelineThemeMode: timelineThemeModeBinding,
                    quotedShotCost: quotedShotCost,
                    newCharacterName: $newCharacterName,
                    newCharacterDescription: $newCharacterDescription,
                    jobKindDraft: $jobKindDraft,
                    onCloseProject: closeProject,
                    onDeleteProject: { Task { await deleteSelectedProject() } },
                    onCreateCharacter: { Task { await createCharacter() } },
                    onTrainCharacter: { characterId in Task { await trainCharacter(characterId: characterId) } },
                    onGenerateStoryboard: { Task { await generateStoryboard() } },
                    onReviseScene: { scene, revision in Task { await reviseScene(scene: scene, revision: revision) } },
                    onQuote: { Task { await quoteShot() } },
                    onCreateShot: { Task { await createShot() } },
                    onGenerateShot: { shotId in Task { await generateShot(shotId: shotId) } },
                    onCreateJob: { Task { await createJob() } },
                    onReorderShots: { from, to in Task { await reorderShots(from: from, to: to) } },
                    onGenerateDialogue: { Task { await generateDialogueTrack() } },
                    onGenerateScore: { Task { await generateScoreTrack() } },
                    onGenerateSFX: { Task { await generateSFXTrack() } },
                    onMixAudio: { Task { await mixAudioTrack() } },
                    onLipSync: { Task { await generateLipSyncTrack() } },
                    onPreviewStitch: { Task { await previewStitchTimeline() } },
                    onApplyTransitions: { Task { await applyTimelineTransitions() } },
                    onColorMatch: { Task { await applyTimelineColorMatch() } },
                    onBakeCaptions: { Task { await bakeTimelineCaptions() } },
                    onNormalizeLoudness: { Task { await normalizeTimelineLoudness() } },
                    onFinalStitch: { Task { await finalStitchTimeline() } },
                    onExportFinal: { Task { await exportFinalTimeline() } },
                    showTooltips: editorSettings.showTooltips
                )
            }
            .onChange(of: selectedProjectId) { _, _ in
                if let selectedProjectId {
                    lastProjectId = selectedProjectId
                }
                Task { await loadSelectedProjectDetails(showLoadingIndicator: true) }
            }
        }
        .padding(.horizontal, CinefuseTokens.Spacing.s)
        .padding(.bottom, CinefuseTokens.Spacing.s)
        .padding(.top, CinefuseTokens.Spacing.xxs)
        .sheet(isPresented: $isCreateProjectSheetPresented) {
            createProjectSheet
        }
        .task {
            if editorSettings.restoreLastOpenWorkspace, !lastProjectId.isEmpty {
                await refresh(selectProjectId: lastProjectId)
            } else {
                await refresh(selectProjectId: selectedProjectId)
            }
            await refreshServerHealth()
        }
        .preferredColorScheme(timelineThemeMode.colorScheme)
        .task(id: selectedProjectId) {
            await monitorInFlightJobs()
        }
        .task(id: selectedProjectId) {
            await observeProjectEvents()
        }
        .onChange(of: apiServerModeRaw) { _, _ in
            Task {
                await refresh(selectProjectId: selectedProjectId)
                await refreshServerHealth()
            }
        }
        .onChange(of: customServerBaseURL) { _, _ in
            guard (APIServerMode(rawValue: apiServerModeRaw) ?? .local) == .custom else { return }
            Task { await refreshServerHealth() }
        }
        .tint(timelineThemeMode.palette.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
            PubfuseLogoBadge()
            Spacer(minLength: CinefuseTokens.Spacing.s)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    globalWorkspaceControls
                    serverStatusBadge
                    Label("Sparks: \(model.balance)", systemImage: "sparkles")
                        .font(CinefuseTokens.Typography.label)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    if selectedProject == nil {
                        Button {
                            openCreateProjectSheet()
                        } label: {
                            Label("New Project", systemImage: "plus.square.on.square")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .keyboardShortcut("n", modifiers: [.command])
                    }
                    Button {
                        closeProject()
                        model.signOut()
                        lastProjectId = ""
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
                VStack(alignment: .trailing, spacing: CinefuseTokens.Spacing.xs) {
                    globalWorkspaceControls
                    serverStatusBadge
                    Label("Sparks: \(model.balance)", systemImage: "sparkles")
                        .font(CinefuseTokens.Typography.label)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        if selectedProject == nil {
                            Button {
                                openCreateProjectSheet()
                            } label: {
                                Label("New", systemImage: "plus.square.on.square")
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .keyboardShortcut("n", modifiers: [.command])
                        }
                        Button {
                            closeProject()
                            model.signOut()
                            lastProjectId = ""
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            }
            .padding(.horizontal, CinefuseTokens.Spacing.s)
            .padding(.vertical, CinefuseTokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                    .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private var globalWorkspaceControls: some View {
        HStack(spacing: CinefuseTokens.Spacing.xs) {
            Picker("Workspace", selection: $workspacePresetRaw) {
                ForEach(EditorWorkspacePreset.allCases) { preset in
                    Text(preset.label).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: CinefuseTokens.Control.jobPickerWidth)
            .onChange(of: workspacePresetRaw) { _, newValue in
                applyWorkspacePreset(newValue)
            }
            .tooltip("Choose workspace layout preset", enabled: editorSettings.showTooltips)

            IconCommandButton(
                systemName: showLeftPane ? "sidebar.left" : "sidebar.left",
                label: "Toggle left panel",
                action: { showLeftPane.toggle() },
                tooltipEnabled: editorSettings.showTooltips
            )
            
            IconCommandButton(
                systemName: showRightPane ? "sidebar.right" : "sidebar.right",
                label: "Toggle right panel",
                action: { showRightPane.toggle() },
                tooltipEnabled: editorSettings.showTooltips
            )
            IconCommandButton(
                systemName: showBottomPane ? "rectangle.split.3x1.fill" : "rectangle.split.3x1",
                label: "Toggle bottom panel",
                action: { showBottomPane.toggle() },
                tooltipEnabled: editorSettings.showTooltips
            )
            IconCommandButton(
                systemName: "arrow.left.arrow.right.square",
                label: "Swap side panels",
                action: { swapSidePanes.toggle() },
                tooltipEnabled: editorSettings.showTooltips
            )

            Picker("Theme", selection: timelineThemeModeBinding) {
                ForEach(TimelineThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 100)
            .tooltip("Choose appearance theme", enabled: editorSettings.showTooltips)

            IconCommandButton(
                systemName: "slider.horizontal.3",
                label: "Editor settings",
                action: { showSettingsPanel.toggle() },
                tooltipEnabled: editorSettings.showTooltips
            )
            .popover(isPresented: $showSettingsPanel, arrowEdge: .bottom) {
                workspaceSettingsPanel
            }
        }
    }

    private var workspaceSettingsPanel: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            Text("Editor Settings")
                .font(CinefuseTokens.Typography.cardTitle)
            Toggle("Show tooltips", isOn: $editorSettings.showTooltips)
            Toggle("Restore last open project", isOn: $editorSettings.restoreLastOpenWorkspace)
            Divider()
            Text("Server")
                .font(CinefuseTokens.Typography.label)
            Picker("API Server", selection: $apiServerModeRaw) {
                ForEach(APIServerMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            if (APIServerMode(rawValue: apiServerModeRaw) ?? .local) == .custom {
                TextField("https://your-server.example.com", text: $customServerBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Current API base URL: \(activeServerBaseURL)")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            serverStatusBadge
            Button("Reconnect Server") {
                Task {
                    await refresh(selectProjectId: selectedProjectId)
                    await refreshServerHealth()
                }
            }
            .buttonStyle(SecondaryActionButtonStyle())
            Text("Selected theme is saved automatically.")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
        .padding(CinefuseTokens.Spacing.m)
        .frame(width: CinefuseTokens.Control.settingsPanelWidth)
    }

    private func normalizedServerURL(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return trimmed
    }

    private var serverStatusBadge: some View {
        let stateText: String = {
            if isCheckingServerHealth {
                return "Checking"
            }
            if let isServerReachable {
                return isServerReachable ? "Online" : "Offline"
            }
            return "Unknown"
        }()
        let dotColor: Color = {
            if isCheckingServerHealth {
                return CinefuseTokens.ColorRole.warning
            }
            if let isServerReachable {
                return isServerReachable ? CinefuseTokens.ColorRole.success : CinefuseTokens.ColorRole.danger
            }
            return CinefuseTokens.ColorRole.textSecondary
        }()

        return HStack(spacing: CinefuseTokens.Spacing.xxs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text("\(serverModeLabel): \(stateText)")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
    }

    private func refreshServerHealth() async {
        isCheckingServerHealth = true
        let reachable = await api.healthCheck()
        isServerReachable = reachable
        isCheckingServerHealth = false
    }

    private func applyWorkspacePreset(_ rawValue: String) {
        guard let preset = EditorWorkspacePreset(rawValue: rawValue) else { return }
        switch preset {
        case .editing:
            showLeftPane = true
            showRightPane = true
            showBottomPane = true
            swapSidePanes = false
        case .audio:
            showLeftPane = false
            showRightPane = true
            showBottomPane = true
            swapSidePanes = false
        case .review:
            showLeftPane = true
            showRightPane = false
            showBottomPane = true
            swapSidePanes = false
        }
    }

    private var createProjectSheet: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Create New Project")
                .font(CinefuseTokens.Typography.sectionTitle)
            Text("Give your film a working title. You can rename it later.")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

            TextField("Project title", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isCreateProjectTitleFocused)
                .onSubmit {
                    Task { await createProject() }
                }
            HStack {
                Spacer()
                Button("Cancel") {
                    isCreateProjectSheetPresented = false
                }
                .buttonStyle(SecondaryActionButtonStyle())
                Button("Create Project") {
                    Task { await createProject() }
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .padding(CinefuseTokens.Spacing.l)
        .frame(minWidth: 420)
        .onAppear {
            forceAppFocusForTextEntry()
        }
        .task {
            titleDraft = ""
            forceFieldFocusSoon()
        }
    }

    private func refresh(selectProjectId: String? = nil) async {
        model.isLoading = true
        model.errorMessage = nil
        do {
            async let projects = api.listProjects(token: model.bearerToken)
            async let balance = api.getBalance(token: model.bearerToken)
            model.projects = try await projects
            model.balance = try await balance
            if let selectProjectId {
                selectedProjectId = selectProjectId
            } else if !model.projects.contains(where: { $0.id == selectedProjectId }) {
                selectedProjectId = model.projects.first?.id
            }
            await loadSelectedProjectDetails(showLoadingIndicator: true)
        } catch {
            model.errorMessage = error.localizedDescription
        }
        model.isLoading = false
    }

    private func createProject() async {
        model.errorMessage = nil
        do {
            let normalizedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let createdProject = try await api.createProject(
                token: model.bearerToken,
                title: normalizedTitle.isEmpty ? "Untitled project" : normalizedTitle
            )
            isCreateProjectSheetPresented = false
            await refresh(selectProjectId: createdProject.id)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedProject() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            try await api.deleteProject(token: model.bearerToken, projectId: selectedProjectId)
            closeProject()
            await refresh()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func closeProject() {
        selectedProjectId = nil
        scenes = []
        characters = []
        quotedShotCost = nil
        shots = []
        audioTracks = []
        jobs = []
        if !editorSettings.restoreLastOpenWorkspace {
            lastProjectId = ""
        }
    }

    private func openCreateProjectSheet() {
        forceAppFocusForTextEntry()
        isCreateProjectSheetPresented = true
    }

    private func forceAppFocusForTextEntry() {
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
#endif
    }

    private func forceFieldFocusSoon() {
        DispatchQueue.main.async {
            isCreateProjectTitleFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isCreateProjectTitleFocused = true
        }
    }

    private func loadSelectedProjectDetails(showLoadingIndicator: Bool = false) async {
        guard let selectedProjectId else {
            scenes = []
            characters = []
            shots = []
            audioTracks = []
            jobs = []
            return
        }
        if isRefreshingProjectDetails {
            return
        }
        isRefreshingProjectDetails = true
        if showLoadingIndicator {
            isLoadingProjectDetails = true
        }
        defer {
            isRefreshingProjectDetails = false
            if showLoadingIndicator {
                isLoadingProjectDetails = false
            }
        }
        do {
            async let projectScenes = api.listScenes(token: model.bearerToken, projectId: selectedProjectId)
            async let projectCharacters = api.listCharacters(token: model.bearerToken, projectId: selectedProjectId)
            async let timeline = api.listTimeline(token: model.bearerToken, projectId: selectedProjectId)
            async let projectJobs = api.listJobs(token: model.bearerToken, projectId: selectedProjectId)
            let latestScenes = try await projectScenes
            let latestCharacters = try await projectCharacters
            let latestTimeline = try await timeline
            let latestJobs = try await projectJobs
            var transaction = Transaction()
            if !showLoadingIndicator {
                transaction.animation = nil
            }
            withTransaction(transaction) {
                scenes = latestScenes
                characters = latestCharacters
                shots = latestTimeline.shots
                audioTracks = latestTimeline.audioTracks
                jobs = latestJobs
            }
            model.errorMessage = nil
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func monitorInFlightJobs() async {
        guard selectedProjectId != nil else { return }
        while !Task.isCancelled && selectedProjectId != nil {
            if scenePhase == .active && hasInFlightWork && !hasLiveEventsConnection {
                await loadSelectedProjectDetails(showLoadingIndicator: false)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private func observeProjectEvents() async {
        guard let projectId = selectedProjectId else {
            hasLiveEventsConnection = false
            return
        }

        while !Task.isCancelled && selectedProjectId == projectId {
            do {
                let stream = api.streamProjectEvents(token: model.bearerToken, projectId: projectId)
                hasLiveEventsConnection = true
                for try await event in stream {
                    if Task.isCancelled || selectedProjectId != projectId {
                        break
                    }
                    if event.type == "connected" {
                        continue
                    }
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                }
            } catch {
                // Background event stream failures should not block the editor flow.
            }

            hasLiveEventsConnection = false
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func createShot() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            _ = try await api.createShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                prompt: shotPromptDraft,
                modelTier: shotModelTierDraft,
                characterLocks: selectedCharacterLockId.isEmpty ? [] : [selectedCharacterLockId]
            )
            quotedShotCost = nil
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateStoryboard() async {
        guard let project = selectedProject else { return }
        model.errorMessage = nil
        do {
            _ = try await api.generateStoryboard(
                token: model.bearerToken,
                projectId: project.id,
                logline: project.logline,
                targetDurationMinutes: project.targetDurationMinutes,
                tone: project.tone
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reviseScene(scene: StoryScene, revision: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            _ = try await api.reviseScene(
                token: model.bearerToken,
                projectId: selectedProjectId,
                sceneId: scene.id,
                title: scene.title,
                revision: revision,
                orderIndex: scene.orderIndex,
                mood: scene.mood
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func createCharacter() async {
        guard let selectedProjectId else { return }
        let normalizedName = newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        model.errorMessage = nil
        do {
            _ = try await api.createCharacter(
                token: model.bearerToken,
                projectId: selectedProjectId,
                name: normalizedName,
                description: newCharacterDescription
            )
            newCharacterName = ""
            newCharacterDescription = ""
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func trainCharacter(characterId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            _ = try await api.trainCharacter(token: model.bearerToken, projectId: selectedProjectId, characterId: characterId)
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func quoteShot() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            quotedShotCost = try await api.quoteShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                prompt: shotPromptDraft,
                modelTier: shotModelTierDraft
            )
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateShot(shotId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let generation = try await api.generateShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shotId
            )
            quotedShotCost = generation.quote
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func createJob() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            _ = try await api.createJob(
                token: model.bearerToken,
                projectId: selectedProjectId,
                kind: jobKindDraft
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func reorderShots(from: IndexSet, to: Int) async {
        guard let selectedProjectId else { return }
        var reordered = shots
        reordered.move(fromOffsets: from, toOffset: to)
        shots = reordered
        do {
            _ = try await api.reorderTimelineShots(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotIds: reordered.map(\.id)
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateDialogueTrack() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.generateDialogue(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shots.first?.id,
                title: audioTrackTitleDraft,
                laneIndex: 0,
                startMs: 0,
                durationMs: 4000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateScoreTrack() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.generateScore(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: "Score bed",
                laneIndex: 1,
                startMs: 0,
                durationMs: 10000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateSFXTrack() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.generateSFX(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: audioTrackTitleDraft.isEmpty ? "Foley accent" : audioTrackTitleDraft,
                laneIndex: 2,
                startMs: 0,
                durationMs: 2500
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func mixAudioTrack() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.mixAudio(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: "Scene mixdown",
                laneIndex: 3,
                startMs: 0,
                durationMs: 10000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateLipSyncTrack() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.lipsyncAudio(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shots.first?.id,
                title: "Lip-sync pass",
                laneIndex: 0,
                startMs: 0,
                durationMs: 4000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func previewStitchTimeline() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.previewStitch(
                token: model.bearerToken,
                projectId: selectedProjectId,
                transitionStyle: transitionStyle,
                captionsEnabled: exportCaptionsEnabled
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyTimelineTransitions() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.applyTransitions(
                token: model.bearerToken,
                projectId: selectedProjectId,
                transitionStyle: transitionStyle
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func applyTimelineColorMatch() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.colorMatchStitch(
                token: model.bearerToken,
                projectId: selectedProjectId,
                colorMatchMode: "balanced"
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func bakeTimelineCaptions() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.bakeCaptions(
                token: model.bearerToken,
                projectId: selectedProjectId,
                captionsEnabled: exportCaptionsEnabled
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func normalizeTimelineLoudness() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.normalizeLoudness(
                token: model.bearerToken,
                projectId: selectedProjectId,
                targetLufs: -14
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func finalStitchTimeline() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.finalStitch(
                token: model.bearerToken,
                projectId: selectedProjectId,
                transitionStyle: transitionStyle,
                captionsEnabled: exportCaptionsEnabled,
                resolution: exportResolution
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func exportFinalTimeline() async {
        guard let selectedProjectId else { return }
        do {
            let effectivePublishTarget = exportPublishTarget == "pubfuse" ? "pubfuse" : "none"
            _ = try await api.exportFinal(
                token: model.bearerToken,
                projectId: selectedProjectId,
                resolution: exportResolution,
                captionsEnabled: exportCaptionsEnabled,
                includeArchive: exportIncludeArchive,
                publishTarget: effectivePublishTarget
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selectedProjectId: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text("Project Gallery")
                    .font(CinefuseTokens.Typography.sectionTitle)
                Text("Pick a project to draft shots, quote costs, and generate clips.")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            .padding(CinefuseTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                    )
            )
            if isLoading {
                ProgressView("Loading projects...")
                    .font(CinefuseTokens.Typography.caption)
            }
            if projects.isEmpty {
                EmptyStateCard(
                    title: "No projects yet",
                    message: "Create a project to start drafting shots and render jobs."
                )
            } else {
                List(selection: $selectedProjectId) {
                    ForEach(projects) { project in
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                            Text(project.title)
                                .font(CinefuseTokens.Typography.cardTitle)
                            Text("Phase: \(project.currentPhase) · Tone: \(project.tone)")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        }
                        .padding(.vertical, CinefuseTokens.Spacing.xxs)
                        .tag(project.id)
                    }
                }
            }
        }
        .frame(minWidth: 0)
        .clipped()
    }
}

struct ProjectDetailScreen: View {
    let project: Project?
    let isLoadingProjectDetails: Bool
    let scenes: [StoryScene]
    let characters: [CharacterProfile]
    let shots: [Shot]
    let audioTracks: [AudioTrack]
    let jobs: [Job]
    @Binding var shotPromptDraft: String
    @Binding var shotModelTierDraft: String
    @Binding var selectedCharacterLockId: String
    @Binding var audioTrackTitleDraft: String
    @Binding var exportResolution: String
    @Binding var exportCaptionsEnabled: Bool
    @Binding var transitionStyle: String
    @Binding var exportIncludeArchive: Bool
    @Binding var exportPublishTarget: String
    @Binding var timelineThemeMode: TimelineThemeMode
    let quotedShotCost: ShotQuote?
    @Binding var newCharacterName: String
    @Binding var newCharacterDescription: String
    @Binding var jobKindDraft: String

    let onCloseProject: () -> Void
    let onDeleteProject: () -> Void
    let onCreateCharacter: () -> Void
    let onTrainCharacter: (String) -> Void
    let onGenerateStoryboard: () -> Void
    let onReviseScene: (StoryScene, String) -> Void
    let onQuote: () -> Void
    let onCreateShot: () -> Void
    let onGenerateShot: (String) -> Void
    let onCreateJob: () -> Void
    let onReorderShots: (IndexSet, Int) -> Void
    let onGenerateDialogue: () -> Void
    let onGenerateScore: () -> Void
    let onGenerateSFX: () -> Void
    let onMixAudio: () -> Void
    let onLipSync: () -> Void
    let onPreviewStitch: () -> Void
    let onApplyTransitions: () -> Void
    let onColorMatch: () -> Void
    let onBakeCaptions: () -> Void
    let onNormalizeLoudness: () -> Void
    let onFinalStitch: () -> Void
    let onExportFinal: () -> Void
    let showTooltips: Bool
    @AppStorage("cinefuse.editor.leftPaneWidth") private var leftPaneWidth: Double = 460
    @AppStorage("cinefuse.editor.rightPaneWidth") private var rightPaneWidth: Double = 460
    @AppStorage("cinefuse.editor.bottomPaneHeight") private var bottomPaneHeight: Double = 240
    @AppStorage("cinefuse.editor.showLeftPane") private var showLeftPane = true
    @AppStorage("cinefuse.editor.showRightPane") private var showRightPane = true
    @AppStorage("cinefuse.editor.showBottomPane") private var showBottomPane = true
    @AppStorage("cinefuse.editor.swapSidePanes") private var swapSidePanes = false
    @AppStorage("cinefuse.editor.workspacePreset") private var workspacePresetRaw = EditorWorkspacePreset.editing.rawValue
    @State private var selectedTimelineShotId: String?
    @State private var trackSyncModes: [Int: AudioTrackSyncMode] = [:]

    var body: some View {
        Group {
            if let project {
                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                    header(project: project)

                    if isLoadingProjectDetails {
                        ProgressView("Refreshing timeline and job states...")
                            .font(CinefuseTokens.Typography.caption)
                    }

                    HorizontalTimelineTrack(
                        shots: sortedShots,
                        selectedShotId: $selectedTimelineShotId,
                        onMoveShot: onReorderShots,
                        showTooltips: showTooltips,
                        themePalette: timelineThemeMode.palette
                    )

                    GeometryReader { geometry in
                        let totalWidth = Double(max(geometry.size.width, 320))
                        let totalHeight = Double(max(geometry.size.height, 280))
                        let bottomHandleHeight = Double(CinefuseTokens.Control.splitterHitArea)
                        let minTopWorkspaceHeight = Double(CinefuseTokens.Control.minTopWorkspaceHeight)
                        let maxBottomByAvailableSpace = max(
                            0,
                            totalHeight - minTopWorkspaceHeight - (showBottomPane ? bottomHandleHeight : 0)
                        )
                        let minBottomPanelHeight = Double(CinefuseTokens.Control.minBottomPanelHeight)
                        let sanitizedBottomHeight: Double = {
                            guard showBottomPane else { return 0 }
                            if maxBottomByAvailableSpace >= minBottomPanelHeight {
                                return min(max(bottomPaneHeight, minBottomPanelHeight), maxBottomByAvailableSpace)
                            }
                            return maxBottomByAvailableSpace
                        }()
                        let topWorkspaceHeight = max(
                            0,
                            totalHeight - sanitizedBottomHeight - (showBottomPane ? bottomHandleHeight : 0)
                        )
                        let sideFrame = paneLayout(totalWidth: totalWidth)
                        let showsLeftPanel = showLeftPane && sideFrame.left > 1
                        let showsRightPanel = showRightPane && sideFrame.right > 1

                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                if showsLeftPanel {
                                    sidePaneContainer {
                                        if swapSidePanes {
                                            rightPaneContent
                                        } else {
                                            leftPaneContent
                                        }
                                    }
                                    .frame(width: CGFloat(sideFrame.left))
                                    .frame(minWidth: 0, maxHeight: .infinity)
                                    VerticalPanelHandle { delta in
                                        leftPaneWidth = clampedLeftPaneWidth(
                                            leftPaneWidth + delta,
                                            totalWidth: totalWidth,
                                            opposingPaneWidth: sideFrame.right
                                        )
                                    }
                                }

                                EditorPreviewPanel(
                                    shots: sortedShots,
                                    selectedShotId: $selectedTimelineShotId,
                                    showTooltips: showTooltips
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                                .padding(.horizontal, CinefuseTokens.Spacing.s)

                                if showsRightPanel {
                                    VerticalPanelHandle { delta in
                                        rightPaneWidth = clampedRightPaneWidth(
                                            rightPaneWidth - delta,
                                            totalWidth: totalWidth,
                                            opposingPaneWidth: sideFrame.left
                                        )
                                    }
                                    sidePaneContainer {
                                        if swapSidePanes {
                                            leftPaneContent
                                        } else {
                                            rightPaneContent
                                        }
                                    }
                                    .frame(width: CGFloat(sideFrame.right))
                                    .frame(minWidth: 0, maxHeight: .infinity)
                                }
                            }
                            .frame(height: CGFloat(topWorkspaceHeight))
                            .clipped()

                            if showBottomPane {
                                HorizontalPanelHandle { delta in
                                    bottomPaneHeight = clampedBottomPaneHeight(
                                        bottomPaneHeight - delta,
                                        totalHeight: totalHeight
                                    )
                                }
                                HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
                                    SectionCard(
                                        title: "Audio Lanes",
//                                        subtitle: "Dialogue, score, and SFX tracks mapped to timeline order."
                                    ) {
                                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                                            ViewThatFits(in: .horizontal) {
                                                HStack(spacing: CinefuseTokens.Spacing.s) {
                                                    TextField("Audio title", text: $audioTrackTitleDraft)
                                                        .textFieldStyle(.roundedBorder)
                                                    Button("Generate Dialogue", action: onGenerateDialogue)
                                                        .tooltip("Generate spoken dialogue track", enabled: showTooltips)
                                                        .buttonStyle(SecondaryActionButtonStyle())
                                                    Button("Generate Score", action: onGenerateScore)
                                                        .tooltip("Generate background music score", enabled: showTooltips)
                                                        .buttonStyle(SecondaryActionButtonStyle())
                                                    Button("Generate SFX", action: onGenerateSFX)
                                                        .tooltip("Generate one-shot sound effect", enabled: showTooltips)
                                                        .buttonStyle(SecondaryActionButtonStyle())
                                                    Button("Mix", action: onMixAudio)
                                                        .tooltip("Create mixed audio master for timeline", enabled: showTooltips)
                                                        .buttonStyle(SecondaryActionButtonStyle())
                                                    Button("Lip-sync", action: onLipSync)
                                                        .tooltip("Run lip-sync pass for selected shot", enabled: showTooltips)
                                                        .buttonStyle(SecondaryActionButtonStyle())
                                                }
                                                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                                                    TextField("Audio title", text: $audioTrackTitleDraft)
                                                        .textFieldStyle(.roundedBorder)
                                                    HStack(spacing: CinefuseTokens.Spacing.s) {
                                                        Button("Generate Dialogue", action: onGenerateDialogue)
                                                            .tooltip("Generate spoken dialogue track", enabled: showTooltips)
                                                            .buttonStyle(SecondaryActionButtonStyle())
                                                        Button("Generate Score", action: onGenerateScore)
                                                            .tooltip("Generate background music score", enabled: showTooltips)
                                                            .buttonStyle(SecondaryActionButtonStyle())
                                                        Button("Generate SFX", action: onGenerateSFX)
                                                            .tooltip("Generate one-shot sound effect", enabled: showTooltips)
                                                            .buttonStyle(SecondaryActionButtonStyle())
                                                        Button("Mix", action: onMixAudio)
                                                            .tooltip("Create mixed audio master for timeline", enabled: showTooltips)
                                                            .buttonStyle(SecondaryActionButtonStyle())
                                                        Button("Lip-sync", action: onLipSync)
                                                            .tooltip("Run lip-sync pass for selected shot", enabled: showTooltips)
                                                            .buttonStyle(SecondaryActionButtonStyle())
                                                    }
                                                }
                                            }
                                            ScrollView {
                                                AudioLaneView(
                                                    audioTracks: audioTracks,
                                                    shotBoundaries: timelineShotBoundaries,
                                                    syncModes: $trackSyncModes,
                                                    themePalette: timelineThemeMode.palette
                                                )
                                            }
                                            .frame(maxHeight: .infinity, alignment: .top)
                                        }
                                    }
                                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .clipped()

                                    JobsPanel(
                                        jobs: jobs,
                                        jobKindDraft: $jobKindDraft,
                                        onCreateJob: onCreateJob,
                                        showTooltips: showTooltips
                                    )
                                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .clipped()
                                }
                                .padding(.top, CinefuseTokens.Spacing.s)
                                .frame(height: CGFloat(sanitizedBottomHeight), alignment: .top)
                                .clipped()
                            }
                        }
                    }
                    .frame(minHeight: 380)
                }
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "film.stack",
                    description: Text("Choose a project from the sidebar or create one to get started.")
                )
            }
        }
        .onAppear {
            sanitizePersistedLayout()
        }
        .onChange(of: showLeftPane) { _, _ in
            sanitizePersistedLayout()
        }
        .onChange(of: showRightPane) { _, _ in
            sanitizePersistedLayout()
        }
        .onChange(of: showBottomPane) { _, _ in
            sanitizePersistedLayout()
        }
    }

    private var timelineShotBoundaries: [TimelineShotBoundary] {
        var cursorMs = 0
        return sortedShots.map { shot in
            let durationMs = max((shot.durationSec ?? 5) * 1_000, 500)
            let boundary = TimelineShotBoundary(
                shotId: shot.id,
                startMs: cursorMs,
                endMs: cursorMs + durationMs
            )
            cursorMs += durationMs
            return boundary
        }
    }

    private var sortedShots: [Shot] {
        shots.sorted { lhs, rhs in
            let leftIndex = lhs.orderIndex ?? Int.max
            let rightIndex = rhs.orderIndex ?? Int.max
            if leftIndex == rightIndex {
                return lhs.id < rhs.id
            }
            return leftIndex < rightIndex
        }
    }

    private var leftPaneContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                StoryboardPanel(
                    scenes: scenes,
                    onGenerateStoryboard: onGenerateStoryboard,
                    onReviseScene: onReviseScene
                )
                CharacterPanel(
                    characters: characters,
                    newCharacterName: $newCharacterName,
                    newCharacterDescription: $newCharacterDescription,
                    onCreateCharacter: onCreateCharacter,
                    onTrainCharacter: onTrainCharacter,
                    showTooltips: showTooltips
                )
            }
            .padding(CinefuseTokens.Spacing.s)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private var rightPaneContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ShotsPanel(
                    shots: shots,
                    characterOptions: characters,
                    shotPromptDraft: $shotPromptDraft,
                    shotModelTierDraft: $shotModelTierDraft,
                    selectedCharacterLockId: $selectedCharacterLockId,
                    quotedShotCost: quotedShotCost,
                    onQuote: onQuote,
                    onCreateShot: onCreateShot,
                    onGenerateShot: onGenerateShot,
                    showTooltips: showTooltips
                )
                SectionCard(
                    title: "Export",
//                    subtitle: "Render the current timeline order into a combined output."
                ) {
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        HStack(spacing: CinefuseTokens.Spacing.s) {
                            Picker("Resolution", selection: $exportResolution) {
                                Text("1080p").tag("1080p")
                                Text("4K").tag("4k")
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 110)
                            .tooltip("Choose final output resolution", enabled: showTooltips)
                            
                            Picker("Transitions", selection: $transitionStyle) {
                                Text("Crossfade").tag("crossfade")
                                Text("Dip to Black").tag("dip_to_black")
                                Text("Hard Cut").tag("cut")
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 140)
                            .tooltip("Choose timeline transition style", enabled: showTooltips)
                        }
                        
                        HStack(spacing: 5) {
                            Toggle("Captions", isOn: $exportCaptionsEnabled)
                                .toggleStyle(.switch)
                                .tooltip("Bake captions into stitched/exported output", enabled: showTooltips).frame(width: 150)
                        }.padding(CinefuseTokens.Spacing.s)
                        
                        HStack(spacing: 5) {
                            Toggle("Archive", isOn: $exportIncludeArchive)
                                .toggleStyle(.switch)
                                .tooltip("Create a restorable project archive bundle", enabled: showTooltips).frame(width: 150)
                        }.padding(CinefuseTokens.Spacing.s)
                        
                        HStack(spacing: CinefuseTokens.Spacing.s) {
                            
                            Picker("Publish", selection: $exportPublishTarget) {
                                Text("None").tag("none")
                                Text("Pubfuse").tag("pubfuse")
                                Text("YouTube (soon)").tag("youtube")
                                Text("Vimeo (soon)").tag("vimeo")
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 90)
                            .tooltip("Choose where to publish after export", enabled: showTooltips)
                        }
                        HStack(spacing: 5) {
                            Button {
                                // Placeholder: YouTube OAuth wiring lands in a future milestone.
                            } label: {
                                Label("Connect YouTube", systemImage: "play.rectangle")
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(true)
                            .tooltip("YouTube publish integration is coming soon", enabled: showTooltips)
                        }
                        HStack(spacing: 5) {
                            
                            Button {
                                // Placeholder: Vimeo OAuth wiring lands in a future milestone.
                            } label: {
                                Label("Connect Vimeo", systemImage: "video.badge.plus")
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(true)
                            .tooltip("Vimeo publish integration is coming soon", enabled: showTooltips)
//                            Spacer()
                        }
                        if exportPublishTarget == "youtube" || exportPublishTarget == "vimeo" {
                            Text("Selected publish target is not live yet. Export continues without auto-publish.")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        }
                        HStack(spacing: 5) {
                            Button("Preview Stitch", action: onPreviewStitch)
                                .tooltip("Build a lightweight stitched preview", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                            Button("Transitions", action: onApplyTransitions)
                                .tooltip("Apply transitions between adjacent shots", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                            
                        }
                        HStack(spacing: 5) {
                            Button("Color Match", action: onColorMatch)
                                .tooltip("Reduce color mismatch across shot cuts", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                            Button("Bake Captions", action: onBakeCaptions)
                                .tooltip("Render timeline captions into video output", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                        }
                        HStack(spacing: 5) {
                            
                            Button("Normalize Loudness", action: onNormalizeLoudness)
                                .tooltip("Normalize mix output loudness for playback", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                            Button("Final Stitch", action: onFinalStitch)
                                .tooltip("Run full stitch pass before export", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                        }
                        HStack(spacing: 5) {
                            Button {
                                onExportFinal()
                            } label: {
                                Label("Export Combined", systemImage: "square.and.arrow.up")
                            }
                            .tooltip("Render and export the current timeline", enabled: showTooltips)
                                .buttonStyle(PrimaryActionButtonStyle())
                        }.padding(CinefuseTokens.Spacing.s)
                    }
                }.padding(CinefuseTokens.Spacing.s)
                    
            }
            .padding(CinefuseTokens.Spacing.s)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private func sidePaneContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large))
            .overlay(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                    .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
            )
    }

    private func paneLayout(totalWidth: Double) -> (left: Double, right: Double) {
        let minCenter = Double(CinefuseTokens.Control.minCenterPreviewWidth)
        let left = showLeftPane
            ? min(max(leftPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)), Double(CinefuseTokens.Control.maxSidePanelWidth))
            : 0
        let right = showRightPane
            ? min(max(rightPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)), Double(CinefuseTokens.Control.maxSidePanelWidth))
            : 0
        let handles = (showLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (showRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + Double(CinefuseTokens.Control.layoutHandleReserve)
        let availableForSides = max(totalWidth - minCenter - handles, 0)
        if !showLeftPane && !showRightPane {
            return (0, 0)
        }
        if !showLeftPane {
            return (0, min(right, availableForSides))
        }
        if !showRightPane {
            return (min(left, availableForSides), 0)
        }

        let minPane = Double(CinefuseTokens.Control.minSidePanelWidth)
        if availableForSides <= minPane {
            return (availableForSides, 0)
        }
        if availableForSides <= (minPane * 2) {
            return (minPane, max(0, availableForSides - minPane))
        }

        let sideTotal = left + right
        if sideTotal <= availableForSides || sideTotal == 0 {
            return (left, right)
        }
        let scale = availableForSides / sideTotal
        return (max(minPane, left * scale), max(minPane, right * scale))
    }

    private func clampedLeftPaneWidth(_ width: Double, totalWidth: Double, opposingPaneWidth: Double) -> Double {
        let minPane = Double(CinefuseTokens.Control.minSidePanelWidth)
        let maxPane = Double(CinefuseTokens.Control.maxSidePanelWidth)
        let minCenter = Double(CinefuseTokens.Control.minCenterPreviewWidth)
        let reservedHandles = (showLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (showRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + Double(CinefuseTokens.Control.layoutHandleReserve)
        let maxByCenter = max(totalWidth - minCenter - reservedHandles - opposingPaneWidth, minPane)
        return min(max(width, minPane), min(maxPane, maxByCenter))
    }

    private func clampedRightPaneWidth(_ width: Double, totalWidth: Double, opposingPaneWidth: Double) -> Double {
        let minPane = Double(CinefuseTokens.Control.minSidePanelWidth)
        let maxPane = Double(CinefuseTokens.Control.maxSidePanelWidth)
        let minCenter = Double(CinefuseTokens.Control.minCenterPreviewWidth)
        let reservedHandles = (showLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (showRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + Double(CinefuseTokens.Control.layoutHandleReserve)
        let maxByCenter = max(totalWidth - minCenter - reservedHandles - opposingPaneWidth, minPane)
        return min(max(width, minPane), min(maxPane, maxByCenter))
    }

    private func clampedBottomPaneHeight(_ height: Double, totalHeight: Double) -> Double {
        let minTopWorkspaceHeight = Double(CinefuseTokens.Control.minTopWorkspaceHeight)
        let bottomHandleHeight = Double(CinefuseTokens.Control.splitterHitArea)
        let maxHeight = max(0, totalHeight - minTopWorkspaceHeight - bottomHandleHeight)
        if maxHeight >= Double(CinefuseTokens.Control.minBottomPanelHeight) {
            return min(max(height, Double(CinefuseTokens.Control.minBottomPanelHeight)), maxHeight)
        }
        return maxHeight
    }

    private func sanitizePersistedLayout() {
        leftPaneWidth = min(
            max(leftPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)),
            Double(CinefuseTokens.Control.maxSidePanelWidth)
        )
        rightPaneWidth = min(
            max(rightPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)),
            Double(CinefuseTokens.Control.maxSidePanelWidth)
        )
        bottomPaneHeight = max(bottomPaneHeight, Double(CinefuseTokens.Control.minBottomPanelHeight))
    }

    private func header(project: Project) -> some View {
        HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text(project.title)
                    .font(CinefuseTokens.Typography.sectionTitle)
                Text("Project ID: \(project.id) · \(shots.count) clips · \(audioTracks.count) tracks")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            Spacer(minLength: CinefuseTokens.Spacing.s)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CinefuseTokens.Spacing.xs) {
                    Button {
                        onCloseProject()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                        .buttonStyle(SecondaryActionButtonStyle())
                    Button(role: .destructive) {
                        onDeleteProject()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                        .buttonStyle(DestructiveActionButtonStyle())
                }
                VStack(alignment: .trailing, spacing: CinefuseTokens.Spacing.xs) {
                    Button {
                        onCloseProject()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    Button(role: .destructive) {
                        onDeleteProject()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(DestructiveActionButtonStyle())
                }
            }
        }
        .padding(CinefuseTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                        .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                )
        )
    }
}

enum EditorWorkspacePreset: String, CaseIterable, Identifiable {
    case editing
    case audio
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editing: return "Edit"
        case .audio: return "Audio"
        case .review: return "Review"
        }
    }
}

enum APIServerMode: String, CaseIterable, Identifiable {
    case local
    case production
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local"
        case .production: return "Production"
        case .custom: return "Custom URL"
        }
    }
}

struct HorizontalTimelineTrack: View {
    let shots: [Shot]
    @Binding var selectedShotId: String?
    let onMoveShot: (IndexSet, Int) -> Void
    let showTooltips: Bool
    let themePalette: CinefuseTokens.ThemePalette
    @State private var orderedShots: [Shot] = []
    @State private var draggingShotId: String?
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var hiddenShotIds: Set<String> = []
    @State private var trimByShotId: [String: ClosedRange<Double>] = [:]

    var body: some View {
        SectionCard(
            title: "Timeline",
//            subtitle: "Left-to-right playback order. Select a clip to cue preview."
        ) {
            if visibleShots.isEmpty {
                EmptyStateCard(
                    title: "No clips in timeline",
                    message: "Create or generate shots, then reorder them in this track."
                )
            } else {
                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                    TimelineRulerView(
                        shots: visibleShots,
                        trimByShotId: trimByShotId,
                        palette: themePalette
                    )
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: CinefuseTokens.Spacing.s) {
                            ForEach(Array(visibleShots.enumerated()), id: \.element.id) { index, shot in
                                TimelineClipCard(
                                    shot: shot,
                                    index: index,
                                    trimRange: trimByShotId[shot.id],
                                    isSelected: selectedShotId == shot.id,
                                    canMoveLeft: index > 0,
                                    canMoveRight: index < (visibleShots.count - 1),
                                    onSelect: { selectedShotId = shot.id },
                                    onMoveLeft: {
                                        commitMove(from: index, to: index - 1)
                                        selectedShotId = shot.id
                                    },
                                    onMoveRight: {
                                        commitMove(from: index, to: index + 1)
                                        selectedShotId = shot.id
                                    },
                                    onDuplicate: { duplicateShot(shot.id) },
                                    onDelete: { deleteShot(shot.id) },
                                    onToggleHidden: { toggleHidden(shot.id) },
                                    onTrimLeading: { adjustTrimLeading(for: shot.id, amount: 1) },
                                    onTrimTrailing: { adjustTrimTrailing(for: shot.id, amount: 1) },
                                    showTooltips: showTooltips,
                                    isDragging: draggingShotId == shot.id,
                                    onDragStarted: {
                                        draggingShotId = shot.id
                                        dragSourceIndex = index
                                    }
                                )
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: TimelineClipDropDelegate(
                                        destinationShot: shot,
                                        shots: visibleShots,
                                        draggingShotId: $draggingShotId,
                                        selectedShotId: $selectedShotId,
                                        onPreviewMove: previewMove(from:to:),
                                        onDropTarget: { dragTargetIndex = $0 },
                                        onDropCompleted: commitDraggedMove
                                    )
                                )
                            }
                        }
                        .padding(.vertical, CinefuseTokens.Spacing.xxs)
                    }
                    .frame(height: 136)
                }
                .padding(CinefuseTokens.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                        .fill(themePalette.timelineBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .stroke(themePalette.timelineBevelTop, lineWidth: 1)
                        )
                        .shadow(color: themePalette.timelineBevelBottom.opacity(0.35), radius: 8, x: 0, y: 4)
                )
            }
        }
        .onAppear {
            syncDisplayedShots()
        }
        .onChange(of: shots.map(\.id).joined(separator: "|")) { _, _ in
            syncDisplayedShots()
        }
    }

    private var displayedShots: [Shot] {
        orderedShots.isEmpty ? shots : orderedShots
    }

    private var visibleShots: [Shot] {
        displayedShots.filter { !hiddenShotIds.contains($0.id) }
    }

    private func syncDisplayedShots() {
        orderedShots = shots
        hiddenShotIds = hiddenShotIds.intersection(Set(shots.map(\.id)))
        trimByShotId = trimByShotId.filter { key, _ in shots.contains(where: { $0.id == key }) }
    }

    private func commitMove(from source: Int, to destination: Int) {
        moveLocally(from: source, to: destination)
        persistMove(from: source, to: destination)
    }

    private func previewMove(from source: Int, to destination: Int) {
        moveLocally(from: source, to: destination)
    }

    private func moveLocally(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0,
              source < displayedShots.count,
              destination >= 0,
              destination < displayedShots.count
        else { return }

        var updated = displayedShots
        let moving = updated.remove(at: source)
        updated.insert(moving, at: destination)
        orderedShots = updated
    }

    private func persistMove(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0,
              destination >= 0
        else { return }
        onMoveShot(IndexSet(integer: source), source < destination ? destination + 1 : destination)
    }

    private func commitDraggedMove() {
        defer {
            dragSourceIndex = nil
            dragTargetIndex = nil
        }
        guard let source = dragSourceIndex,
              let destination = dragTargetIndex,
              source != destination
        else { return }
        persistMove(from: source, to: destination)
    }

    private func duplicateShot(_ shotId: String) {
        guard let index = displayedShots.firstIndex(where: { $0.id == shotId }) else { return }
        let source = displayedShots[index]
        let duplicate = Shot(
            id: "local-\(UUID().uuidString)",
            projectId: source.projectId,
            prompt: source.prompt,
            modelTier: source.modelTier,
            status: source.status,
            clipUrl: source.clipUrl,
            orderIndex: source.orderIndex,
            durationSec: source.durationSec,
            thumbnailUrl: source.thumbnailUrl,
            audioRefs: source.audioRefs,
            characterLocks: source.characterLocks
        )
        var updated = displayedShots
        updated.insert(duplicate, at: min(index + 1, updated.count))
        orderedShots = updated
    }

    private func deleteShot(_ shotId: String) {
        orderedShots.removeAll { $0.id == shotId }
        hiddenShotIds.remove(shotId)
        trimByShotId.removeValue(forKey: shotId)
        if selectedShotId == shotId {
            selectedShotId = visibleShots.first?.id
        }
    }

    private func toggleHidden(_ shotId: String) {
        if hiddenShotIds.contains(shotId) {
            hiddenShotIds.remove(shotId)
        } else {
            hiddenShotIds.insert(shotId)
            if selectedShotId == shotId {
                selectedShotId = visibleShots.first(where: { $0.id != shotId })?.id
            }
        }
    }

    private func adjustTrimLeading(for shotId: String, amount: Double) {
        guard let shot = displayedShots.first(where: { $0.id == shotId }) else { return }
        let duration = max(Double(shot.durationSec ?? 5), 1)
        let current = trimByShotId[shotId] ?? (0...duration)
        let newLower = min(max(current.lowerBound + amount, 0), current.upperBound - 0.5)
        trimByShotId[shotId] = newLower...current.upperBound
    }

    private func adjustTrimTrailing(for shotId: String, amount: Double) {
        guard let shot = displayedShots.first(where: { $0.id == shotId }) else { return }
        let duration = max(Double(shot.durationSec ?? 5), 1)
        let current = trimByShotId[shotId] ?? (0...duration)
        let newUpper = max(min(current.upperBound - amount, duration), current.lowerBound + 0.5)
        trimByShotId[shotId] = current.lowerBound...newUpper
    }
}

struct TimelineClipCard: View {
    let shot: Shot
    let index: Int
    let trimRange: ClosedRange<Double>?
    let isSelected: Bool
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let onSelect: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onToggleHidden: () -> Void
    let onTrimLeading: () -> Void
    let onTrimTrailing: () -> Void
    let showTooltips: Bool
    let isDragging: Bool
    let onDragStarted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            HStack {
                Text("#\(index + 1)")
                    .font(CinefuseTokens.Typography.caption.weight(.semibold))
                Spacer()
                StatusBadge(status: shot.status)
            }
            Text(shot.prompt.isEmpty ? "Untitled clip" : shot.prompt)
                .font(CinefuseTokens.Typography.label)
                .lineLimit(2)
            Text("\(shot.modelTier.capitalized) · \(shot.durationSec ?? 0)s")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            if let trimRange {
                Text("Trim \(trimRange.lowerBound.formatted(.number.precision(.fractionLength(0))))s-\(trimRange.upperBound.formatted(.number.precision(.fractionLength(0))))s")
                    .font(CinefuseTokens.Typography.micro)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            HStack(spacing: CinefuseTokens.Spacing.xxs) {
                IconCommandButton(
                    systemName: "arrow.left",
                    label: "Move clip left",
                    action: onMoveLeft,
                    tooltipEnabled: showTooltips
                )
                .disabled(!canMoveLeft)

                IconCommandButton(
                    systemName: "arrow.right",
                    label: "Move clip right",
                    action: onMoveRight,
                    tooltipEnabled: showTooltips
                )
                .disabled(!canMoveRight)
            }
        }
        .padding(CinefuseTokens.Spacing.s)
        .frame(
            width: CinefuseTokens.Control.timelineCardWidth,
            height: CinefuseTokens.Control.timelineCardHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                        .stroke(
                            isSelected ? CinefuseTokens.ColorRole.accent : CinefuseTokens.ColorRole.borderSubtle,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .opacity(isDragging ? 0.75 : 1)
        .onTapGesture(perform: onSelect)
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: NSString(string: shot.id))
        }
        .contextMenu {
            Button {
                onTrimLeading()
            } label: {
                Label("Trim Start +1s", systemImage: "scissors")
            }
            Button {
                onTrimTrailing()
            } label: {
                Label("Trim End -1s", systemImage: "scissors.badge.ellipsis")
            }
            Divider()
            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                onToggleHidden()
            } label: {
                Label("Hide/Unhide", systemImage: "eye.slash")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct TimelineClipDropDelegate: DropDelegate {
    let destinationShot: Shot
    let shots: [Shot]
    @Binding var draggingShotId: String?
    @Binding var selectedShotId: String?
    let onPreviewMove: (Int, Int) -> Void
    let onDropTarget: (Int) -> Void
    let onDropCompleted: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingShotId,
              draggingShotId != destinationShot.id,
              let fromIndex = shots.firstIndex(where: { $0.id == draggingShotId }),
              let toIndex = shots.firstIndex(where: { $0.id == destinationShot.id })
        else { return }
        onPreviewMove(fromIndex, toIndex)
        onDropTarget(toIndex)
        selectedShotId = draggingShotId
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingShotId = nil
        onDropCompleted()
        return true
    }
}

struct EditorPreviewPanel: View {
    let shots: [Shot]
    @Binding var selectedShotId: String?
    let showTooltips: Bool
    @State private var queuePlayer = AVQueuePlayer()

    private var playableShots: [Shot] {
        shots.filter { $0.clipUrl != nil }
    }

    private var selectedShot: Shot? {
        if let selectedShotId {
            return playableShots.first(where: { $0.id == selectedShotId })
        }
        return playableShots.first
    }

    var body: some View {
        SectionCard(
            title: "Preview",
//            subtitle: "Playback queue follows timeline order."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                if playableShots.isEmpty {
                    EmptyStateCard(
                        title: "No playable clips yet",
                        message: "Generate clips to preview timeline playback."
                    )
                } else {
                    VideoPlayer(player: queuePlayer)
                        .frame(minHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))

                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        IconCommandButton(
                            systemName: "play.fill",
                            label: "Play sequence",
                            action: { playSequence(fromSelected: true) },
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: "play.square.fill",
                            label: "Play selected clip",
                            action: { playSelectedOnly() },
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: "stop.fill",
                            label: "Stop playback",
                            action: {
                                queuePlayer.pause()
                                queuePlayer.removeAllItems()
                            },
                            tooltipEnabled: showTooltips
                        )

                        Spacer()
                        Text("Queue: \(playableShots.count) clips")
                            .font(CinefuseTokens.Typography.caption)
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            if selectedShotId == nil {
                selectedShotId = playableShots.first?.id
            }
            playSelectedOnly()
        }
        .onChange(of: shots.map { "\($0.id):\($0.clipUrl ?? "")" }.joined(separator: "|")) { _, _ in
            if selectedShotId == nil {
                selectedShotId = playableShots.first?.id
            }
            playSelectedOnly()
        }
    }

    private func playSequence(fromSelected: Bool) {
        let sequence: [Shot]
        if fromSelected, let selected = selectedShot, let selectedIndex = playableShots.firstIndex(where: { $0.id == selected.id }) {
            sequence = Array(playableShots[selectedIndex...])
        } else {
            sequence = playableShots
        }
        let items = sequence.compactMap { shot -> AVPlayerItem? in
            guard let clip = shot.clipUrl, let url = URL(string: clip) else { return nil }
            return AVPlayerItem(url: url)
        }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        for item in items {
            queuePlayer.insert(item, after: nil)
        }
        queuePlayer.play()
    }

    private func playSelectedOnly() {
        guard let selected = selectedShot,
              let clip = selected.clipUrl,
              let url = URL(string: clip)
        else {
            return
        }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        queuePlayer.insert(AVPlayerItem(url: url), after: nil)
        queuePlayer.play()
    }
}

struct VerticalPanelHandle: View {
    let onDrag: (Double) -> Void
    @State private var lastTranslation: Double = 0

    var body: some View {
        Rectangle()
            .fill(CinefuseTokens.ColorRole.borderSubtle)
            .frame(width: CinefuseTokens.Control.splitterThickness)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let next = Double(value.translation.width)
                        onDrag(next - lastTranslation)
                        lastTranslation = next
                    }
                    .onEnded { value in
                        let next = Double(value.translation.width)
                        onDrag(next - lastTranslation)
                        lastTranslation = 0
                    }
            )
            .padding(.horizontal, (CinefuseTokens.Control.splitterHitArea - CinefuseTokens.Control.splitterThickness) / 2)
    }
}

struct HorizontalPanelHandle: View {
    let onDrag: (Double) -> Void
    @State private var lastTranslation: Double = 0

    var body: some View {
        Rectangle()
            .fill(CinefuseTokens.ColorRole.borderSubtle)
            .frame(height: CinefuseTokens.Control.splitterThickness)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let next = Double(value.translation.height)
                        onDrag(next - lastTranslation)
                        lastTranslation = next
                    }
                    .onEnded { value in
                        let next = Double(value.translation.height)
                        onDrag(next - lastTranslation)
                        lastTranslation = 0
                    }
            )
            .padding(.vertical, (CinefuseTokens.Control.splitterHitArea - CinefuseTokens.Control.splitterThickness) / 2)
    }
}

struct StoryboardPanel: View {
    let scenes: [StoryScene]
    let onGenerateStoryboard: () -> Void
    let onReviseScene: (StoryScene, String) -> Void

    @State private var revisionDraftBySceneId: [String: String] = [:]

    var body: some View {
        SectionCard(
            title: "Storyboard",
//            subtitle: "Generate and revise scene beats before creating detailed shots."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                Button("Generate Beat Sheet") {
                    onGenerateStoryboard()
                }
                .buttonStyle(PrimaryActionButtonStyle())

                if scenes.isEmpty {
                    EmptyStateCard(
                        title: "No scenes generated",
                        message: "Generate a beat sheet to create the storyboard for this project."
                    )
                } else {
                    ForEach(scenes) { scene in
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            Text("Scene \(scene.orderIndex + 1): \(scene.title)")
                                .font(CinefuseTokens.Typography.cardTitle)
                            Text(scene.description)
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

                            TextField(
                                "Revise this scene beat",
                                text: Binding(
                                    get: { revisionDraftBySceneId[scene.id] ?? "" },
                                    set: { revisionDraftBySceneId[scene.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Save Revision") {
                                let revision = (revisionDraftBySceneId[scene.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !revision.isEmpty else { return }
                                onReviseScene(scene, revision)
                                revisionDraftBySceneId[scene.id] = ""
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                        }
                        .padding(CinefuseTokens.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                        )
                    }
                }
            }
        }
    }
}

struct CharacterPanel: View {
    let characters: [CharacterProfile]
    @Binding var newCharacterName: String
    @Binding var newCharacterDescription: String
    let onCreateCharacter: () -> Void
    let onTrainCharacter: (String) -> Void
    let showTooltips: Bool

    var body: some View {
        SectionCard(
            title: "Characters",
            subtitle: "Create hero or supporting characters, then train and lock them to shots."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        TextField("Character name", text: $newCharacterName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $newCharacterDescription)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            onCreateCharacter()
                        } label: {
                            Label("Add Character", systemImage: "person.badge.plus")
                        }
                        .tooltip("Create a new character profile", enabled: showTooltips)
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        TextField("Character name", text: $newCharacterName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $newCharacterDescription)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            onCreateCharacter()
                        } label: {
                            Label("Add Character", systemImage: "person.badge.plus")
                        }
                        .tooltip("Create a new character profile", enabled: showTooltips)
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                }

                if characters.isEmpty {
                    EmptyStateCard(
                        title: "No characters created",
                        message: "Add a character and train it before locking to key shots."
                    )
                } else {
                    ForEach(characters) { character in
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: CinefuseTokens.Spacing.s) {
                                Text(character.name)
                                    .font(CinefuseTokens.Typography.cardTitle)
                                    .lineLimit(2)
                                    .layoutPriority(1)
                                Spacer(minLength: CinefuseTokens.Spacing.s)
                                StatusBadge(status: character.status)
                            }
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                Text(character.description)
                                    .font(CinefuseTokens.Typography.caption)
                                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                if let score = character.consistencyScore {
                                    let pct = Int(score * 100)
                                    let thresholdPct = Int((character.consistencyThreshold ?? 0.8) * 100)
                                    Text("Consistency: \(pct)% (threshold \(thresholdPct)%)")
                                        .font(CinefuseTokens.Typography.caption)
                                        .foregroundStyle((character.consistencyPassed ?? false)
                                            ? CinefuseTokens.ColorRole.success
                                            : CinefuseTokens.ColorRole.warning)
                                }
                            }
                            if character.status != "trained" {
                                Button {
                                    onTrainCharacter(character.id)
                                } label: {
                                    Label("Train", systemImage: "figure.strengthtraining.traditional")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .tooltip("Train this character for consistency", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                            }
                        }
                        .padding(CinefuseTokens.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                        )
                    }
                }
            }
        }
    }
}

struct ShotsPanel: View {
    let shots: [Shot]
    let characterOptions: [CharacterProfile]
    @Binding var shotPromptDraft: String
    @Binding var shotModelTierDraft: String
    @Binding var selectedCharacterLockId: String
    let quotedShotCost: ShotQuote?
    let onQuote: () -> Void
    let onCreateShot: () -> Void
    let onGenerateShot: (String) -> Void
    let showTooltips: Bool

    private let inFlightStatuses: Set<String> = ["queued", "generating", "running"]

    var body: some View {
        SectionCard(
            title: "Shots",
            subtitle: "1: Draft shot 2: Quote cost 3: Generate 4: Review"
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                        TextField("Describe the shot action or camera movement", text: $shotPromptDraft)
                            .textFieldStyle(.roundedBorder)
                        Picker("Tier", selection: $shotModelTierDraft) {
                            Text("Budget").tag("budget")
                            Text("Standard").tag("standard")
                            Text("Premium").tag("premium")
                        }
                        .pickerStyle(.menu)
                        .frame(width: CinefuseTokens.Control.primaryPickerWidth)
                        Picker("Character Lock", selection: $selectedCharacterLockId) {
                            Text("No lock").tag("")
                            ForEach(characterOptions) { character in
                                Text(character.name).tag(character.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: CinefuseTokens.Control.secondaryPickerWidth)
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            Button {
                                onQuote()
                            } label: {
                                Label("Quote Cost", systemImage: "tag")
                            }
                            .tooltip("Estimate sparks before generation", enabled: showTooltips)
                            .buttonStyle(SecondaryActionButtonStyle())
                            Button {
                                onCreateShot()
                            } label: {
                                Label("Create Shot", systemImage: "plus.rectangle.on.rectangle")
                            }
                            .tooltip("Create shot draft in timeline", enabled: showTooltips)
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                    }
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        TextField("Describe the shot action or camera movement", text: $shotPromptDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                            Picker("Tier", selection: $shotModelTierDraft) {
                                Text("Budget").tag("budget")
                                Text("Standard").tag("standard")
                                Text("Premium").tag("premium")
                            }
                            .pickerStyle(.menu)
                            .frame(width: CinefuseTokens.Control.primaryPickerWidth)
                            Picker("Character Lock", selection: $selectedCharacterLockId) {
                                Text("No lock").tag("")
                                ForEach(characterOptions) { character in
                                    Text(character.name).tag(character.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: CinefuseTokens.Control.secondaryPickerWidth)
                        }
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            Button {
                                onQuote()
                            } label: {
                                Label("Quote Cost", systemImage: "tag")
                            }
                            .tooltip("Estimate sparks before generation", enabled: showTooltips)
                            .buttonStyle(SecondaryActionButtonStyle())
                            Button {
                                onCreateShot()
                            } label: {
                                Label("Create Shot", systemImage: "plus.rectangle.on.rectangle")
                            }
                            .tooltip("Create shot draft in timeline", enabled: showTooltips)
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                    }
                }

                if let quotedShotCost {
                    let durationText = quotedShotCost.estimatedDurationSec.map { "~\($0)s" } ?? "~5s"
                    Text("Estimated: \(quotedShotCost.sparksCost) Sparks · \(quotedShotCost.modelId) · \(durationText)")
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }

                if shots.isEmpty {
                    EmptyStateCard(
                        title: "No shots drafted",
                        message: "Create your first shot above, then quote and generate."
                    )
                } else {
                    ForEach(shots) { shot in
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                Text(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                    .font(CinefuseTokens.Typography.body)
                                    .lineLimit(2)
                                    .layoutPriority(1)
                                Text(shot.modelTier.capitalized)
                                    .font(CinefuseTokens.Typography.caption)
                                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                StatusBadge(status: shot.status)
                                if let lock = shot.characterLocks?.first, !lock.isEmpty {
                                    Text("Character lock")
                                        .font(CinefuseTokens.Typography.caption)
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                        .tooltip(lock, enabled: showTooltips)
                                }
                                if let clipUrl = shot.clipUrl {
                                    Text("Output ready")
                                        .font(CinefuseTokens.Typography.caption)
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                        .tooltip(clipUrl, enabled: showTooltips)
                                }
                            }
                            Button {
                                onGenerateShot(shot.id)
                            } label: {
                                Label("Generate", systemImage: "video.badge.plus")
                                    .font(CinefuseTokens.Typography.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .tooltip("Generate final clip for this shot", enabled: showTooltips)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(inFlightStatuses.contains(shot.status) || shot.status == "ready")
                        }
                        .padding(CinefuseTokens.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                        )
                    }
                }
            }
        }.padding(CinefuseTokens.Spacing.s)
    }
}

struct JobsPanel: View {
    let jobs: [Job]
    @Binding var jobKindDraft: String
    let onCreateJob: () -> Void
    let showTooltips: Bool

    var body: some View {
        SectionCard(
            title: "Jobs - Track render",
//            subtitle: "Track render and processing work for this project."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        Picker("Job type", selection: $jobKindDraft) {
                            Text("Clip").tag("clip")
                            Text("Audio").tag("audio")
                            Text("Stitch").tag("stitch")
                            Text("Export").tag("export")
                        }
                        .pickerStyle(.menu)
                        .frame(width: CinefuseTokens.Control.jobPickerWidth)
                        Button {
                            onCreateJob()
                        } label: {
                            Label("Create Job", systemImage: "hammer")
                        }
                        .tooltip("Queue a manual job", enabled: showTooltips)
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        Picker("Job type", selection: $jobKindDraft) {
                            Text("Clip").tag("clip")
                            Text("Audio").tag("audio")
                            Text("Stitch").tag("stitch")
                            Text("Export").tag("export")
                        }
                        .pickerStyle(.menu)
                        .frame(width: CinefuseTokens.Control.secondaryPickerWidth)
                        Button {
                            onCreateJob()
                        } label: {
                            Label("Create Job", systemImage: "hammer")
                        }
                        .tooltip("Queue a manual job", enabled: showTooltips)
                        .buttonStyle(PrimaryActionButtonStyle())
                    }
                }

                if jobs.isEmpty {
                    EmptyStateCard(
                        title: "No jobs yet",
                        message: "Jobs appear when you queue rendering, audio, stitch, or export tasks."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                            ForEach(jobs) { job in
                                HStack(spacing: CinefuseTokens.Spacing.s) {
                                    Text(job.kind.capitalized)
                                        .font(CinefuseTokens.Typography.body)
                                    StatusBadge(status: job.status)
                                    Spacer()
                                    Text("Cost to us: \(job.costToUsCents)c")
                                        .font(CinefuseTokens.Typography.caption)
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                }
                                .padding(CinefuseTokens.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                        .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}

enum TimelineThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case ivorySlate
    case carbonGlass
    case cobaltPulse
    case sandstone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .ivorySlate: return "Ivory Slate"
        case .carbonGlass: return "Carbon Glass"
        case .cobaltPulse: return "Cobalt Pulse"
        case .sandstone: return "Sandstone"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .ivorySlate: return .light
        case .sandstone: return .light
        case .carbonGlass: return .dark
        case .cobaltPulse: return .dark
        }
    }

    var palette: CinefuseTokens.ThemePalette {
        switch self {
        case .system: return CinefuseTokens.Theme.system
        case .light: return CinefuseTokens.Theme.light
        case .dark: return CinefuseTokens.Theme.dark
        case .ivorySlate: return CinefuseTokens.Theme.ivorySlate
        case .carbonGlass: return CinefuseTokens.Theme.carbonGlass
        case .cobaltPulse: return CinefuseTokens.Theme.cobaltPulse
        case .sandstone: return CinefuseTokens.Theme.sandstone
        }
    }
}

struct TimelineShotBoundary {
    let shotId: String
    let startMs: Int
    let endMs: Int
}

enum AudioTrackSyncMode: String, CaseIterable, Identifiable {
    case locked
    case freeform

    var id: String { rawValue }

    var label: String {
        switch self {
        case .locked: return "Locked"
        case .freeform: return "Freeform"
        }
    }
}

struct TimelinePanel: View {
    let shots: [Shot]
    let audioTracks: [AudioTrack]
    @Binding var audioTrackTitleDraft: String
    @Binding var themeMode: TimelineThemeMode
    let onMoveShot: (IndexSet, Int) -> Void
    let onGenerateDialogue: () -> Void
    let onGenerateScore: () -> Void
    let onExport: () -> Void

    @State private var isShowingVideoPreview = false
    @State private var selectedVideoURL: URL?

    var body: some View {
        SectionCard(
            title: "Timeline",
            subtitle: "Drag shots to reorder, preview media, and generate dialogue/score lanes."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    Picker("Theme", selection: $themeMode) {
                        ForEach(TimelineThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: CinefuseTokens.Control.jobPickerWidth)
                    TextField("Audio title", text: $audioTrackTitleDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Generate Dialogue", action: onGenerateDialogue)
                        .buttonStyle(SecondaryActionButtonStyle())
                    Button("Generate Score", action: onGenerateScore)
                        .buttonStyle(SecondaryActionButtonStyle())
                    Spacer()
                    Button("Export Combined", action: onExport)
                        .buttonStyle(PrimaryActionButtonStyle())
                }

                if shots.isEmpty {
                    EmptyStateCard(
                        title: "Timeline is empty",
                        message: "Create clips in the shots panel, then drag them into narrative order."
                    )
                } else {
                    HStack {
                        Text("Drag to reorder shots")
                            .font(CinefuseTokens.Typography.caption)
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    }
                    List {
                        ForEach(shots) { shot in
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                HStack {
                                    Text(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                        .font(CinefuseTokens.Typography.body)
                                    Spacer()
                                    StatusBadge(status: shot.status)
                                }
                                MediaPreviewRow(
                                    shot: shot,
                                    onPreview: { url in
                                        selectedVideoURL = url
                                        isShowingVideoPreview = true
                                    }
                                )
                            }
                            .padding(.vertical, CinefuseTokens.Spacing.xxs)
                        }
                        .onMove(perform: onMoveShot)
                    }
                    .frame(minHeight: 220, maxHeight: 340)
                }

                AudioLaneView(
                    audioTracks: audioTracks,
                    shotBoundaries: [],
                    syncModes: .constant([:]),
                    themePalette: themeMode.palette
                )
            }
        }
        .sheet(isPresented: $isShowingVideoPreview) {
            if let selectedVideoURL {
                VideoPreviewSheet(videoURL: selectedVideoURL)
            }
        }
    }
}

struct MediaPreviewRow: View {
    let shot: Shot
    let onPreview: (URL) -> Void

    var body: some View {
        HStack(spacing: CinefuseTokens.Spacing.s) {
            if let thumb = shot.thumbnailUrl, let thumbURL = URL(string: thumb) {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                            .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                            .overlay(Image(systemName: "film"))
                    }
                }
                .frame(width: 88, height: 50)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
            } else {
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                    .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                    .frame(width: 88, height: 50)
                    .overlay(Image(systemName: "film"))
            }
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text("Duration: \(shot.durationSec ?? 0)s")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                if let clipUrl = shot.clipUrl, let url = URL(string: clipUrl) {
                    Button("Play Clip") { onPreview(url) }
                        .buttonStyle(SecondaryActionButtonStyle())
                }
            }
            Spacer()
        }
    }
}

struct AudioLaneView: View {
    let audioTracks: [AudioTrack]
    let shotBoundaries: [TimelineShotBoundary]
    @Binding var syncModes: [Int: AudioTrackSyncMode]
    let themePalette: CinefuseTokens.ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
//            Text("Audio Lanes")
//                .font(CinefuseTokens.Typography.timelineHeader)
            if audioTracks.isEmpty {
                Text("No audio tracks generated yet.")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            } else {
                ForEach(audioTracks) { track in
                    let laneMode = syncModes[track.laneIndex] ?? .locked
                    let computedStartMs = laneMode == .locked
                        ? lockedStartMs(for: track)
                        : track.startMs
                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        if let waveform = track.waveformUrl, let waveformURL = URL(string: waveform) {
                            AsyncImage(url: waveformURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                                        .fill(CinefuseTokens.ColorRole.surfacePrimary)
                                        .overlay(Image(systemName: "waveform"))
                                }
                            }
                            .frame(width: 74, height: 40)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                        }
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                            Text("\(track.kind.capitalized): \(track.title)")
                                .font(CinefuseTokens.Typography.label)
                            Text("Lane \(track.laneIndex + 1) • Start \(computedStartMs)ms • \(track.durationMs)ms")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            if laneMode == .locked {
                                Text("Locked to video timeline")
                                    .font(CinefuseTokens.Typography.micro)
                                    .foregroundStyle(themePalette.accent)
                            }
                        }
                        Spacer()
                        Picker("Sync", selection: Binding(
                            get: { syncModes[track.laneIndex] ?? .locked },
                            set: { syncModes[track.laneIndex] = $0 }
                        )) {
                            ForEach(AudioTrackSyncMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        if let sourceUrl = track.sourceUrl, let url = URL(string: sourceUrl) {
                            Link("Play", destination: url)
                                .font(CinefuseTokens.Typography.caption)
                        }
                        StatusBadge(status: track.status)
                    }
                    .padding(CinefuseTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                            .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(laneMode == .locked ? 0.92 : 0.76))
                    )
                }
            }
        }
        .padding(CinefuseTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                .fill(themePalette.timelineBase.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                        .stroke(themePalette.timelineRuler.opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func lockedStartMs(for track: AudioTrack) -> Int {
        guard let shotId = track.shotId,
              let boundary = shotBoundaries.first(where: { $0.shotId == shotId })
        else {
            return track.startMs
        }
        return boundary.startMs
    }
}

struct VideoPreviewSheet: View {
    let videoURL: URL
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            Text("Clip Preview")
                .font(CinefuseTokens.Typography.sectionTitle)
            if let player {
                VideoPlayer(player: player)
                    .frame(minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
            } else {
                ProgressView("Loading video...")
            }
            Text(videoURL.absoluteString)
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
        .padding(CinefuseTokens.Spacing.l)
        .task {
            let player = AVPlayer(url: videoURL)
            self.player = player
            player.play()
        }
    }
}
