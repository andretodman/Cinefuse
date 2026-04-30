import SwiftUI
import UniformTypeIdentifiers
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AVKit)
import AVKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(AVFoundation)
@MainActor
private enum BlueprintReferenceHold {
    static var lastPlayer: AVAudioPlayer?
}
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
#if os(iOS)
        .onAppear(perform: preferLandscapeWindowWhenIOSAppOnMac)
        .onChange(of: model.isAuthenticated) { _, isAuthed in
            if isAuthed {
                preferLandscapeWindowWhenIOSAppOnMac()
            }
        }
#endif
    }

#if os(iOS)
    /// “Designed for iPad” on macOS often opens in portrait; request landscape for a proper desktop aspect ratio.
    private func preferLandscapeWindowWhenIOSAppOnMac() {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
    }
#endif
}

/// Time ruler drawn at **exactly** `contentWidth` so it scrolls and aligns with proportional clip cards below.
struct TimelineRulerStrip: View {
    let totalSeconds: Int
    let contentWidth: CGFloat
    let palette: CinefuseTokens.ThemePalette

    private var secondsTotal: Int {
        max(totalSeconds, 1)
    }

    /// Avoid hundreds of tick views on very long timelines.
    private var majorLabelStride: Int {
        let T = secondsTotal
        if T <= 120 { return 5 }
        if T <= 600 { return 15 }
        if T <= 3600 { return 60 }
        return max(60, T / 14)
    }

    private var minorTickStride: Int {
        if secondsTotal <= 180 { return 1 }
        let step = majorLabelStride / max(1, majorLabelStride / 5)
        return max(1, step)
    }

    var body: some View {
        let W = max(contentWidth, 1)
        let T = CGFloat(secondsTotal)
        let labelReserve: CGFloat = 11
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(palette.timelineRuler.opacity(0.12))
                Canvas { context, canvasSize in
                    let majorH = CinefuseTokens.Control.timelineNotchMajor
                    let minorH = CinefuseTokens.Control.timelineNotchMinor
                    let baseY = canvasSize.height - labelReserve
                    var s = 0
                    while s <= secondsTotal {
                        let x = CGFloat(s) / T * canvasSize.width
                        let isMajor = s % majorLabelStride == 0 || s == secondsTotal
                        let h = isMajor ? majorH : minorH
                        let opacity = isMajor ? 0.85 : 0.45
                        let rect = CGRect(x: x - 0.25, y: baseY - h, width: 1, height: h)
                        context.fill(Path(rect), with: .color(palette.timelineRuler.opacity(opacity)))
                        s += minorTickStride
                    }
                }
                .allowsHitTesting(false)
                .frame(width: size.width, height: size.height)

                ForEach(Array(stride(from: 0, through: secondsTotal, by: majorLabelStride)), id: \.self) { sec in
                    Text("\(sec)s")
                        .font(CinefuseTokens.Typography.nano)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .position(x: CGFloat(sec) / T * size.width + 14, y: size.height - 6)
                }
                if secondsTotal > 0, secondsTotal % majorLabelStride != 0 {
                    Text("\(secondsTotal)s")
                        .font(CinefuseTokens.Typography.nano)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .position(x: CGFloat(secondsTotal) / T * size.width + 14, y: size.height - 6)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(width: W, height: CinefuseTokens.Control.timelineRulerHeight)
        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
    }
}

struct LoginScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage("cinefuse.server.mode") private var apiServerModeRaw = APIServerMode.production.rawValue
    @AppStorage("cinefuse.server.customBaseURL") private var customServerBaseURL = ""
    @AppStorage("cinefuse.auth.demoEmail") private var demoEmail = "tester@pubfuse.com"
    @AppStorage("cinefuse.auth.demoPassword") private var demoPassword = "pubfuseguest"
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var signupUsername = ""
    @State private var signupDisplayName = ""
    @State private var forgotEmail = ""
    @State private var resetTokenFromLink = ""
    @State private var isResetPasswordSheetPresented = false
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
        ProcessInfo.processInfo.environment["CINEFUSE_API_PROD_BASE_URL"] ?? "https://cinefuse.pubfuse.com"
    }

    private var selectedCinefuseBaseURL: String {
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .production {
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
        // Auth is owned by Pubfuse user management; do not infer auth host from Cinefuse API mode.
        // Use explicit override only when intentionally testing a different auth server.
        return "https://www.pubfuse.com"
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
        .onOpenURL { url in
            guard let token = passwordResetToken(from: url), !token.isEmpty else { return }
            resetTokenFromLink = token
            authMode = .forgotPassword
            isResetPasswordSheetPresented = true
            successMessage = "Reset link received. Choose a new password."
            errorMessage = nil
        }
        .sheet(isPresented: $isResetPasswordSheetPresented) {
            ResetPasswordSheet(
                token: resetTokenFromLink,
                authBaseURL: selectedAuthBaseURL,
                cinefuseBaseURL: selectedCinefuseBaseURL
            )
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

    private func passwordResetToken(from url: URL) -> String? {
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""
        let matchesResetRoute = path.contains("/app/reset-password")
            || path.hasSuffix("/reset-password")
            || host == "reset-password"
        guard matchesResetRoute else {
            return nil
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct ResetPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let authBaseURL: String
    let cinefuseBaseURL: String

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Reset Password")
                .font(CinefuseTokens.Typography.screenTitle)

            Text("Set a new password for your Pubfuse account.")
                .font(CinefuseTokens.Typography.body)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

            SecureField("New password", text: $newPassword)
                .textFieldStyle(.roundedBorder)

            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)

            if let successMessage {
                Text(successMessage)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.success)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.danger)
            }

            HStack(spacing: CinefuseTokens.Spacing.s) {
                Button {
                    Task { await submitResetPassword() }
                } label: {
                    Label("Update Password", systemImage: "key.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isSubmitting || token.isEmpty || newPassword.count < 8 || newPassword != confirmPassword)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(CinefuseTokens.Spacing.xl)
        .frame(minWidth: 460)
    }

    private func submitResetPassword() async {
        await MainActor.run {
            isSubmitting = true
            errorMessage = nil
            successMessage = nil
        }
        defer { Task { @MainActor in isSubmitting = false } }

        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = "Reset token is missing."
            }
            return
        }

        guard newPassword.count >= 8 else {
            await MainActor.run {
                errorMessage = "Password must be at least 8 characters."
            }
            return
        }

        guard newPassword == confirmPassword else {
            await MainActor.run {
                errorMessage = "Passwords do not match."
            }
            return
        }

        do {
            try await APIClient(baseURLString: cinefuseBaseURL).resetPubfusePassword(
                authBaseURLString: authBaseURL,
                token: token,
                newPassword: newPassword
            )
            await MainActor.run {
                successMessage = "Password updated. You can now sign in."
                newPassword = ""
                confirmPassword = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Lyrics behavior for `POST .../audio/score` (ElevenLabs Music MCP).
enum ScoreGenerationLyricsMode: String, CaseIterable, Identifiable {
    case instrumental
    case auto
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instrumental: return "Instrumental"
        case .auto: return "Lyrics (auto)"
        case .custom: return "Lyrics (custom)"
        }
    }
}

/// Video vs Audio creation mode: two compact segments; selected side reads depressed into the track.
private struct CreationModeBinarySwitch: View {
    @Binding var creationModeRaw: String

    private var selectedMode: CreationMode {
        CreationMode(rawValue: creationModeRaw) ?? .video
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CreationMode.allCases) { mode in
                let isSelected = selectedMode == mode
                Button {
                    creationModeRaw = mode.rawValue
                } label: {
                    segmentLabel(mode: mode, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: mode))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(CinefuseTokens.ColorRole.borderSubtle.opacity(0.45), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Creation mode")
    }

    @ViewBuilder
    private func segmentLabel(mode: CreationMode, isSelected: Bool) -> some View {
        Text(shortLabel(for: mode))
            .font(CinefuseTokens.Typography.micro)
            .foregroundStyle(
                isSelected
                    ? CinefuseTokens.ColorRole.textPrimary
                    : CinefuseTokens.ColorRole.textSecondary
            )
            .frame(minWidth: 36)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isSelected ? CinefuseTokens.ColorRole.borderSubtle.opacity(0.65) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.22) : .clear,
                radius: 0,
                x: 0,
                y: 1
            )
            .padding(1)
    }

    private func shortLabel(for mode: CreationMode) -> String {
        switch mode {
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }

    private func accessibilityLabel(for mode: CreationMode) -> String {
        switch mode {
        case .video: return "Video creation"
        case .audio: return "Audio creation"
        }
    }
}

struct ProjectWorkspaceScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var titleDraft = ""
    @State private var isCreateProjectSheetPresented = false
    @FocusState private var isCreateProjectTitleFocused: Bool

    @State private var selectedProjectId: String?
    @State private var scenes: [StoryScene] = []
    @State private var characters: [CharacterProfile] = []
    @State private var shots: [Shot] = []
    @State private var audioTracks: [AudioTrack] = []
    @State private var jobs: [Job] = []
    @State private var shotPromptDraft = ""
    /// Local `file://` playback for freshly uploaded sounds (API clip URLs require Bearer; preview uses these copies).
    @State private var shotPlaybackClipURLByShotId: [String: URL] = [:]
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
    @AppStorage("cinefuse.editor.showAudioPanel") private var showAudioPanel = true
    @AppStorage("cinefuse.editor.showJobsPanel") private var showJobsPanel = true
    @AppStorage("cinefuse.editor.swapSidePanes") private var swapSidePanes = false
    @AppStorage("cinefuse.editor.workspacePreset") private var workspacePresetRaw = EditorWorkspacePreset.editing.rawValue
    @AppStorage("cinefuse.editor.creationMode") private var creationModeRaw = CreationMode.video.rawValue
    @State private var soundBlueprints: [SoundBlueprint] = []
    /// Per-shot selected sound blueprint IDs for Generate (audio mode); merged server-side into reference file IDs.
    @State private var selectedSoundBlueprintIdsByShotId: [String: Set<String>] = [:]
    /// Defaults used when creating a sound if no timeline shot is selected (toolbar blueprint row).
    @State private var draftSoundBlueprintIds: Set<String> = []
    /// Per-shot sound origin: `"generated"` (prompt → pipeline) or `"uploaded"` (user file). Not user-editable; set by create/upload flows.
    @State private var shotSoundSourceById: [String: String] = [:]
    @State private var soundTagsDraft = ""
    /// ElevenLabs score (audio workspace): target length in seconds (clamped 3…600 server-side).
    @State private var scoreDurationSeconds: Double = 30
    /// Score generation: instrumental, model-written lyrics, or user lyrics (composition plan).
    @State private var scoreLyricsModeSelection: ScoreGenerationLyricsMode = .instrumental
    @State private var scoreCustomLyricsDraft = ""
    /// Maximizes the center preview column (toolbar icon); clears pop-out window when engaged.
    @State private var isPreviewFullscreen = false
    @State private var jobKindDraft = "clip"
    @State private var isLoadingProjectDetails = false
    @State private var isRefreshingProjectDetails = false
    /// When true, the next `loadSelectedProjectDetails` exit will run another refresh (coalesces concurrent callers).
    @State private var pendingReloadSelectedProjectDetails = false
    @State private var isRefreshingStatusSnapshot = false
    @State private var hasLiveEventsConnection = false
    @State private var editorSettings = EditorSettingsModel()
    @State private var showSettingsPanel = false
    @State private var settingsSheetDetent: PresentationDetent = .large
    @State private var showHelpCenter = false
    @State private var showDebugWindow = false
    @State private var showOnboardingSheet = false
    @State private var isCreatingSampleProject = false
    @State private var isCheckingServerHealth = false
    @State private var isServerReachable: Bool?
    @State private var localFileRecordsByRemoteURL: [String: LocalFileRecord] = [:]
    @State private var localThumbnailURLByShotId: [String: URL] = [:]
    @State private var localThumbnailURLByJobId: [String: URL] = [:]
    @State private var debugEventLog: [String] = []
#if os(iOS)
    @State private var mobileEditorPresentedPanel: MobileEditorPresentedPanel?
#endif
    @State private var shotRequestStateById: [String: RenderRequestState] = [:]
    @State private var jobRequestStateById: [String: RenderRequestState] = [:]
    /// Tracks clip-job progress per shot so long-running `generating` work doesn’t false-timeout when only `progressPct` moves.
    @State private var lastSyncedClipJobProgressByShotId: [String: Int] = [:]
    @State private var lastSyncedProgressByJobId: [String: Int] = [:]
    @AppStorage("cinefuse.server.mode") private var apiServerModeRaw = APIServerMode.production.rawValue
    @AppStorage("cinefuse.server.customBaseURL") private var customServerBaseURL = ""
    @AppStorage("cinefuse.onboarding.completed") private var onboardingCompleted = false
#if os(iOS)
    /// Synced with ``ProjectDetailScreen`` — toolbar toggles on iPhone / compact iPad to collapse timeline or preview for more canvas space.
    @AppStorage("cinefuse.editor.collapse.timeline") private var collapseTimelinePanelChrome = false
    @AppStorage("cinefuse.editor.collapse.preview") private var collapsePreviewPanelChrome = false
#endif

    private let inFlightStatuses: Set<String> = ["queued", "generating", "running", "processing"]
    private let generatedFilesStore = GeneratedFilesStore()
    @StateObject private var editorPlaybackState = EditorPlaybackState()
    private var localServerBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000"
    }
    private var productionServerBaseURL: String {
        ProcessInfo.processInfo.environment["CINEFUSE_API_PROD_BASE_URL"] ?? "https://cinefuse.pubfuse.com"
    }
    private var activeServerBaseURL: String {
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .production {
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
        (APIServerMode(rawValue: apiServerModeRaw) ?? .production).label
    }
    private var requiresPubfuseJWTForActiveServer: Bool {
        switch APIServerMode(rawValue: apiServerModeRaw) ?? .production {
        case .local:
            return false
        case .production:
            return true
        case .custom:
            let normalized = (normalizedServerURL(customServerBaseURL) ?? "").lowercased()
            if normalized.contains("localhost") || normalized.contains("127.0.0.1") {
                return false
            }
            return !normalized.isEmpty
        }
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

    private var isAudioCreationWorkspace: Bool {
        CreationMode(rawValue: creationModeRaw) == .audio
    }

#if os(iOS)
    private var workspaceEditorLayoutTraits: EditorLayoutTraits {
        EditorLayoutTraits.iOS(horizontalSizeClass: horizontalSizeClass)
    }

    private func leftPanelChromeAction() {
        let traits = workspaceEditorLayoutTraits
        if traits.useSheetBasedSidePanels {
            if mobileEditorPresentedPanel == .leftInspector {
                mobileEditorPresentedPanel = nil
            } else {
                showLeftPane = true
                mobileEditorPresentedPanel = .leftInspector
            }
        } else {
            withAnimation(CinefuseTokens.Motion.panel) {
                showLeftPane.toggle()
            }
        }
    }

    private func rightPanelChromeAction() {
        let traits = workspaceEditorLayoutTraits
        if traits.useSheetBasedSidePanels {
            if mobileEditorPresentedPanel == .rightInspector {
                mobileEditorPresentedPanel = nil
            } else {
                showRightPane = true
                mobileEditorPresentedPanel = .rightInspector
            }
        } else {
            withAnimation(CinefuseTokens.Motion.panel) {
                showRightPane.toggle()
            }
        }
    }

    private func audioLanesChromeAction() {
        let traits = workspaceEditorLayoutTraits
        if !traits.useInlineBottomRegion {
            if mobileEditorPresentedPanel == .audioLanes {
                mobileEditorPresentedPanel = nil
            } else {
                showAudioPanel = true
                mobileEditorPresentedPanel = .audioLanes
            }
            return
        }
        withAnimation(CinefuseTokens.Motion.panel) {
            showAudioPanel.toggle()
            if showAudioPanel {
                showBottomPane = true
            }
        }
    }

    private func jobsChromeAction() {
        let traits = workspaceEditorLayoutTraits
        if !traits.useInlineBottomRegion {
            if mobileEditorPresentedPanel == .jobs {
                mobileEditorPresentedPanel = nil
            } else {
                showJobsPanel = true
                mobileEditorPresentedPanel = .jobs
            }
            return
        }
        withAnimation(CinefuseTokens.Motion.panel) {
            showJobsPanel.toggle()
            if showJobsPanel {
                showBottomPane = true
            }
        }
    }
#endif

    private var mobileEditorPresentedPanelBinding: Binding<MobileEditorPresentedPanel?> {
#if os(iOS)
        $mobileEditorPresentedPanel
#else
        .constant(nil)
#endif
    }

    private func persistShotPreviewTrim(shotId: String, previewTrimInMs: Int?, previewTrimOutMs: Int?) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let shot = try await api.patchShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shotId,
                previewTrimInMs: previewTrimInMs,
                previewTrimOutMs: previewTrimOutMs
            )
            await MainActor.run {
                if let idx = shots.firstIndex(where: { $0.id == shotId }) {
                    shots[idx] = shot
                }
            }
        } catch {
            await MainActor.run {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var shotsForEditorDisplay: [Shot] {
        shots.map { shot in
            if let clipUrl = shot.clipUrl,
               let record = localFileRecordsByRemoteURL[clipUrl],
               record.status == .synced || record.status == .alreadyPresent,
               let path = record.localPath,
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                let fileURL = URL(fileURLWithPath: path)
                return shot.withClipUrl(fileURL.absoluteString)
            }
            if let local = shotPlaybackClipURLByShotId[shot.id] {
                return shot.withClipUrl(local.absoluteString)
            }
            return shot
        }
    }

    private var projectDetailView: some View {
        ProjectDetailScreen(
            project: selectedProject,
            isLoadingProjectDetails: isLoadingProjectDetails,
            scenes: scenes,
            characters: characters,
            shots: shotsForEditorDisplay,
            audioTracks: audioTracks,
            jobs: jobs,
            localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
            localThumbnailURLByShotId: localThumbnailURLByShotId,
            localThumbnailURLByJobId: localThumbnailURLByJobId,
            debugEventLog: debugEventLog,
            shotRequestStateById: shotRequestStateById,
            jobRequestStateById: jobRequestStateById,
            showDebugWindow: $showDebugWindow,
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
            scoreDurationSeconds: $scoreDurationSeconds,
            scoreLyricsModeSelection: $scoreLyricsModeSelection,
            scoreCustomLyricsDraft: $scoreCustomLyricsDraft,
            onCloseProject: closeProject,
            onDeleteProject: { Task { await deleteSelectedProject() } },
            onRenameProject: { title in Task { await renameSelectedProject(title: title) } },
            onCreateCharacter: { Task { await createCharacter() } },
            onTrainCharacter: { characterId, referenceFileIds in
                Task { await trainCharacter(characterId: characterId, referenceFileIds: referenceFileIds) }
            },
            uploadProjectFiles: { urls in try await performUploadProjectFiles(urls: urls) },
            onGenerateStoryboard: { Task { await generateStoryboard() } },
            onReviseScene: { scene, revision in Task { await reviseScene(scene: scene, revision: revision) } },
            onQuote: { Task { await quoteShot() } },
            onCreateShot: { Task { await createShot() } },
            onGenerateShot: { shotId in Task { await generateShot(shotId: shotId) } },
            onRetryShot: { shotId in Task { await retryOrRestartShot(shotId: shotId) } },
            onDeleteShot: { shotId in Task { await deleteShotFromProject(shotId: shotId) } },
            onCreateJob: { Task { await createJob() } },
            onRetryJob: { jobId in Task { await retryOrRestartJob(jobId: jobId) } },
            onDeleteJob: { jobId in Task { await deleteJobFromProject(jobId: jobId) } },
            onReorderShots: { from, to in
                Task {
                    if CreationMode(rawValue: creationModeRaw) == .audio {
                        await reorderAudibleShots(from: from, to: to)
                    } else {
                        await reorderShots(from: from, to: to)
                    }
                }
            },
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
            onOpenDebugWindow: { showDebugWindow = true },
            showTooltips: editorSettings.showTooltips,
            creationModeRaw: $creationModeRaw,
            soundBlueprints: $soundBlueprints,
            selectedSoundBlueprintIdsByShotId: $selectedSoundBlueprintIdsByShotId,
            draftSoundBlueprintIds: $draftSoundBlueprintIds,
            soundSourceLabel: soundSourceLabel(for:),
            soundTagsDraft: $soundTagsDraft,
            onCreateSoundBlueprint: { request in Task { await createSoundBlueprint(request: request) } },
            onPlayBlueprintReferenceFile: { fileId in
                Task { await playBlueprintReferenceFile(fileId: fileId) }
            },
            onExportAudioMix: { Task { await exportLayeredAudioMix() } },
            onAddAudioTrack: { Task { await addEmptyAudioLane() } },
            onEnsureVideoLaneSlot: { lane in await ensureVideoLaneSlot(laneIndex: lane) },
            onRefreshStatusDetails: { await refreshGenerationStatusSnapshot() },
            onPersistShotPreviewTrim: { shotId, inMs, outMs in
                await persistShotPreviewTrim(shotId: shotId, previewTrimInMs: inMs, previewTrimOutMs: outMs)
            },
            isPreviewFullscreen: $isPreviewFullscreen,
            mobileEditorPresentedPanel: mobileEditorPresentedPanelBinding
        )
        .environmentObject(editorPlaybackState)
    }

    /// Re-fetches timeline + jobs only (no scenes/characters/blueprints, no file sync, no full-page loading).
    private func refreshGenerationStatusSnapshot() async {
        guard let selectedProjectId else { return }
        if isRefreshingProjectDetails || isRefreshingStatusSnapshot {
            return
        }
        isRefreshingStatusSnapshot = true
        defer { isRefreshingStatusSnapshot = false }
        do {
            async let timeline = api.listTimeline(token: model.bearerToken, projectId: selectedProjectId)
            async let projectJobs = api.listJobs(token: model.bearerToken, projectId: selectedProjectId)
            let latestTimeline = try await timeline
            let latestJobs = try await projectJobs
            let filteredJobs = latestJobs.filter { $0.status != "deleted" }
            await MainActor.run {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    shots = latestTimeline.shots
                    audioTracks = latestTimeline.audioTracks
                    jobs = filteredJobs
                    let keptShotIds = Set(latestTimeline.shots.map(\.id))
                    shotSoundSourceById = shotSoundSourceById.filter { keptShotIds.contains($0.key) }
                    selectedSoundBlueprintIdsByShotId = selectedSoundBlueprintIdsByShotId.filter {
                        keptShotIds.contains($0.key)
                    }
                }
                syncRequestStatesFromSnapshot(shots: latestTimeline.shots, jobs: filteredJobs)
                appendDebugEvent("status snapshot refresh shots=\(latestTimeline.shots.count) jobs=\(filteredJobs.count)")
                model.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                appendDebugEvent("status snapshot refresh failed reason=\(error.localizedDescription)")
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func createSoundBlueprint(request: CreateSoundBlueprintRequest) async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.createSoundBlueprint(
                token: model.bearerToken,
                projectId: selectedProjectId,
                body: request
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func playBlueprintReferenceFile(fileId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let url = try await api.downloadProjectFileForPlayback(
                token: model.bearerToken,
                projectId: selectedProjectId,
                fileId: fileId,
                filenameHint: nil
            )
            await MainActor.run {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    BlueprintReferenceHold.lastPlayer = player
                    player.play()
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        } catch {
            await MainActor.run {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func exportLayeredAudioMix() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.exportAudioMix(token: model.bearerToken, projectId: selectedProjectId)
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func addEmptyAudioLane() async {
        guard let selectedProjectId else { return }
        let nextLane = (audioTracks.map(\.laneIndex).max() ?? -1) + 1
        do {
            _ = try await api.createAudioTrack(
                token: model.bearerToken,
                projectId: selectedProjectId,
                kind: "lane",
                title: "Track \(nextLane + 1)",
                shotId: nil,
                laneIndex: nextLane,
                startMs: 0,
                durationMs: 1000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    /// Creates an empty lane slot at fixed index 0 or 1 for video-mode layering UI (no-op if a track already uses that lane).
    private func ensureVideoLaneSlot(laneIndex: Int) async {
        guard let selectedProjectId else { return }
        guard laneIndex == 0 || laneIndex == 1 else { return }
        if audioTracks.contains(where: { $0.laneIndex == laneIndex }) {
            return
        }
        do {
            _ = try await api.createAudioTrack(
                token: model.bearerToken,
                projectId: selectedProjectId,
                kind: "lane",
                title: laneIndex == 0 ? "Primary layer" : "Secondary layer",
                shotId: nil,
                laneIndex: laneIndex,
                startMs: 0,
                durationMs: 1000
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
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
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: 280,
                    max: 520
                )
            } detail: {
                projectDetailView
            }
            .onChange(of: selectedProjectId) { _, _ in
#if os(iOS)
                mobileEditorPresentedPanel = nil
#endif
                shotPlaybackClipURLByShotId = [:]
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
        .sheet(isPresented: $showDebugWindow) {
            DebugGenerationWindow(logLines: debugEventLog)
        }
        .sheet(isPresented: $showHelpCenter) {
            HelpCenterSheet()
        }
        .sheet(isPresented: $showOnboardingSheet) {
            onboardingSheet
        }
        .task {
#if os(iOS)
            EditorMobileDefaultsMigration.applyIfNeeded()
#endif
            await refreshServerHealth()
            if editorSettings.restoreLastOpenWorkspace, !lastProjectId.isEmpty {
                await refresh(selectProjectId: lastProjectId)
            } else {
                await refresh(selectProjectId: selectedProjectId)
            }
            if !onboardingCompleted && model.projects.isEmpty {
                showOnboardingSheet = true
            }
        }
        .task(id: activeServerBaseURL) {
            await refreshServerHealth()
        }
        .preferredColorScheme(timelineThemeMode.colorScheme)
        .task(id: selectedProjectId) {
            await monitorInFlightJobs()
        }
        .task(id: selectedProjectId) {
            await observeProjectEvents()
        }
        .onChange(of: selectedProjectId) { _, newId in
            if newId == nil {
                isPreviewFullscreen = false
            }
        }
        .onChange(of: apiServerModeRaw) { _, _ in
            Task {
                await refresh(selectProjectId: selectedProjectId)
                await refreshServerHealth()
            }
        }
        .onChange(of: customServerBaseURL) { _, _ in
            guard (APIServerMode(rawValue: apiServerModeRaw) ?? .production) == .custom else { return }
            Task { await refreshServerHealth() }
        }
        .tint(timelineThemeMode.palette.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
            PubfuseLogoBadge()
            Spacer(minLength: CinefuseTokens.Spacing.s)
            HStack(alignment: .center, spacing: CinefuseTokens.Spacing.xs) {
                serverStatusBadge
                headerSparksLabel
                globalWorkspaceControls
                if selectedProject == nil {
                    Button {
                        openCreateProjectSheet()
                    } label: {
                        Label("New Project", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut("n", modifiers: [.command])
                }
                IconCommandButton(
                    systemName: "door.left.hand.open",
                    label: "Sign Out",
                    action: {
                        closeProject()
                        model.signOut()
                        lastProjectId = ""
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
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

    private var headerSparksLabel: some View {
        Label {
            Text("Sparks: \(model.balance)")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        } icon: {
            Image(systemName: "sparkles")
                .font(CinefuseTokens.Typography.caption.weight(.medium))
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var globalWorkspaceControls: some View {
#if os(iOS)
        iOSGlobalWorkspaceControls
#else
        macOSGlobalWorkspaceControls
#endif
    }

#if os(iOS)
    private var iOSGlobalWorkspaceControls: some View {
        HStack(spacing: CinefuseTokens.Spacing.xs) {
            if workspaceEditorLayoutTraits.useCompactWorkspaceChrome {
                Menu {
                    Section("Creation") {
                        ForEach(CreationMode.allCases) { mode in
                            Button {
                                creationModeRaw = mode.rawValue
                            } label: {
                                HStack {
                                    Text(mode.label)
                                    Spacer(minLength: 8)
                                    if creationModeRaw == mode.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(CinefuseTokens.ColorRole.accent)
                                    }
                                }
                            }
                        }
                    }
                    Section("Layout") {
                        ForEach(EditorWorkspacePreset.allCases) { preset in
                            Button {
                                workspacePresetRaw = preset.rawValue
                                applyWorkspacePreset(preset.rawValue)
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    Spacer(minLength: 8)
                                    if workspacePresetRaw == preset.rawValue {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(CinefuseTokens.ColorRole.accent)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            swapSidePanes.toggle()
                        }
                    } label: {
                        Label("Swap side panels", systemImage: "arrow.left.arrow.right.square")
                    }
                } label: {
                    Label("Mode & preset", systemImage: "square.grid.2x2")
                }
                .tooltip("Creation mode and workspace layout", enabled: editorSettings.showTooltips)
            } else {
                HStack(spacing: CinefuseTokens.Spacing.xxs) {
                    CreationModeBinarySwitch(creationModeRaw: $creationModeRaw)
                        .tooltip("Video Creation or Audio Creation mode", enabled: editorSettings.showTooltips)

                    EditorWorkspacePresetSegmentSwitch(workspacePresetRaw: $workspacePresetRaw)
                        .onChange(of: workspacePresetRaw) { _, newValue in
                            applyWorkspacePreset(newValue)
                        }
                        .tooltip("Choose workspace layout: Edit, Audio, Review, or Render", enabled: editorSettings.showTooltips)
                }
            }

            IconCommandButton(
                systemName: "sidebar.left",
                label: "Story & characters",
                action: { leftPanelChromeAction() },
                tooltipEnabled: editorSettings.showTooltips
            )

            IconCommandButton(
                systemName: "sidebar.right",
                label: "Shots & export",
                action: { rightPanelChromeAction() },
                tooltipEnabled: editorSettings.showTooltips
            )

            if workspaceEditorLayoutTraits.useSheetBasedSidePanels
                || workspaceEditorLayoutTraits.useCompactWorkspaceChrome {
                IconCommandButton(
                    systemName: collapseTimelinePanelChrome ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                    label: collapseTimelinePanelChrome ? "Expand timeline" : "Collapse timeline",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            collapseTimelinePanelChrome.toggle()
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
                IconCommandButton(
                    systemName: collapsePreviewPanelChrome ? "play.square.fill" : "play.square",
                    label: collapsePreviewPanelChrome ? "Expand preview" : "Collapse preview",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            collapsePreviewPanelChrome.toggle()
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }

            if !isAudioCreationWorkspace {
                IconCommandButton(
                    systemName: showAudioPanel ? "waveform" : "waveform.slash",
                    label: "Audio lanes",
                    action: { audioLanesChromeAction() },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }

            IconCommandButton(
                systemName: showJobsPanel ? "list.bullet.clipboard.fill" : "list.bullet.clipboard",
                label: "Jobs",
                action: { jobsChromeAction() },
                tooltipEnabled: editorSettings.showTooltips
            )

            if selectedProjectId != nil {
                IconCommandButton(
                    systemName: isPreviewFullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    label: isPreviewFullscreen ? "Exit full-screen preview" : "Full-screen preview",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            isPreviewFullscreen.toggle()
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }

            if !workspaceEditorLayoutTraits.useCompactWorkspaceChrome {
                IconCommandButton(
                    systemName: "arrow.left.arrow.right.square",
                    label: "Swap side panels",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            swapSidePanes.toggle()
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }

            settingsPresentationTrigger
            IconCommandButton(
                systemName: "info.circle",
                label: "Help",
                action: { showHelpCenter = true },
                tooltipEnabled: editorSettings.showTooltips
            )
        }
    }
#endif

    private var macOSGlobalWorkspaceControls: some View {
        HStack(spacing: CinefuseTokens.Spacing.xs) {
            HStack(spacing: CinefuseTokens.Spacing.xxs) {
                CreationModeBinarySwitch(creationModeRaw: $creationModeRaw)
                    .tooltip("Video Creation or Audio Creation mode", enabled: editorSettings.showTooltips)

                EditorWorkspacePresetSegmentSwitch(workspacePresetRaw: $workspacePresetRaw)
                    .onChange(of: workspacePresetRaw) { _, newValue in
                        applyWorkspacePreset(newValue)
                    }
                    .tooltip("Choose workspace layout: Edit, Audio, Review, or Render", enabled: editorSettings.showTooltips)
            }

            IconCommandButton(
                systemName: showLeftPane ? "sidebar.left" : "sidebar.left",
                label: "Toggle left panel",
                action: {
                    withAnimation(CinefuseTokens.Motion.panel) {
                        showLeftPane.toggle()
                    }
                },
                tooltipEnabled: editorSettings.showTooltips
            )

            IconCommandButton(
                systemName: showRightPane ? "sidebar.right" : "sidebar.right",
                label: "Toggle right panel",
                action: {
                    withAnimation(CinefuseTokens.Motion.panel) {
                        showRightPane.toggle()
                    }
                },
                tooltipEnabled: editorSettings.showTooltips
            )
            IconCommandButton(
                systemName: showBottomPane ? "rectangle.split.3x1.fill" : "rectangle.split.3x1",
                label: "Toggle bottom panel",
                action: {
                    withAnimation(CinefuseTokens.Motion.panel) {
                        showBottomPane.toggle()
                        if showBottomPane && !showAudioPanel && !showJobsPanel {
                            if !isAudioCreationWorkspace {
                                showAudioPanel = true
                            }
                            showJobsPanel = true
                        }
                    }
                },
                tooltipEnabled: editorSettings.showTooltips
            )
            if !isAudioCreationWorkspace {
                IconCommandButton(
                    systemName: showAudioPanel ? "waveform" : "waveform.slash",
                    label: "Toggle audio lanes panel",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            showAudioPanel.toggle()
                            if showAudioPanel {
                                showBottomPane = true
                            }
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }
            IconCommandButton(
                systemName: showJobsPanel ? "list.bullet.clipboard.fill" : "list.bullet.clipboard",
                label: "Toggle jobs panel",
                action: {
                    withAnimation(CinefuseTokens.Motion.panel) {
                        showJobsPanel.toggle()
                        if showJobsPanel {
                            showBottomPane = true
                        }
                    }
                },
                tooltipEnabled: editorSettings.showTooltips
            )
            if selectedProjectId != nil {
                IconCommandButton(
                    systemName: isPreviewFullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    label: isPreviewFullscreen ? "Exit full-screen preview" : "Full-screen preview",
                    action: {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            isPreviewFullscreen.toggle()
                        }
                    },
                    tooltipEnabled: editorSettings.showTooltips
                )
            }
            IconCommandButton(
                systemName: "arrow.left.arrow.right.square",
                label: "Swap side panels",
                action: {
                    withAnimation(CinefuseTokens.Motion.panel) {
                        swapSidePanes.toggle()
                    }
                },
                tooltipEnabled: editorSettings.showTooltips
            )

            settingsPresentationTrigger
            IconCommandButton(
                systemName: "info.circle",
                label: "Help",
                action: { showHelpCenter = true },
                tooltipEnabled: editorSettings.showTooltips
            )
        }
    }

    @ViewBuilder
    private var settingsPresentationTrigger: some View {
#if os(iOS)
        IconCommandButton(
            systemName: "slider.horizontal.3",
            label: "Editor settings",
            action: {
                withAnimation(CinefuseTokens.Motion.standard) {
                    showSettingsPanel.toggle()
                }
            },
            tooltipEnabled: editorSettings.showTooltips
        )
        .sheet(isPresented: $showSettingsPanel) {
            workspaceSettingsPanel
                .presentationDetents([.medium, .large], selection: $settingsSheetDetent)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: showSettingsPanel) { _, isOpen in
            if isOpen {
                settingsSheetDetent = .large
            }
        }
#else
        IconCommandButton(
            systemName: "slider.horizontal.3",
            label: "Editor settings",
            action: {
                withAnimation(CinefuseTokens.Motion.standard) {
                    showSettingsPanel.toggle()
                }
            },
            tooltipEnabled: editorSettings.showTooltips
        )
        .popover(isPresented: $showSettingsPanel, arrowEdge: .bottom) {
            workspaceSettingsPanel
        }
#endif
    }

    private var workspaceSettingsPreferredWidth: CGFloat {
#if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return CinefuseTokens.Control.settingsPanelWidthIOSMac
        }
#endif
        return CinefuseTokens.Control.settingsPanelWidth
    }

    private var workspaceSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
                HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                        Text("Editor Settings")
                            .font(CinefuseTokens.Typography.sectionTitle)
                        Text("Appearance, workspace behavior, and server controls.")
                            .font(CinefuseTokens.Typography.caption)
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(CinefuseTokens.Motion.quick) {
                            showSettingsPanel = false
                        }
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }

                settingsSection("Appearance", subtitle: "Theme and visual presentation.") {
                    Picker("Theme", selection: timelineThemeModeBinding) {
                        ForEach(TimelineThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Theme is saved automatically.")
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }

                settingsSection("Workspace Behavior", subtitle: "Editing and restore preferences.") {
                    Toggle("Show tooltips", isOn: $editorSettings.showTooltips)
                    Toggle("Restore last open project", isOn: $editorSettings.restoreLastOpenWorkspace)
                }

                settingsSection("Server Connection", subtitle: "Active API endpoint and connectivity.") {
                    Picker("API Server", selection: $apiServerModeRaw) {
                        ForEach(APIServerMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    if (APIServerMode(rawValue: apiServerModeRaw) ?? .production) == .custom {
                        TextField("https://your-server.example.com", text: $customServerBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .transition(.opacity.combined(with: .move(edge: .top)))
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CinefuseTokens.Spacing.m)
        }
        .frame(width: workspaceSettingsPreferredWidth)
        .animation(CinefuseTokens.Motion.standard, value: apiServerModeRaw)
    }

    private func settingsSection<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text(title)
                    .font(CinefuseTokens.Typography.label.weight(.semibold))
                Text(subtitle)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            content()
        }
        .padding(CinefuseTokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                        .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                )
        )
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
        let dotColor: Color = {
            if isCheckingServerHealth {
                return CinefuseTokens.ColorRole.warning
            }
            if let isServerReachable {
                return isServerReachable ? CinefuseTokens.ColorRole.success : CinefuseTokens.ColorRole.danger
            }
            return CinefuseTokens.ColorRole.textSecondary
        }()
        let reachabilityPhrase: String = {
            if isCheckingServerHealth {
                return "checking connection"
            }
            if let isServerReachable {
                return isServerReachable ? "online" : "offline"
            }
            return "connection unknown"
        }()

        return HStack(spacing: CinefuseTokens.Spacing.xxs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(serverModeLabel)
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(serverModeLabel), \(reachabilityPhrase)")
    }

    private func refreshServerHealth() async {
        isCheckingServerHealth = true
        let reachable = await api.healthCheck()
        isServerReachable = reachable
        isCheckingServerHealth = false
    }

    private func applyWorkspacePreset(_ rawValue: String) {
        guard let preset = EditorWorkspacePreset(rawValue: rawValue) else { return }
        withAnimation(CinefuseTokens.Motion.panel) {
            switch preset {
            case .editing:
                showLeftPane = true
                showRightPane = true
                showBottomPane = true
                showAudioPanel = true
                showJobsPanel = true
                swapSidePanes = false
            case .audio:
                showLeftPane = false
                showRightPane = true
                showBottomPane = true
                showAudioPanel = true
                showJobsPanel = true
                swapSidePanes = false
            case .review:
                showLeftPane = true
                showRightPane = false
                showBottomPane = true
                showAudioPanel = true
                showJobsPanel = true
                swapSidePanes = false
            case .render:
                showLeftPane = false
                showRightPane = false
                showBottomPane = true
                showAudioPanel = true
                showJobsPanel = true
                swapSidePanes = false
            }
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

    private var onboardingSheet: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Welcome to Cinefuse")
                .font(CinefuseTokens.Typography.screenTitle)

            Text("Create your first short in three steps.")
                .font(CinefuseTokens.Typography.body)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                Label("Generate a beat sheet in Storyboard.", systemImage: "list.bullet.rectangle.portrait")
                Label("Draft shots and quote Spark costs.", systemImage: "film.stack")
                Label("Render, stitch, and export when ready.", systemImage: "square.and.arrow.up")
            }
            .font(CinefuseTokens.Typography.body)
            .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)

            HStack(spacing: CinefuseTokens.Spacing.s) {
                Button("Skip for now") {
                    onboardingCompleted = true
                    showOnboardingSheet = false
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isCreatingSampleProject)

                Button {
                    Task { await createSampleProjectFromTemplate() }
                } label: {
                    if isCreatingSampleProject {
                        ProgressView()
                            .frame(minWidth: 140)
                    } else {
                        Text("Create Sample Project")
                            .frame(minWidth: 140)
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(isCreatingSampleProject)

                Button("Create First Project") {
                    onboardingCompleted = true
                    showOnboardingSheet = false
                    openCreateProjectSheet()
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isCreatingSampleProject)
            }
        }
        .padding(CinefuseTokens.Spacing.l)
        .frame(minWidth: 520)
    }

    private func createSampleProjectFromTemplate() async {
        guard !isCreatingSampleProject else { return }
        isCreatingSampleProject = true
        defer { isCreatingSampleProject = false }

        model.errorMessage = nil
        do {
            let project = try await api.createProject(
                token: model.bearerToken,
                title: "Sample: Neon Rooftop Chase"
            )
            _ = try await api.generateStoryboard(
                token: model.bearerToken,
                projectId: project.id,
                logline: "A coder races across neon rooftops to deliver a critical patch before sunrise.",
                targetDurationMinutes: 3,
                tone: "Cinematic thriller with hopeful finish"
            )
            onboardingCompleted = true
            showOnboardingSheet = false
            await refresh(selectProjectId: project.id)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func refresh(selectProjectId: String? = nil) async {
        model.isLoading = true
        defer { model.isLoading = false }
        model.errorMessage = nil
        if requiresPubfuseJWTForActiveServer && model.pubfuseAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.errorMessage = "Remote server requires a Pubfuse login token. Sign out and sign in again to reconnect."
            return
        }
        do {
            async let projectsTask = withTimeout(seconds: 20, message: "Loading projects timed out") {
                try await api.listProjects(token: model.bearerToken)
            }
            async let balanceTask = withTimeout(seconds: 20, message: "Loading Spark balance timed out") {
                try await api.getBalance(token: model.bearerToken)
            }
            model.projects = try await projectsTask
            model.balance = try await balanceTask
            if let selectProjectId {
                selectedProjectId = selectProjectId
            } else if !model.projects.contains(where: { $0.id == selectedProjectId }) {
                selectedProjectId = model.projects.first?.id
            }
            await loadSelectedProjectDetails(showLoadingIndicator: true)
        } catch {
            let message = error.localizedDescription
            if requiresPubfuseJWTForActiveServer && message.lowercased().contains("invalid token") {
                model.errorMessage = "Your Pubfuse session expired for remote mode. Sign out, then sign in again."
            } else {
                model.errorMessage = message
            }
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        message: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let delayNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNanoseconds)
                throw NSError(
                    domain: "Cinefuse.Refresh",
                    code: 408,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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
        pendingReloadSelectedProjectDetails = false
        scenes = []
        characters = []
        quotedShotCost = nil
        shots = []
        audioTracks = []
        jobs = []
        shotSoundSourceById = [:]
        localFileRecordsByRemoteURL = [:]
        localThumbnailURLByShotId = [:]
        localThumbnailURLByJobId = [:]
        debugEventLog = []
        shotRequestStateById = [:]
        jobRequestStateById = [:]
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

    private func appendDebugEvent(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        debugEventLog.append(line)
        if debugEventLog.count > 200 {
            debugEventLog.removeFirst(debugEventLog.count - 200)
        }
        DiagnosticsLogger.renderStatus(message: line)
    }

    private func parseISODate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date()
    }

    private func parseOptionalISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func upsertShotRequestState(_ shotId: String, _ update: (inout RenderRequestState) -> Void) {
        var state = shotRequestStateById[shotId] ?? RenderRequestState()
        update(&state)
        shotRequestStateById[shotId] = state
    }

    private func upsertJobRequestState(_ jobId: String, _ update: (inout RenderRequestState) -> Void) {
        var state = jobRequestStateById[jobId] ?? RenderRequestState()
        update(&state)
        jobRequestStateById[jobId] = state
    }

    private func updateLifecycleTimeouts() {
        let now = Date()
        let timeoutSeconds: TimeInterval = 120

        for (shotId, state) in shotRequestStateById {
            guard state.stage.isTimeoutCandidate else { continue }
            let reference = state.lastMeaningfulTransitionAt ?? state.requestSentAt
            guard let reference else { continue }
            let age = now.timeIntervalSince(reference)
            if age > timeoutSeconds {
                var updated = state
                updated.stage = .timedOut
                updated.errorMessage = "No update for \(Int(age))s after request."
                shotRequestStateById[shotId] = updated
                appendDebugEvent("timeout shot=\(shotId) waited=\(Int(age))s stage=\(state.stage.rawValue)")
            }
        }

        for (jobId, state) in jobRequestStateById {
            guard state.stage.isTimeoutCandidate else { continue }
            let reference = state.lastMeaningfulTransitionAt ?? state.requestSentAt
            guard let reference else { continue }
            let age = now.timeIntervalSince(reference)
            if age > timeoutSeconds {
                var updated = state
                updated.stage = .timedOut
                updated.errorMessage = "No update for \(Int(age))s after request."
                jobRequestStateById[jobId] = updated
                appendDebugEvent("timeout job=\(jobId) waited=\(Int(age))s stage=\(state.stage.rawValue)")
            }
        }
    }

    private func syncRequestStatesFromSnapshot(shots: [Shot], jobs: [Job]) {
        var latestJobByShotId: [String: Job] = [:]
        for job in jobs {
            guard let shotId = job.shotId else { continue }
            let current = latestJobByShotId[shotId]
            let isNewer = parseOptionalISODate(job.updatedAt) ?? .distantPast
                >= parseOptionalISODate(current?.updatedAt) ?? .distantPast
            if current == nil || isNewer {
                latestJobByShotId[shotId] = job
            }
        }

        for shot in shots {
            let generationNoun = latestJobByShotId[shot.id]?.kind == "audio" ? "Sound" : "Shot"
            // Sound uses `kind == "audio"` jobs; only reading `clip` progress never advanced
            // `lastMeaningfulTransitionAt`, so the 120s shot timeout fired while the worker was healthy.
            let progressJob = latestJobByShotId[shot.id]
            let progressNow = progressJob?.progressPct
            let prevProgress = lastSyncedClipJobProgressByShotId[shot.id]
            let progressAdvanced = progressNow != nil && progressNow != prevProgress
                && inFlightStatuses.contains(shot.status.lowercased())

            upsertShotRequestState(shot.id) { state in
                let previousStatus = state.lastKnownStatus
                state.lastKnownStatus = shot.status
                state.source = "snapshot"
                if state.requestSentAt == nil {
                    state.requestSentAt = Date()
                }
                let changed = previousStatus != shot.status
                switch shot.status {
                case "queued", "generating", "running", "processing":
                    if state.stage != .failed && state.stage != .timedOut {
                        state.stage = shot.status == "queued" ? .waiting : .running
                    }
                case "ready":
                    state.stage = .done
                case "failed":
                    state.stage = .failed
                    let backendDetail = latestJobByShotId[shot.id]?.errorMessage?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let backendError = (backendDetail?.isEmpty == false) ? backendDetail : nil
                    state.errorMessage = backendError ?? state.errorMessage ?? "\(generationNoun) generation failed."
                default:
                    break
                }
                if changed {
                    state.lastMeaningfulTransitionAt = Date()
                    if shot.status == "ready" {
                        appendDebugEvent("snapshot shot final shot=\(shot.id) status=\(shot.status)")
                    } else if shot.status == "failed" {
                        let j = latestJobByShotId[shot.id]
                        let err = j?.errorMessage.map { String($0.prefix(220)) } ?? ""
                        appendDebugEvent(
                            "snapshot shot final shot=\(shot.id) status=failed job=\(j?.id ?? "-") kind=\(j?.kind ?? "-") err=\(err)"
                        )
                    }
                } else if progressAdvanced {
                    state.lastMeaningfulTransitionAt = Date()
                    state.lastEventAt = Date()
                }

                let lj = latestJobByShotId[shot.id]
                let invokeDone = (lj?.invokeState ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "done"
                if shot.status != "failed", lj?.status == "done" || invokeDone {
                    state.stage = .done
                    state.errorMessage = nil
                    state.lastMeaningfulTransitionAt = parseOptionalISODate(lj?.updatedAt) ?? Date()
                }
            }

            if shot.status == "ready" || shot.status == "failed" {
                lastSyncedClipJobProgressByShotId.removeValue(forKey: shot.id)
            } else if let progressNow {
                lastSyncedClipJobProgressByShotId[shot.id] = progressNow
            }
        }

        for job in jobs {
            let stateDate = parseOptionalISODate(job.updatedAt)
            let prevJobProgress = lastSyncedProgressByJobId[job.id]
            let currProgress = job.progressPct
            let progressMoved = currProgress != nil && currProgress != prevJobProgress

            upsertJobRequestState(job.id) { state in
                let previousStatus = state.lastKnownStatus
                state.lastKnownStatus = job.status
                state.source = "snapshot"
                if state.requestSentAt == nil {
                    state.requestSentAt = stateDate
                }
                let changed = previousStatus != job.status
                switch job.status {
                case "queued":
                    if state.stage != .failed && state.stage != .timedOut {
                        state.stage = .waiting
                    }
                case "running", "processing":
                    if state.stage != .failed && state.stage != .timedOut {
                        state.stage = .running
                    }
                case "done":
                    state.stage = .done
                case "failed":
                    state.stage = .failed
                    let trimmedJobErr = job.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let jobErr = (trimmedJobErr?.isEmpty == false) ? trimmedJobErr : nil
                    state.errorMessage = jobErr ?? state.errorMessage ?? "Render job failed."
                default:
                    break
                }
                if changed || progressMoved {
                    state.lastMeaningfulTransitionAt = stateDate ?? Date()
                    state.lastEventAt = stateDate ?? state.lastEventAt
                    if job.status == "done" || job.status == "failed" {
                        let err = job.errorMessage.map { String($0.prefix(220)) } ?? ""
                        let fe = [job.featureError?.reason, job.featureError?.detail]
                            .compactMap { $0 }
                            .joined(separator: " | ")
                        appendDebugEvent(
                            "snapshot job final job=\(job.id) kind=\(job.kind) status=\(job.status) progress=\(job.progressPct.map(String.init) ?? "n/a") shot=\(job.shotId ?? "-") err=\(err) featureErr=\(fe)"
                        )
                    } else if changed, job.status == "queued" {
                        let started = !providerPipelineNotStarted(job: job)
                        appendDebugEvent(
                            "snapshot job queued job=\(job.id) kind=\(job.kind) shot=\(job.shotId ?? "-") provider_started=\(started) updatedAt=\(job.updatedAt ?? "?")"
                        )
                    }
                }
                if state.stage == .running, state.responseReceivedAt == nil {
                    state.responseReceivedAt = stateDate ?? Date()
                }
            }

            if job.status == "done" || job.status == "failed" {
                lastSyncedProgressByJobId.removeValue(forKey: job.id)
            } else if let currProgress {
                lastSyncedProgressByJobId[job.id] = currProgress
            }
        }
    }

    private func syncArtifactFromRemoteURL(
        projectId: String,
        remoteURLString: String,
        preferredBaseName: String
    ) async -> LocalFileRecord {
        let fetchStr = GeneratedFilesStore.fetchURLStringForRemoteArtifact(
            remoteURLString: remoteURLString,
            apiGatewayBaseURLString: activeServerBaseURL
        )
        return await generatedFilesStore.syncFile(
            projectId: projectId,
            remoteURLString: remoteURLString,
            preferredBaseName: preferredBaseName,
            fetchURLString: fetchStr != remoteURLString ? fetchStr : nil,
            bearerToken: model.bearerToken,
            authorizedApiBaseURLString: activeServerBaseURL
        )
    }

    private func syncGeneratedFiles(projectId: String, shots: [Shot], jobs: [Job]) async {
        var refreshedShotThumbnails: [String: URL] = [:]
        var refreshedJobThumbnails: [String: URL] = [:]

        for shot in shots {
            guard let clipUrl = shot.clipUrl, !clipUrl.isEmpty else { continue }
            let localRecord = await syncArtifactFromRemoteURL(
                projectId: projectId,
                remoteURLString: clipUrl,
                preferredBaseName: "shot-\(shot.orderIndex ?? 0)-\(shot.id)"
            )
            let thumbnailURL = await ensureShotThumbnail(projectId: projectId, shot: shot, localClipRecord: localRecord)
            if let thumbnailURL {
                refreshedShotThumbnails[shot.id] = thumbnailURL
            }
            await MainActor.run {
                localFileRecordsByRemoteURL[clipUrl] = localRecord
                if let thumbnailURL {
                    localThumbnailURLByShotId[shot.id] = thumbnailURL
                }
                appendDebugEvent("shot file sync \(localRecord.status.rawValue) shot=\(shot.id)")
            }
        }

        for job in jobs {
            if let shotId = job.shotId, let thumbnailURL = refreshedShotThumbnails[shotId] {
                refreshedJobThumbnails[job.id] = thumbnailURL
            }
            if (job.kind == "audio" || job.kind == "audio_export"),
               let outputUrl = job.outputUrl,
               !outputUrl.isEmpty {
                let baseName = job.kind == "audio_export" ? "audio-export-\(job.id)" : "audio-\(job.id)"
                let localRecord = await syncArtifactFromRemoteURL(
                    projectId: projectId,
                    remoteURLString: outputUrl,
                    preferredBaseName: baseName
                )
                await MainActor.run {
                    localFileRecordsByRemoteURL[outputUrl] = localRecord
                    appendDebugEvent("audio file sync \(localRecord.status.rawValue) job=\(job.id)")
                }
            }
            guard job.kind == "export" else { continue }
            guard let outputUrl = job.outputUrl, !outputUrl.isEmpty else { continue }
            let localRecord = await syncArtifactFromRemoteURL(
                projectId: projectId,
                remoteURLString: outputUrl,
                preferredBaseName: "export-\(job.id)"
            )
            let outputThumbnailURL = await ensureExportThumbnail(projectId: projectId, job: job, localOutputRecord: localRecord)
            if let outputThumbnailURL {
                refreshedJobThumbnails[job.id] = outputThumbnailURL
            }
            await MainActor.run {
                localFileRecordsByRemoteURL[outputUrl] = localRecord
                if let outputThumbnailURL {
                    localThumbnailURLByJobId[job.id] = outputThumbnailURL
                }
                appendDebugEvent("export file sync \(localRecord.status.rawValue) job=\(job.id)")
            }
        }

        await MainActor.run {
            localThumbnailURLByShotId = refreshedShotThumbnails
            localThumbnailURLByJobId = refreshedJobThumbnails
        }
    }

    private func ensureShotThumbnail(projectId: String, shot: Shot, localClipRecord: LocalFileRecord) async -> URL? {
        let clipName = clipDisplayName(for: shot)
        if let existing = try? await generatedFilesStore.existingThumbnailURL(
            projectId: projectId,
            clipName: clipName,
            shotId: shot.id,
            orderIndex: shot.orderIndex
        ) {
            return existing
        }
        guard let localClipPath = localClipRecord.localPath else { return nil }
        let clipURL = URL(fileURLWithPath: localClipPath)
        guard let imageData = thumbnailJPEGData(from: clipURL) else { return nil }
        return try? await generatedFilesStore.writeThumbnailData(
            imageData,
            projectId: projectId,
            clipName: clipName,
            shotId: shot.id,
            orderIndex: shot.orderIndex
        )
    }

    private func ensureExportThumbnail(projectId: String, job: Job, localOutputRecord: LocalFileRecord) async -> URL? {
        guard let localOutputPath = localOutputRecord.localPath else { return nil }
        let clipURL = URL(fileURLWithPath: localOutputPath)
        guard let imageData = thumbnailJPEGData(from: clipURL) else { return nil }
        return try? await generatedFilesStore.writeThumbnailData(
            imageData,
            projectId: projectId,
            clipName: "export-\(job.id)",
            shotId: job.id,
            orderIndex: nil
        )
    }

    private func clipDisplayName(for shot: Shot) -> String {
        let trimmedPrompt = shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            return trimmedPrompt
        }
        return "shot-\(shot.orderIndex ?? 0)"
    }

    private func thumbnailJPEGData(from videoURL: URL) -> Data? {
#if canImport(AVFoundation)
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let frameTime = CMTime(seconds: 0.2, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: frameTime, actualTime: nil) else {
            return nil
        }
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let image = NSImage(cgImage: cgImage, size: .zero)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
#elseif canImport(UIKit)
        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: 0.82)
#else
        return nil
#endif
#else
        return nil
#endif
    }

    private func loadSelectedProjectDetails(showLoadingIndicator: Bool = false) async {
        guard let selectedProjectId else {
            scenes = []
            characters = []
            shots = []
            audioTracks = []
            jobs = []
            soundBlueprints = []
            selectedSoundBlueprintIdsByShotId = [:]
            draftSoundBlueprintIds = []
            shotSoundSourceById = [:]
            return
        }
        if isRefreshingProjectDetails {
            pendingReloadSelectedProjectDetails = true
            appendDebugEvent("project refresh coalesced (already refreshing)")
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
            var latestBlueprints: [SoundBlueprint] = []
            do {
                latestBlueprints = try await api.listSoundBlueprints(
                    token: model.bearerToken,
                    projectId: selectedProjectId
                )
            } catch {
                appendDebugEvent("sound blueprints unavailable \(error.localizedDescription)")
            }
            var transaction = Transaction()
            if !showLoadingIndicator {
                transaction.animation = nil
            }
            withTransaction(transaction) {
                scenes = latestScenes
                characters = latestCharacters
                shots = latestTimeline.shots
                audioTracks = latestTimeline.audioTracks
                jobs = latestJobs.filter { $0.status != "deleted" }
                soundBlueprints = latestBlueprints
                let keptShotIds = Set(latestTimeline.shots.map(\.id))
                shotSoundSourceById = shotSoundSourceById.filter { keptShotIds.contains($0.key) }
                selectedSoundBlueprintIdsByShotId = selectedSoundBlueprintIdsByShotId.filter { keptShotIds.contains($0.key) }
            }
            syncRequestStatesFromSnapshot(
                shots: latestTimeline.shots,
                jobs: latestJobs.filter { $0.status != "deleted" }
            )
            // `syncGeneratedFiles` can await a long time; do not hold the refresh gate across it
            // or the in-flight monitor drops polls and misses job completion until timeout.
            isRefreshingProjectDetails = false
            await syncGeneratedFiles(
                projectId: selectedProjectId,
                shots: latestTimeline.shots,
                jobs: latestJobs
            )
            appendDebugEvent("project refresh complete shots=\(latestTimeline.shots.count) jobs=\(latestJobs.count)")
            model.errorMessage = nil
        } catch {
            appendDebugEvent("project refresh failed reason=\(error.localizedDescription)")
            model.errorMessage = error.localizedDescription
        }
        if pendingReloadSelectedProjectDetails {
            pendingReloadSelectedProjectDetails = false
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        }
    }

    private func monitorInFlightJobs() async {
        guard selectedProjectId != nil else { return }
        while !Task.isCancelled && selectedProjectId != nil {
            await MainActor.run {
                updateLifecycleTimeouts()
            }
            // SSE does not guarantee delivery (proxies, reconnects). Poll timeline+jobs while work is in flight,
            // even when the event stream is connected, so UI cannot stick at an early progress tick.
            if scenePhase == .active && hasInFlightWork {
                if hasLiveEventsConnection {
                    await refreshGenerationStatusSnapshot()
                } else {
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                }
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
                    DiagnosticsLogger.projectEventReceived(
                        type: event.type,
                        projectId: event.projectId,
                        shotId: event.shotId,
                        jobId: event.jobId
                    )
                    applyProjectEvent(event)
                }
            } catch {
                // Background event stream failures should not block the editor flow.
                appendDebugEvent("event stream error reason=\(error.localizedDescription)")
            }

            hasLiveEventsConnection = false
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func applyProjectEvent(_ event: ProjectEvent) {
        appendDebugEvent("event \(event.type) shot=\(event.shotId ?? "-") job=\(event.jobId ?? "-") status=\(event.status ?? "-")")
        switch event.type {
        case "shot_status_changed":
            guard let shotId = event.shotId else { return }
            let latestShotJob = jobs
                .filter { $0.shotId == shotId }
                .max(by: { (parseOptionalISODate($0.updatedAt) ?? .distantPast) < (parseOptionalISODate($1.updatedAt) ?? .distantPast) })
            let generationNoun = latestShotJob?.kind == "audio" ? "Sound" : "Shot"
            upsertShotRequestState(shotId) { state in
                let eventDate = parseISODate(event.timestamp)
                let previousStatus = state.lastKnownStatus
                state.lastKnownStatus = event.status ?? state.lastKnownStatus
                state.source = "events"
                if state.requestSentAt == nil {
                    state.requestSentAt = eventDate
                }
                switch event.status {
                case "queued":
                    state.stage = .waiting
                case "generating", "running", "processing":
                    state.stage = .running
                    state.responseReceivedAt = state.responseReceivedAt ?? eventDate
                case "ready":
                    state.stage = .done
                case "failed":
                    state.stage = .failed
                    let backendDetail = latestShotJob?.errorMessage?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let backendError = (backendDetail?.isEmpty == false) ? backendDetail : nil
                    state.errorMessage = backendError ?? state.errorMessage ?? "\(generationNoun) generation failed."
                default:
                    break
                }
                if previousStatus != state.lastKnownStatus {
                    state.lastEventAt = eventDate
                    state.lastMeaningfulTransitionAt = eventDate
                }
            }
            if let index = shots.firstIndex(where: { $0.id == shotId }) {
                let shot = shots[index]
                shots[index] = Shot(
                    id: shot.id,
                    projectId: shot.projectId,
                    prompt: shot.prompt,
                    modelTier: shot.modelTier,
                    status: event.status ?? shot.status,
                    clipUrl: shot.clipUrl,
                    orderIndex: shot.orderIndex,
                    durationSec: shot.durationSec,
                    thumbnailUrl: shot.thumbnailUrl,
                    audioRefs: shot.audioRefs,
                    characterLocks: shot.characterLocks,
                    soundGeneration: shot.soundGeneration,
                    previewTrimInMs: shot.previewTrimInMs,
                    previewTrimOutMs: shot.previewTrimOutMs
                )
            }
            if event.status == "ready" {
                appendDebugEvent("shot final shot=\(shotId) status=ready")
                Task {
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                }
            } else if event.status == "failed" {
                appendDebugEvent("shot final shot=\(shotId) status=failed")
            }
        case "job_status_changed":
            guard let jobId = event.jobId else { return }
            if event.status == "deleted" {
                jobs.removeAll { $0.id == jobId }
                return
            }
            let priorJob = jobs.first(where: { $0.id == jobId })
            let priorJobStatus = priorJob?.status
            let priorJobProgress = priorJob?.progressPct
            upsertJobRequestState(jobId) { state in
                let eventDate = parseISODate(event.timestamp)
                let previousStatus = state.lastKnownStatus
                state.lastKnownStatus = event.status ?? state.lastKnownStatus
                state.source = "events"
                if state.requestSentAt == nil {
                    state.requestSentAt = eventDate
                }
                switch event.status {
                case "queued":
                    state.stage = .waiting
                case "running", "processing":
                    state.stage = .running
                    state.responseReceivedAt = state.responseReceivedAt ?? eventDate
                case "done":
                    state.stage = .done
                case "failed":
                    state.stage = .failed
                    let trimmedPriorErr = priorJob?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let priorErr = (trimmedPriorErr?.isEmpty == false) ? trimmedPriorErr : nil
                    state.errorMessage = priorErr ?? state.errorMessage ?? "Render job failed."
                default:
                    break
                }
                let newStatus = event.status ?? previousStatus
                let statusMoved = newStatus != previousStatus
                let progressMoved = event.progressPct != nil && event.progressPct != priorJobProgress
                if statusMoved || progressMoved {
                    state.lastEventAt = eventDate
                    state.lastMeaningfulTransitionAt = eventDate
                }
            }
            let jobKind = priorJob?.kind ?? "clip"
            if ["clip", "audio"].contains(jobKind),
               let shotIdForClip = event.shotId ?? priorJob?.shotId {
                let statusMoved = (event.status ?? priorJobStatus) != priorJobStatus
                let progressMoved = event.progressPct != nil && event.progressPct != priorJobProgress
                if statusMoved || progressMoved {
                    let eventDate = parseISODate(event.timestamp)
                    upsertShotRequestState(shotIdForClip) { s in
                        s.lastMeaningfulTransitionAt = eventDate
                        s.lastEventAt = eventDate
                        s.source = "events"
                    }
                }
                if event.status == "done" || event.status == "failed" {
                    let eventDate = parseISODate(event.timestamp)
                    upsertShotRequestState(shotIdForClip) { s in
                        s.stage = event.status == "done" ? .done : .failed
                        s.lastKnownStatus = event.status == "done" ? "ready" : "failed"
                        s.lastMeaningfulTransitionAt = eventDate
                        s.lastEventAt = eventDate
                        s.source = "events"
                    }
                }
            }
            if let index = jobs.firstIndex(where: { $0.id == jobId }) {
                let job = jobs[index]
                jobs[index] = Job(
                    id: job.id,
                    projectId: job.projectId,
                    shotId: job.shotId,
                    kind: job.kind,
                    status: event.status ?? job.status,
                    progressPct: event.progressPct ?? job.progressPct,
                    costToUsCents: job.costToUsCents,
                    promptText: job.promptText,
                    modelId: job.modelId,
                    errorMessage: job.errorMessage,
                    outputUrl: job.outputUrl,
                    requestId: job.requestId,
                    idempotencyKey: job.idempotencyKey,
                    invokeState: job.invokeState,
                    falEndpoint: job.falEndpoint,
                    falStatusUrl: job.falStatusUrl,
                    providerEndpoint: job.providerEndpoint,
                    providerStatusCode: job.providerStatusCode,
                    providerResponseSnippet: job.providerResponseSnippet,
                    skippedFeature: job.skippedFeature,
                    featureError: job.featureError,
                    providerAdapter: job.providerAdapter,
                    outputCreated: job.outputCreated,
                    updatedAt: event.timestamp
                )
            } else if event.shotId != nil {
                appendDebugEvent("job event for unknown job id=\(jobId); refreshing snapshot")
                Task {
                    await refreshGenerationStatusSnapshot()
                }
            }
            if event.status == "done" {
                appendDebugEvent("job final job=\(jobId) status=done progress=\(event.progressPct.map(String.init) ?? "n/a")")
                Task {
                    await refreshGenerationStatusSnapshot()
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                }
            } else if event.status == "failed" {
                let errNote = jobs.first(where: { $0.id == jobId })?.errorMessage.map { String($0.prefix(220)) } ?? ""
                appendDebugEvent(
                    "job final job=\(jobId) status=failed progress=\(event.progressPct.map(String.init) ?? "n/a") err=\(errNote)"
                )
                Task {
                    await refreshGenerationStatusSnapshot()
                    await loadSelectedProjectDetails(showLoadingIndicator: false)
                }
            }
        case "shot_deleted":
            guard let shotId = event.shotId else { return }
            shots.removeAll { $0.id == shotId }
            jobs.removeAll { $0.shotId == shotId }
        case "job_deleted":
            guard let jobId = event.jobId else { return }
            jobs.removeAll { $0.id == jobId }
        default:
            Task {
                await loadSelectedProjectDetails(showLoadingIndicator: false)
            }
        }
    }

    private func createShot() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        if isAudioCreationWorkspace {
            guard validateSoundCreationDraftForWorkspace() else { return }
        }
        appendDebugEvent("create shot requested project=\(selectedProjectId)")
        do {
            let durationSec: Int? = isAudioCreationWorkspace
                ? Int(min(600, max(3, scoreDurationSeconds.rounded())))
                : nil
            let soundGeneration: ShotSoundGeneration? = soundGenerationPayloadForCreate()
            let createdShot = try await api.createShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                prompt: shotPromptDraft,
                modelTier: shotModelTierDraft,
                characterLocks: selectedCharacterLockId.isEmpty ? [] : [selectedCharacterLockId],
                durationSec: durationSec,
                soundGeneration: soundGeneration
            )
            if !shots.contains(where: { $0.id == createdShot.id }) {
                var updatedShots = shots
                updatedShots.append(createdShot)
                shots = updatedShots.sorted { lhs, rhs in
                    let left = lhs.orderIndex ?? Int.max
                    let right = rhs.orderIndex ?? Int.max
                    if left != right {
                        return left < right
                    }
                    return lhs.id < rhs.id
                }
            }
            shotPromptDraft = ""
            quotedShotCost = nil
            appendDebugEvent("create shot success shot=\(createdShot.id)")
            if CreationMode(rawValue: creationModeRaw) == .audio {
                shotSoundSourceById[createdShot.id] = "generated"
                selectedSoundBlueprintIdsByShotId[createdShot.id] = draftSoundBlueprintIds
            }
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            appendDebugEvent("create shot failed reason=\(error.localizedDescription)")
            model.errorMessage = error.localizedDescription
        }
    }

    /// Label for Sounds panel: derived from create/upload actions and shot status, not from a user picker.
    private func soundSourceLabel(for shot: Shot) -> String {
        if let raw = shotSoundSourceById[shot.id] {
            return raw == "uploaded" ? "Uploaded" : "Generated"
        }
        let s = shot.status.lowercased()
        if ["queued", "generating", "running", "processing", "ready", "failed"].contains(s) {
            return "Generated"
        }
        return "Generated"
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

    private func performUploadProjectFiles(urls: [URL]) async throws -> [String] {
        guard let selectedProjectId else { return [] }
        var ids: [String] = []
        for url in urls {
            let ref = try await api.uploadProjectFile(
                token: model.bearerToken,
                projectId: selectedProjectId,
                fileURL: url
            )
            ids.append(ref.id)
        }
        return ids
    }

    private func trainCharacter(characterId: String, referenceFileIds: [String]) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            _ = try await api.trainCharacter(
                token: model.bearerToken,
                projectId: selectedProjectId,
                characterId: characterId,
                referenceFileIds: referenceFileIds
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func quoteShot() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let soundDurationSec = isAudioCreationWorkspace
                ? Int(min(600, max(3, scoreDurationSeconds.rounded())))
                : nil
            quotedShotCost = try await api.quoteShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                prompt: shotPromptDraft,
                modelTier: shotModelTierDraft,
                generationKind: isAudioCreationWorkspace ? "sound" : nil,
                durationSec: soundDurationSec
            )
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateShot(shotId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        upsertShotRequestState(shotId) { state in
            state.stage = .requestSent
            state.requestSentAt = state.requestSentAt ?? Date()
            state.lastMeaningfulTransitionAt = state.requestSentAt
            state.responseReceivedAt = nil
            state.errorMessage = nil
            state.source = "local-request"
        }
        appendDebugEvent("generate shot requested shot=\(shotId)")
        do {
            let soundBlueprintIds: [String]? = isAudioCreationWorkspace
                ? Array(selectedSoundBlueprintIdsByShotId[shotId] ?? []).sorted()
                : nil
            let generation = try await api.generateShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shotId,
                soundBlueprintIds: soundBlueprintIds,
                generationKind: isAudioCreationWorkspace ? "sound" : nil
            )
            quotedShotCost = generation.quote
            upsertShotRequestState(shotId) { state in
                state.stage = .responseReceived
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = generation.shot.status
                state.source = "api-response"
            }
            upsertJobRequestState(generation.job.id) { state in
                state.stage = .responseReceived
                state.requestSentAt = state.requestSentAt ?? Date()
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = generation.job.status
                state.source = "api-response"
            }
            appendDebugEvent(
                "generate shot queued shot=\(shotId) job=\(generation.job.id) kind=\(generation.job.kind) jobStatus=\(generation.job.status) shotStatus=\(generation.shot.status)"
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
            await refreshGenerationStatusSnapshot()
        } catch {
            let nsError = error as NSError
            let isAlreadyGenerating = nsError.domain == "CinefuseAPI"
                && nsError.code == 409
                && nsError.localizedDescription.localizedCaseInsensitiveContains("already in progress")
            upsertShotRequestState(shotId) { state in
                state.stage = isAlreadyGenerating ? .waiting : .failed
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.errorMessage = isAlreadyGenerating
                    ? "Shot generation is already in progress. Wait for the current run to finish before retrying."
                    : error.localizedDescription
                state.source = "api-response"
            }
            if isAlreadyGenerating {
                appendDebugEvent("generate shot conflict shot=\(shotId) reason=already in progress")
                model.errorMessage = nil
            } else {
                appendDebugEvent("generate shot failed shot=\(shotId) reason=\(error.localizedDescription)")
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func retryShot(shotId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        await loadSelectedProjectDetails(showLoadingIndicator: false)
        guard let currentShot = shots.first(where: { $0.id == shotId }) else {
            model.errorMessage = "Shot no longer exists. Refresh and try again."
            return
        }
        guard currentShot.status == "failed" else {
            let message = "This shot is no longer failed (now \(currentShot.status)). Retry is only for failed shots. Use Generate for draft/ready, or wait if queued/generating."
            upsertShotRequestState(shotId) { state in
                state.stage = .failed
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = currentShot.status
                state.errorMessage = message
                state.source = "snapshot"
            }
            appendDebugEvent("retry shot conflict-precheck shot=\(shotId) status=\(currentShot.status)")
            model.errorMessage = message
            return
        }
        upsertShotRequestState(shotId) { state in
            state.stage = .requestSent
            state.requestSentAt = state.requestSentAt ?? Date()
            state.lastMeaningfulTransitionAt = state.requestSentAt
            state.responseReceivedAt = nil
            state.errorMessage = nil
            state.source = "local-request"
        }
        do {
            let generation = try await api.retryShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shotId,
                generationKind: isAudioCreationWorkspace ? "sound" : nil
            )
            quotedShotCost = generation.quote
            upsertShotRequestState(shotId) { state in
                state.stage = .responseReceived
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = generation.shot.status
                state.source = "api-response"
            }
            upsertJobRequestState(generation.job.id) { state in
                state.stage = .responseReceived
                state.requestSentAt = state.requestSentAt ?? Date()
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = generation.job.status
                state.source = "api-response"
            }
            await loadSelectedProjectDetails(showLoadingIndicator: false)
            await refreshGenerationStatusSnapshot()
        } catch {
            let nsError = error as NSError
            let errorCode = nsError.userInfo[CinefuseAPIErrorUserInfoKey.errorCode] as? String
            let backendStatus = nsError.userInfo[CinefuseAPIErrorUserInfoKey.currentStatus] as? String
            let isRetryConflict = nsError.domain == "CinefuseAPI"
                && nsError.code == 409
                && errorCode == "SHOT_RETRY_CONFLICT"
            let isAlreadyGenerating = nsError.domain == "CinefuseAPI"
                && nsError.code == 409
                && nsError.localizedDescription.localizedCaseInsensitiveContains("already in progress")
            let conflictMessage = "This shot is no longer failed (now \(backendStatus ?? "unknown")). Retry is only for failed shots. Use Generate for draft/ready, or wait if queued/generating."
            upsertShotRequestState(shotId) { state in
                state.stage = .failed
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = backendStatus ?? state.lastKnownStatus
                state.errorMessage = isRetryConflict
                    ? conflictMessage
                    : isAlreadyGenerating
                    ? "Shot generation is already in progress. Wait for the current run to finish before retrying."
                    : error.localizedDescription
                state.source = "api-response"
            }
            if isRetryConflict {
                appendDebugEvent("retry shot conflict shot=\(shotId) backendStatus=\(backendStatus ?? "unknown")")
                await loadSelectedProjectDetails(showLoadingIndicator: false)
                model.errorMessage = conflictMessage
            } else {
                model.errorMessage = isAlreadyGenerating ? nil : error.localizedDescription
            }
        }
    }

    private func restartQueuedShot(shotId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        await loadSelectedProjectDetails(showLoadingIndicator: false)
        guard let currentShot = shots.first(where: { $0.id == shotId }) else {
            model.errorMessage = "Shot no longer exists. Refresh and try again."
            return
        }
        guard currentShot.status == "queued" else {
            model.errorMessage = "Queued restart is only available for queued shots (current: \(currentShot.status))."
            return
        }
        let queuedJobs = jobs.filter { $0.shotId == shotId && $0.status == "queued" }
        guard !queuedJobs.isEmpty else {
            model.errorMessage = "No queued job found for this shot. Refresh and try Generate again."
            return
        }
        do {
            for job in queuedJobs {
                try await api.deleteJob(
                    token: model.bearerToken,
                    projectId: selectedProjectId,
                    jobId: job.id
                )
                jobs.removeAll { $0.id == job.id }
                jobRequestStateById.removeValue(forKey: job.id)
            }
            appendDebugEvent("restart queued shot deleted \(queuedJobs.count) queued job(s) shot=\(shotId)")
            await generateShot(shotId: shotId)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func retryOrRestartShot(shotId: String) async {
        await loadSelectedProjectDetails(showLoadingIndicator: false)
        guard let currentShot = shots.first(where: { $0.id == shotId }) else {
            model.errorMessage = "Shot no longer exists. Refresh and try again."
            return
        }
        if currentShot.status == "queued" {
            await restartQueuedShot(shotId: shotId)
            return
        }
        await retryShot(shotId: shotId)
    }

    private func deleteShotFromProject(shotId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            try await api.deleteShot(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shotId
            )
            shots.removeAll { $0.id == shotId }
            jobs.removeAll { $0.shotId == shotId }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func createJob() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let createdJob = try await api.createJob(
                token: model.bearerToken,
                projectId: selectedProjectId,
                kind: jobKindDraft
            )
            upsertJobRequestState(createdJob.id) { state in
                state.stage = .responseReceived
                state.requestSentAt = state.requestSentAt ?? Date()
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = createdJob.status
                state.source = "api-response"
            }
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func retryJob(jobId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            let generation = try await api.retryJob(
                token: model.bearerToken,
                projectId: selectedProjectId,
                jobId: jobId
            )
            quotedShotCost = generation.quote
            await loadSelectedProjectDetails(showLoadingIndicator: false)
            await refreshGenerationStatusSnapshot()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func retryOrRestartJob(jobId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        await loadSelectedProjectDetails(showLoadingIndicator: false)
        guard let job = jobs.first(where: { $0.id == jobId }) else {
            model.errorMessage = "Job no longer exists. Refresh and try again."
            return
        }
        guard job.status == "queued" || job.status == "failed" else {
            model.errorMessage = "Retry is available for failed or queued jobs (current: \(job.status))."
            return
        }
        if job.status == "failed" {
            await retryJob(jobId: jobId)
            return
        }
        do {
            try await api.deleteJob(
                token: model.bearerToken,
                projectId: selectedProjectId,
                jobId: job.id
            )
            jobs.removeAll { $0.id == job.id }
            jobRequestStateById.removeValue(forKey: job.id)
            appendDebugEvent("restart queued job deleted job=\(job.id) kind=\(job.kind)")
            if let shotId = job.shotId {
                await generateShot(shotId: shotId)
            } else {
                let recreated = try await api.createJob(
                    token: model.bearerToken,
                    projectId: selectedProjectId,
                    kind: job.kind
                )
                upsertJobRequestState(recreated.id) { state in
                    state.stage = .responseReceived
                    state.requestSentAt = state.requestSentAt ?? Date()
                    state.responseReceivedAt = Date()
                    state.lastMeaningfulTransitionAt = state.responseReceivedAt
                    state.lastKnownStatus = recreated.status
                    state.source = "api-response"
                }
                await loadSelectedProjectDetails(showLoadingIndicator: false)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func deleteJobFromProject(jobId: String) async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil
        do {
            try await api.deleteJob(
                token: model.bearerToken,
                projectId: selectedProjectId,
                jobId: jobId
            )
            jobs.removeAll { $0.id == jobId }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func renameSelectedProject(title: String) async {
        guard let selectedProjectId else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        model.errorMessage = nil
        do {
            let updated = try await api.renameProject(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: normalized
            )
            if let index = model.projects.firstIndex(where: { $0.id == selectedProjectId }) {
                model.projects[index] = updated
            }
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

    /// Reorders only shots that carry sound metadata; silent video clips stay in place in the full project shot list.
    private func reorderAudibleShots(from: IndexSet, to: Int) async {
        guard let selectedProjectId else { return }
        let sorted = shots.sorted { lhs, rhs in
            let leftIndex = lhs.orderIndex ?? Int.max
            let rightIndex = rhs.orderIndex ?? Int.max
            if leftIndex == rightIndex {
                return lhs.id < rhs.id
            }
            return leftIndex < rightIndex
        }
        var audible = sorted.filter {
            $0.qualifiesForAudioModeLists(
                audioTracks: audioTracks,
                syncedLocalRecords: localFileRecordsByRemoteURL,
                audioJobs: jobs
            )
        }
        audible.move(fromOffsets: from, toOffset: to)
        var qi = 0
        let merged = sorted.map { shot -> Shot in
            if shot.qualifiesForAudioModeLists(
                audioTracks: audioTracks,
                syncedLocalRecords: localFileRecordsByRemoteURL,
                audioJobs: jobs
            ) {
                let next = audible[qi]
                qi += 1
                return next
            }
            return shot
        }
        shots = merged
        do {
            _ = try await api.reorderTimelineShots(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotIds: merged.map(\.id)
            )
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateDialogueTrack() async {
        guard let selectedProjectId else { return }
        do {
            let result = try await api.generateDialogue(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shots.first?.id,
                title: audioTrackTitleDraft,
                laneIndex: 0,
                startMs: 0,
                durationMs: 4000
            )
            noteAudioGenerationOutcome(result, label: "Dialogue")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func scoreStylePromptForGeneration() -> String {
        let draft = shotPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            return draft
        }
        return audioTrackTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same rules as the former standalone score action: style prompt required (except custom lyrics still need a style line).
    private func validateSoundCreationDraftForWorkspace() -> Bool {
        let style = scoreStylePromptForGeneration().trimmingCharacters(in: .whitespacesAndNewlines)
        switch scoreLyricsModeSelection {
        case .custom:
            let lyrics = scoreCustomLyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if lyrics.isEmpty {
                model.errorMessage =
                    "Add lyrics for custom mode, or switch to Instrumental or Lyrics (auto)."
                return false
            }
            if style.isEmpty {
                model.errorMessage = "Add a style prompt (shot or draft) for custom lyrics."
                return false
            }
        case .instrumental, .auto:
            if style.isEmpty {
                model.errorMessage =
                    "Add a prompt on the selected sound or in the draft so the score has a style."
                return false
            }
        }
        return true
    }

    private func soundGenerationPayloadForCreate() -> ShotSoundGeneration? {
        guard isAudioCreationWorkspace else { return nil }
        switch scoreLyricsModeSelection {
        case .instrumental:
            return ShotSoundGeneration(lyricsMode: "instrumental", lyricsText: nil)
        case .auto:
            return ShotSoundGeneration(lyricsMode: "auto", lyricsText: nil)
        case .custom:
            let lyrics = scoreCustomLyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return ShotSoundGeneration(lyricsMode: "custom", lyricsText: lyrics)
        }
    }

    private func generateScoreTrack() async {
        guard let selectedProjectId else { return }
        model.errorMessage = nil

        let durationSecs = isAudioCreationWorkspace ? scoreDurationSeconds : 10
        let durationMs = Int(min(600_000, max(3000, durationSecs * 1000)))

        let titleTrimmed = audioTrackTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleForTrack = titleTrimmed.isEmpty ? "Score bed" : titleTrimmed

        var lyricsModeArg: String?
        var lyricsTextArg: String?

        if isAudioCreationWorkspace {
            switch scoreLyricsModeSelection {
            case .instrumental:
                lyricsModeArg = "instrumental"
            case .auto:
                lyricsModeArg = "auto"
            case .custom:
                lyricsModeArg = "custom"
                let lyrics = scoreCustomLyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if lyrics.isEmpty {
                    model.errorMessage = "Add lyrics for custom mode, or switch to Instrumental or Lyrics (auto)."
                    return
                }
                lyricsTextArg = lyrics
            }
            let style = scoreStylePromptForGeneration()
            if lyricsModeArg != "custom", style.isEmpty {
                model.errorMessage = "Add a prompt on the selected sound or in the draft so the score has a style."
                return
            }
            if lyricsModeArg == "custom", style.isEmpty {
                model.errorMessage = "Add a style prompt (shot or draft) for custom lyrics."
                return
            }
        } else {
            lyricsModeArg = "instrumental"
        }

        let stylePrompt = scoreStylePromptForGeneration()

        do {
            let result = try await api.generateScore(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: titleForTrack,
                laneIndex: 1,
                startMs: 0,
                durationMs: durationMs,
                prompt: stylePrompt.isEmpty ? nil : stylePrompt,
                mood: nil,
                lyricsMode: lyricsModeArg,
                lyricsText: lyricsTextArg,
                forceInstrumental: nil
            )
            noteAudioGenerationOutcome(result, label: "Score")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateSFXTrack() async {
        guard let selectedProjectId else { return }
        do {
            let result = try await api.generateSFX(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: audioTrackTitleDraft.isEmpty ? "Foley accent" : audioTrackTitleDraft,
                laneIndex: 2,
                startMs: 0,
                durationMs: 2500
            )
            noteAudioGenerationOutcome(result, label: "SFX")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func mixAudioTrack() async {
        guard let selectedProjectId else { return }
        do {
            let result = try await api.mixAudio(
                token: model.bearerToken,
                projectId: selectedProjectId,
                title: "Scene mixdown",
                laneIndex: 3,
                startMs: 0,
                durationMs: 10000
            )
            noteAudioGenerationOutcome(result, label: "Mix")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func generateLipSyncTrack() async {
        guard let selectedProjectId else { return }
        do {
            let result = try await api.lipsyncAudio(
                token: model.bearerToken,
                projectId: selectedProjectId,
                shotId: shots.first?.id,
                title: "Lip-sync pass",
                laneIndex: 0,
                startMs: 0,
                durationMs: 4000
            )
            noteAudioGenerationOutcome(result, label: "Lip-sync")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func noteAudioGenerationOutcome(_ result: AudioGenerationAPIResponse, label: String) {
        if result.skipped == true {
            let detail = result.featureError?.detail
                ?? result.featureError?.reason
                ?? "Provider could not complete this feature."
            appendDebugEvent("audio skipped \(label) job=\(result.job.id) detail=\(detail)")
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
        let requestSentAt = Date()
        appendDebugEvent("export requested project=\(selectedProjectId) target=\(exportPublishTarget)")
        do {
            let effectivePublishTarget = exportPublishTarget == "pubfuse" ? "pubfuse" : "none"
            let result = try await api.exportFinal(
                token: model.bearerToken,
                projectId: selectedProjectId,
                resolution: exportResolution,
                captionsEnabled: exportCaptionsEnabled,
                includeArchive: exportIncludeArchive,
                publishTarget: effectivePublishTarget
            )
            upsertJobRequestState(result.id) { state in
                state.stage = .responseReceived
                state.requestSentAt = state.requestSentAt ?? requestSentAt
                state.responseReceivedAt = Date()
                state.lastMeaningfulTransitionAt = state.responseReceivedAt
                state.lastKnownStatus = result.status
                state.source = "api-response"
            }
            appendDebugEvent("export queued job=\(result.id)")
            await loadSelectedProjectDetails(showLoadingIndicator: false)
        } catch {
            appendDebugEvent("export failed reason=\(error.localizedDescription)")
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
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    let localThumbnailURLByShotId: [String: URL]
    let localThumbnailURLByJobId: [String: URL]
    let debugEventLog: [String]
    let shotRequestStateById: [String: RenderRequestState]
    let jobRequestStateById: [String: RenderRequestState]
    @Binding var showDebugWindow: Bool
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
    @Binding var scoreDurationSeconds: Double
    @Binding var scoreLyricsModeSelection: ScoreGenerationLyricsMode
    @Binding var scoreCustomLyricsDraft: String

    let onCloseProject: () -> Void
    let onDeleteProject: () -> Void
    let onRenameProject: (String) -> Void
    let onCreateCharacter: () -> Void
    let onTrainCharacter: (String, [String]) -> Void
    let uploadProjectFiles: ([URL]) async throws -> [String]
    let onGenerateStoryboard: () -> Void
    let onReviseScene: (StoryScene, String) -> Void
    let onQuote: () -> Void
    let onCreateShot: () -> Void
    let onGenerateShot: (String) -> Void
    let onRetryShot: (String) -> Void
    let onDeleteShot: (String) -> Void
    let onCreateJob: () -> Void
    let onRetryJob: (String) -> Void
    let onDeleteJob: (String) -> Void
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
    let onOpenDebugWindow: () -> Void
    let showTooltips: Bool
    @Binding var creationModeRaw: String
    @Binding var soundBlueprints: [SoundBlueprint]
    @Binding var selectedSoundBlueprintIdsByShotId: [String: Set<String>]
    @Binding var draftSoundBlueprintIds: Set<String>
    let soundSourceLabel: (Shot) -> String
    @Binding var soundTagsDraft: String
    let onCreateSoundBlueprint: (CreateSoundBlueprintRequest) -> Void
    /// Downloads and plays a project file used as a blueprint reference.
    let onPlayBlueprintReferenceFile: (String) -> Void
    let onExportAudioMix: () -> Void
    let onAddAudioTrack: () -> Void
    /// Video mode: create empty audio lane at index 0 or 1 for timeline layering.
    let onEnsureVideoLaneSlot: (Int) async -> Void
    let onRefreshStatusDetails: () async -> Void
    /// Saves preview trim (ms) for a shot after handle edits.
    let onPersistShotPreviewTrim: (String, Int?, Int?) async -> Void
    /// When true, center preview fills the top workspace (side columns hidden).
    @Binding var isPreviewFullscreen: Bool
    @Binding var mobileEditorPresentedPanel: MobileEditorPresentedPanel?
    @EnvironmentObject private var editorPlaybackState: EditorPlaybackState
    @Environment(\.editorMobileInspectorSheet) private var editorMobileInspectorSheet
    @AppStorage("cinefuse.editor.leftPaneWidth") private var leftPaneWidth: Double = 460
    @AppStorage("cinefuse.editor.rightPaneWidth") private var rightPaneWidth: Double = 460
    @AppStorage("cinefuse.editor.bottomPaneHeight") private var bottomPaneHeight: Double = 240
    @AppStorage("cinefuse.editor.showLeftPane") private var showLeftPane = true
    @AppStorage("cinefuse.editor.showRightPane") private var showRightPane = true
    @AppStorage("cinefuse.editor.showBottomPane") private var showBottomPane = true
    @AppStorage("cinefuse.editor.showAudioPanel") private var showAudioPanel = true
    @AppStorage("cinefuse.editor.showJobsPanel") private var showJobsPanel = true
    @AppStorage("cinefuse.editor.swapSidePanes") private var swapSidePanes = false
    @AppStorage("cinefuse.editor.workspacePreset") private var workspacePresetRaw = EditorWorkspacePreset.editing.rawValue
    @AppStorage("cinefuse.editor.collapse.timeline") private var collapseTimelinePanel = false
    @AppStorage("cinefuse.editor.collapse.preview") private var collapsePreviewPanel = false
    @AppStorage("cinefuse.editor.collapse.storyboard") private var collapseStoryboardPanel = false
    @AppStorage("cinefuse.editor.collapse.characters") private var collapseCharacterPanel = false
    @AppStorage("cinefuse.editor.collapse.shots") private var collapseShotsPanel = false
    @AppStorage("cinefuse.editor.collapse.export") private var collapseExportPanel = false
    @AppStorage("cinefuse.editor.collapse.audio") private var collapseAudioPanel = false
    @AppStorage("cinefuse.editor.collapse.jobs") private var collapseJobsPanel = false
    @AppStorage("cinefuse.editor.collapse.soundBlueprints") private var collapseSoundBlueprintsPanel = false
    /// Allocated height for the timeline strip when expanded (drag the handle under the timeline to resize).
    @AppStorage("cinefuse.editor.timelineStripHeight") private var timelineStripHeight: Double = 220
    /// Caps the timeline column (strip + optional video audio layers) so it scrolls vertically instead of pushing the workspace away.
    @AppStorage("cinefuse.editor.timeline.verticalScrollMaxHeight") private var timelineVerticalScrollMaxHeight: Double = 540
    @State private var selectedTimelineShotId: String?
    @State private var trackSyncModes: [Int: AudioTrackSyncMode] = [:]
    @State private var laneVolumeByIndex: [Int: Float] = [:]
    @State private var masterMixGain: Float = 1.0
    @State private var isRenamingProjectTitle = false
    @State private var projectTitleDraft = ""
    @State private var previewPlaybackRequestToken = 0
    @State private var isPreviewPoppedOut = false
    /// Timeline strip expands to fill the editor; hides preview workspace until exited (card header control).
    @State private var isTimelineFullscreen = false
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    @State private var previewPopoutWindowController: PreviewPopoutWindowController?
#endif

    private var editorLayoutTraits: EditorLayoutTraits {
#if os(iOS)
        EditorLayoutTraits.iOS(horizontalSizeClass: horizontalSizeClass)
#else
        .desktopLike
#endif
    }

    private var isAudioCreationWorkspace: Bool {
        CreationMode(rawValue: creationModeRaw) == .audio
    }

    /// When sheet-based side chrome is active, inline columns are hidden so width stays with the preview.
    private var effectiveShowLeftPane: Bool {
        !editorLayoutTraits.useSheetBasedSidePanels && showLeftPane
    }

    private var effectiveShowRightPane: Bool {
        !editorLayoutTraits.useSheetBasedSidePanels && showRightPane
    }

    private var isRenderWorkspace: Bool {
        (EditorWorkspacePreset(rawValue: workspacePresetRaw) ?? .editing) == .render
    }

    private var effectiveCreationMode: CreationMode {
        CreationMode(rawValue: creationModeRaw) ?? .video
    }

    private var isAudioCreationMode: Bool {
        effectiveCreationMode == .audio
    }

    /// Layered audio lanes (dialogue/score/SFX/mix) attach to the video timeline — not shown in Audio Creation mode.
    private var showVideoAudioLanesPanel: Bool {
        showAudioPanel && !isAudioCreationMode
    }

    /// Inline render preset lanes (desktop / iPad when bottom strip is allowed); iPhone uses sheet launchpad only.
    private var shouldShowInlineRenderWorkspacePanels: Bool {
#if os(iOS)
        editorLayoutTraits.useInlineBottomRegion
#else
        true
#endif
    }

    private var latestExportArtifactStatus: ArtifactStatusPresentation? {
        guard let latestExportJob = jobs
            .filter({ $0.kind == "export" || $0.kind == "audio_export" })
            .max(by: { parseDate($0.updatedAt) < parseDate($1.updatedAt) }) else {
            return nil
        }
        let localRecord = latestExportJob.outputUrl.flatMap { localFileRecordsByRemoteURL[$0] }
        return artifactStatusPresentation(
            job: latestExportJob,
            localRecord: localRecord,
            requestState: jobRequestStateById[latestExportJob.id]
        )
    }

    private func parseDate(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

#if os(iOS)
    /// When the render preset is used without inline bottom panels, surface the same tools via sheets.
    private var renderWorkspaceMobileLaunchpad: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Render workspace")
                .font(CinefuseTokens.Typography.sectionTitle)
            Text("Open audio lanes and jobs as full-screen panels.")
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            HStack(spacing: CinefuseTokens.Spacing.s) {
                if !isAudioCreationMode {
                    Button {
                        showAudioPanel = true
                        mobileEditorPresentedPanel = .audioLanes
                    } label: {
                        Label("Audio lanes", systemImage: "waveform")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
                Button {
                    showJobsPanel = true
                    mobileEditorPresentedPanel = .jobs
                } label: {
                    Label("Jobs", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(CinefuseTokens.Spacing.s)
    }

    /// Single scroll surface for iPhone / iPad sheets — avoids nested `ScrollView`s and empty vertical gaps from unconstrained heights.
    @ViewBuilder
    private func mobileInspectorSheetContents(for panel: MobileEditorPresentedPanel) -> some View {
        ScrollView {
            Group {
                switch panel {
                case .leftInspector:
                    leftPaneStack
                case .rightInspector:
                    rightPaneStack
                case .audioLanes:
                    audioLanesPanelCard
                case .jobs:
                    jobsPanelMobileSheet
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.editorMobileInspectorSheet, true)
    }
#endif

    var body: some View {
        Group {
            if let project {
                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                    header(project: project)

                    if isLoadingProjectDetails {
                        ProgressView("Refreshing timeline and job states...")
                            .font(CinefuseTokens.Typography.caption)
                    }

                    if !isRenderWorkspace {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                if collapseTimelinePanel {
                                    HorizontalTimelineTrack(
                                        shots: shotsForSoundOrVideoTimeline,
                                        jobs: jobs,
                                        localThumbnailURLByShotId: localThumbnailURLByShotId,
                                        localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                                        shotRequestStateById: shotRequestStateById,
                                        selectedShotId: $selectedTimelineShotId,
                                        onPreviewShot: { shotId in
                                            selectedTimelineShotId = shotId
                                            previewPlaybackRequestToken += 1
                                        },
                                        onMoveShot: onReorderShots,
                                        showTooltips: showTooltips,
                                        themePalette: timelineThemeMode.palette,
                                        isCollapsed: $collapseTimelinePanel,
                                        clipVisualStyle: isAudioCreationMode ? .audioWaveform : .videoThumbnail,
                                        isTimelineFullscreen: $isTimelineFullscreen
                                    )
                                } else {
                                    VStack(spacing: 0) {
                                        HorizontalTimelineTrack(
                                            shots: shotsForSoundOrVideoTimeline,
                                            jobs: jobs,
                                            localThumbnailURLByShotId: localThumbnailURLByShotId,
                                            localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                                            shotRequestStateById: shotRequestStateById,
                                            selectedShotId: $selectedTimelineShotId,
                                            onPreviewShot: { shotId in
                                                selectedTimelineShotId = shotId
                                                previewPlaybackRequestToken += 1
                                            },
                                            onMoveShot: onReorderShots,
                                            showTooltips: showTooltips,
                                            themePalette: timelineThemeMode.palette,
                                            isCollapsed: $collapseTimelinePanel,
                                            clipVisualStyle: isAudioCreationMode ? .audioWaveform : .videoThumbnail,
                                            isTimelineFullscreen: $isTimelineFullscreen
                                        )
                                        .frame(height: CGFloat(clampedTimelineStripHeight(timelineStripHeight)), alignment: .top)
                                        .clipped()
                                        HorizontalPanelHandle(accessibilityLabel: "Resize timeline height") { delta in
                                            timelineStripHeight = clampedTimelineStripHeight(timelineStripHeight - delta)
                                        }
                                    }
                                }

                                if !isAudioCreationMode {
                                    videoLayerAudioUnderTimeline
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: isTimelineFullscreen ? .infinity : CGFloat(timelineVerticalScrollMaxHeight))
                        .layoutPriority(isTimelineFullscreen ? 1 : 0)
                    }

                    if isRenderWorkspace || !isTimelineFullscreen {
                    GeometryReader { geometry in
                        let totalWidth = Double(max(geometry.size.width, 320))
                        let totalHeight = Double(max(geometry.size.height, 280))
                        let showsBottomRegion = editorLayoutTraits.useInlineBottomRegion
                            && showBottomPane
                            && (showVideoAudioLanesPanel || showJobsPanel)
                        let bottomHandleHeight = Double(CinefuseTokens.Control.splitterHitArea)
                        let minTopWorkspaceHeight = Double(CinefuseTokens.Control.minTopWorkspaceHeight)
                        let maxBottomByAvailableSpace = max(
                            0,
                            totalHeight - minTopWorkspaceHeight - (showsBottomRegion ? bottomHandleHeight : 0)
                        )
                        let minBottomPanelHeight = Double(CinefuseTokens.Control.minBottomPanelHeight)
                        let sanitizedBottomHeight: Double = {
                            guard showsBottomRegion else { return 0 }
                            if maxBottomByAvailableSpace >= minBottomPanelHeight {
                                return min(max(bottomPaneHeight, minBottomPanelHeight), maxBottomByAvailableSpace)
                            }
                            return maxBottomByAvailableSpace
                        }()
                        let visibleBottomPanelCount = (showVideoAudioLanesPanel ? 1 : 0) + (showJobsPanel ? 1 : 0)
                        let collapsedBottomPanelCount = (showVideoAudioLanesPanel && collapseAudioPanel ? 1 : 0)
                            + (showJobsPanel && collapseJobsPanel ? 1 : 0)
                        let allVisibleBottomPanelsCollapsed = visibleBottomPanelCount > 0
                            && visibleBottomPanelCount == collapsedBottomPanelCount
                        let collapsedBottomHeight = 78.0
                        let effectiveBottomHeight = allVisibleBottomPanelsCollapsed
                            ? min(sanitizedBottomHeight, collapsedBottomHeight)
                            : sanitizedBottomHeight
                        let topWorkspaceHeight = max(
                            0,
                            totalHeight - effectiveBottomHeight - (showsBottomRegion ? bottomHandleHeight : 0)
                        )
                        let sideFrame = paneLayout(totalWidth: totalWidth)
                        let previewFs = isPreviewFullscreen
                        let showsLeftPanel = effectiveShowLeftPane && sideFrame.left > 1 && !previewFs
                        let showsRightPanel = effectiveShowRightPane && sideFrame.right > 1 && !previewFs

                        VStack(spacing: 0) {
                            if isRenderWorkspace {
                                if shouldShowInlineRenderWorkspacePanels {
                                    HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
                                        if showVideoAudioLanesPanel {
                                            audioLanesPanelCard
                                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                                        }
                                        if showJobsPanel {
                                            jobsPanelCard
                                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                                        }
                                        if !showVideoAudioLanesPanel && !showJobsPanel {
                                            EmptyStateCard(
                                                title: "Render panels hidden",
                                                message: "Enable Audio Lanes or Jobs from the top menu to continue."
                                            )
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        }
                                    }
                                    .padding(.top, CinefuseTokens.Spacing.s)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                } else {
#if os(iOS)
                                    renderWorkspaceMobileLaunchpad
                                        .frame(maxHeight: .infinity, alignment: .top)
#else
                                    EmptyView()
#endif
                                }
                            } else {
                                Group {
                                    if previewFs && !shouldUseEmbeddedPopoutPreview {
                                        centerPreviewPanel
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                            .transition(.opacity)
                                    } else if shouldUseEmbeddedPopoutPreview {
                                        embeddedPopoutPreviewPanel
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    } else {
                                        HStack(alignment: .top, spacing: 0) {
                                            if showsLeftPanel {
                                                sidePaneContainer {
                                                    if swapSidePanes {
                                                        rightPaneContent
                                                    } else {
                                                        leftPaneContent
                                                    }
                                                }
                                                .frame(width: isPreviewPoppedOut ? nil : CGFloat(sideFrame.left))
                                                .frame(maxWidth: isPreviewPoppedOut ? .infinity : nil)
                                                .frame(minWidth: 0, maxHeight: .infinity)
                                                if !isPreviewPoppedOut {
                                                    VerticalPanelHandle(
                                                        accessibilityLabel: "Resize left and center panels"
                                                    ) { delta in
                                                        leftPaneWidth = clampedLeftPaneWidth(
                                                            leftPaneWidth + delta,
                                                            totalWidth: totalWidth,
                                                            opposingPaneWidth: sideFrame.right
                                                        )
                                                    }
                                                }
                                            }

                                            if !isPreviewPoppedOut {
                                                centerPreviewPanel
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                            }

                                            if showsRightPanel {
                                                if !isPreviewPoppedOut {
                                                    VerticalPanelHandle(
                                                        accessibilityLabel: "Resize center and right panels"
                                                    ) { delta in
                                                        rightPaneWidth = clampedRightPaneWidth(
                                                            rightPaneWidth - delta,
                                                            totalWidth: totalWidth,
                                                            opposingPaneWidth: sideFrame.left
                                                        )
                                                    }
                                                }
                                                sidePaneContainer {
                                                    if swapSidePanes {
                                                        leftPaneContent
                                                    } else {
                                                        rightPaneContent
                                                    }
                                                }
                                                .frame(width: isPreviewPoppedOut ? nil : CGFloat(sideFrame.right))
                                                .frame(maxWidth: isPreviewPoppedOut ? .infinity : nil)
                                                .frame(minWidth: 0, maxHeight: .infinity)
                                            }
                                        }
                                    }
                                }
                                .frame(height: CGFloat(topWorkspaceHeight))
                                .clipped()
                                }

                                if showsBottomRegion {
                                    HorizontalPanelHandle(accessibilityLabel: "Resize jobs and main workspace") { delta in
                                        bottomPaneHeight = clampedBottomPaneHeight(
                                            bottomPaneHeight - delta,
                                            totalHeight: totalHeight
                                        )
                                    }
                                    HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
                                        if showVideoAudioLanesPanel {
                                            audioLanesPanelCard
                                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                                        }
                                        if showJobsPanel {
                                            jobsPanelCard
                                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                                        }
                                    }
                                    .padding(.top, CinefuseTokens.Spacing.s)
                                    .frame(height: CGFloat(effectiveBottomHeight), alignment: .top)
                                    .clipped()
                                }
                        }
                    }
                    .frame(minHeight: 380)
                    .animation(CinefuseTokens.Motion.panel, value: isPreviewPoppedOut)
                    .animation(CinefuseTokens.Motion.panel, value: showLeftPane)
                    .animation(CinefuseTokens.Motion.panel, value: showRightPane)
                    .animation(CinefuseTokens.Motion.panel, value: showBottomPane)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "film.stack",
                    description: Text("Choose a project from the sidebar or create one to get started.")
                )
            }
        }
#if os(iOS)
        .sheet(item: $mobileEditorPresentedPanel) { panel in
            NavigationStack {
                mobileInspectorSheetContents(for: panel)
                    .navigationTitle(panel.navigationTitle(isAudioCreationMode: isAudioCreationMode))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                mobileEditorPresentedPanel = nil
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
#endif
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
        .onChange(of: project?.id) { _, _ in
            isTimelineFullscreen = false
            guard let project else { return }
            projectTitleDraft = project.title
            isRenamingProjectTitle = false
        }
        .onChange(of: project?.title) { _, value in
            guard let value else { return }
            if !isRenamingProjectTitle {
                projectTitleDraft = value
            }
        }
        .onChange(of: isPreviewFullscreen) { _, full in
            if full {
                isPreviewPoppedOut = false
                isTimelineFullscreen = false
            }
        }
        .onChange(of: isTimelineFullscreen) { _, full in
            if full {
                isPreviewFullscreen = false
            }
        }
        .onChange(of: workspacePresetRaw) { _, _ in
            if (EditorWorkspacePreset(rawValue: workspacePresetRaw) ?? .editing) == .render {
                isTimelineFullscreen = false
            }
        }
        .onChange(of: isPreviewPoppedOut) { _, isPoppedOut in
            if isPoppedOut {
                isPreviewFullscreen = false
            }
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
            if isPoppedOut {
                presentPreviewPopoutWindow()
            } else {
                dismissPreviewPopoutWindow()
            }
#endif
        }
        .onChange(of: shotClipSignature) { _, _ in
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
            refreshPreviewPopoutWindowContent()
#endif
        }
        .onChange(of: selectedTimelineShotId) { _, _ in
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
            refreshPreviewPopoutWindowContent()
#endif
        }
        .onChange(of: previewPlaybackRequestToken) { _, _ in
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
            refreshPreviewPopoutWindowContent()
#endif
        }
        .onChange(of: audioLaneLayoutSignature) { _, _ in
            for track in audioTracks {
                if laneVolumeByIndex[track.laneIndex] == nil {
                    laneVolumeByIndex[track.laneIndex] = 1
                }
            }
        }
        .onChange(of: audioTrackMediaSignature) { _, _ in
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
            refreshPreviewPopoutWindowContent()
#endif
        }
    }

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private func previewPopoutRootView() -> some View {
        embeddedPopoutPreviewPanel
        .frame(minWidth: 760, minHeight: 440)
        .padding(CinefuseTokens.Spacing.s)
        .background(CinefuseTokens.ColorRole.canvas)
        .environmentObject(editorPlaybackState)
    }

    private func presentPreviewPopoutWindow() {
        if let windowController = previewPopoutWindowController {
            windowController.update(rootView: previewPopoutRootView())
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            windowController.window?.orderFrontRegardless()
            return
        }
        let controller = PreviewPopoutWindowController(
            rootView: previewPopoutRootView(),
            onWindowClose: {
                isPreviewPoppedOut = false
                previewPopoutWindowController = nil
            }
        )
        previewPopoutWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
        if let keyWindow = NSApp.keyWindow, let popoutWindow = controller.window {
            keyWindow.addChildWindow(popoutWindow, ordered: .above)
        }
    }

    private func dismissPreviewPopoutWindow() {
        previewPopoutWindowController?.close()
        previewPopoutWindowController = nil
    }

    private func refreshPreviewPopoutWindowContent() {
        previewPopoutWindowController?.update(rootView: previewPopoutRootView())
    }
#endif

    private var shouldUseEmbeddedPopoutPreview: Bool {
        guard isPreviewPoppedOut else { return false }
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
        guard let window = previewPopoutWindowController?.window else {
            return true
        }
        return !window.isVisible
#else
        return true
#endif
    }

    /// In Audio creation mode, the horizontal timeline and audio preview only include shots that have linked audio metadata or an audio lane with a source.
    private var shotsForSoundOrVideoTimeline: [Shot] {
        if isAudioCreationMode {
            return sortedShots.filter { shotQualifiesForAudioTimeline($0) }
        }
        return sortedShots
    }

    /// Sounds panel in audio mode: same rows as the sound timeline, plus drafts and in-flight rows (no `clipUrl` yet). Hides finished silent video (`clipUrl` set, no sound linkage).
    private var shotsForSoundsPanelIfNeeded: [Shot] {
        guard isAudioCreationMode else { return sortedShots }
        return sortedShots.filter { shotQualifiesForSoundsPanel($0) }
    }

    /// Timeline + preview: shot has API/audio linkage **or** synced local audio on disk for `clipUrl`.
    private func shotQualifiesForAudioTimeline(_ shot: Shot) -> Bool {
        shot.qualifiesForAudioModeLists(
            audioTracks: audioTracks,
            syncedLocalRecords: localFileRecordsByRemoteURL,
            audioJobs: jobs
        )
    }

    /// Sounds panel: include timeline-qualified shots **or** drafts / queued rows with no `clipUrl` yet.
    private func shotQualifiesForSoundsPanel(_ shot: Shot) -> Bool {
        if shotQualifiesForAudioTimeline(shot) {
            return true
        }
        let clip = shot.clipUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clip.isEmpty
    }

    private var timelineShotBoundaries: [TimelineShotBoundary] {
        var cursorMs = 0
        return shotBoundarySource.map { shot in
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

    private var shotBoundarySource: [Shot] {
        if isAudioCreationMode {
            return sortedShots.filter { shotQualifiesForAudioTimeline($0) }
        }
        return sortedShots
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

    private var shotClipSignature: String {
        shots.map { "\($0.id):\($0.clipUrl ?? "")" }.joined(separator: "|")
    }

    private var audioTrackMediaSignature: String {
        audioTracks.map { "\($0.id):\($0.sourceUrl ?? "")" }.joined(separator: "|")
    }

    private var audioLaneLayoutSignature: String {
        audioTracks.map { "\($0.id):\($0.laneIndex)" }.joined(separator: "|")
    }

    /// Video mode: two fixed lanes (0, 1) under the picture timeline for layering audio over the edit.
    @ViewBuilder
    private var videoLayerAudioUnderTimeline: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            Text("Audio over video")
                .font(CinefuseTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            ForEach(0..<2, id: \.self) { laneIndex in
                videoTimelineOverlayLaneBlock(laneIndex: laneIndex)
            }
        }
        .padding(.top, CinefuseTokens.Spacing.xs)
    }

    @ViewBuilder
    private func videoTimelineOverlayLaneBlock(laneIndex: Int) -> some View {
        let tracksInLane = audioTracks
            .filter { $0.laneIndex == laneIndex }
            .sorted { $0.startMs < $1.startMs }
        let laneHasRow = audioTracks.contains(where: { $0.laneIndex == laneIndex })

        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            HStack(spacing: CinefuseTokens.Spacing.s) {
                Label("Lane \(laneIndex + 1)", systemImage: "waveform")
                    .font(CinefuseTokens.Typography.micro.weight(.semibold))
                    .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
                Spacer(minLength: 0)
                if !laneHasRow {
                    Button("Add lane") {
                        Task { await onEnsureVideoLaneSlot(laneIndex) }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .font(CinefuseTokens.Typography.micro)
                    .tooltip("Create lane \(laneIndex + 1) for layering", enabled: showTooltips)
                }
            }

            if tracksInLane.isEmpty {
                Text(
                    laneHasRow
                        ? "No clips on this lane yet. Use Audio Lanes below or generate dialogue, score, or SFX."
                        : "Tap Add lane, then attach or generate audio that plays over the video timeline."
                )
                .font(CinefuseTokens.Typography.nano)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(tracksInLane) { track in
                    videoOverlayLaneTrackRow(track: track)
                }
            }
        }
        .padding(CinefuseTokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(timelineThemeMode.palette.timelineBase.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                        .stroke(timelineThemeMode.palette.timelineBevelTop, lineWidth: 1)
                )
        )
    }

    private func lockedAudioStartMs(for track: AudioTrack) -> Int {
        guard let shotId = track.shotId,
              let boundary = timelineShotBoundaries.first(where: { $0.shotId == shotId })
        else {
            return track.startMs
        }
        return boundary.startMs
    }

    @ViewBuilder
    private func videoOverlayLaneTrackRow(track: AudioTrack) -> some View {
        let laneMode = trackSyncModes[track.laneIndex] ?? .locked
        let computedStartMs = laneMode == .locked ? lockedAudioStartMs(for: track) : track.startMs
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            HStack(spacing: CinefuseTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(track.kind.capitalized): \(track.title)")
                        .font(CinefuseTokens.Typography.micro)
                        .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
                    Text("Start \(computedStartMs)ms • \(track.durationMs)ms")
                        .font(CinefuseTokens.Typography.nano)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }
                Spacer(minLength: 0)
                Picker(
                    "Sync",
                    selection: Binding(
                        get: { trackSyncModes[track.laneIndex] ?? .locked },
                        set: { trackSyncModes[track.laneIndex] = $0 }
                    )
                ) {
                    ForEach(AudioTrackSyncMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 72)
            }
            HStack(spacing: CinefuseTokens.Spacing.s) {
                Text("Vol")
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                Slider(
                    value: Binding(
                        get: { Double(laneVolumeByIndex[track.laneIndex] ?? 1) },
                        set: { laneVolumeByIndex[track.laneIndex] = Float($0) }
                    ),
                    in: 0...1.5
                )
                .frame(minWidth: 80, idealWidth: 140)
                if let sourceUrl = track.sourceUrl, let url = URL(string: sourceUrl) {
                    Link("Open", destination: url)
                        .font(CinefuseTokens.Typography.nano)
                }
                if track.status.lowercased() != "ready" {
                    StatusBadge(status: track.status)
                }
            }
        }
        .padding(CinefuseTokens.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.88))
        )
    }

    @ViewBuilder
    private var centerPreviewPanel: some View {
        if isAudioCreationMode {
            EditorAudioPreviewPanel(
                shots: shotsForSoundOrVideoTimeline,
                audioTracks: audioTracks,
                audioJobs: jobs,
                localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                selectedShotId: $selectedTimelineShotId,
                playbackRequestToken: previewPlaybackRequestToken,
                showTooltips: showTooltips,
                isCollapsed: $collapsePreviewPanel,
                isPoppedOut: false,
                onTogglePopout: { isPreviewPoppedOut.toggle() }
            )
        } else {
            EditorPreviewPanel(
                shots: sortedShots,
                localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                selectedShotId: $selectedTimelineShotId,
                playbackRequestToken: previewPlaybackRequestToken,
                showTooltips: showTooltips,
                isCollapsed: $collapsePreviewPanel,
                isPoppedOut: false,
                onTogglePopout: { isPreviewPoppedOut.toggle() },
                onPersistShotPreviewTrim: onPersistShotPreviewTrim
            )
        }
    }

    @ViewBuilder
    private var embeddedPopoutPreviewPanel: some View {
        if isAudioCreationMode {
            EditorAudioPreviewPanel(
                shots: shotsForSoundOrVideoTimeline,
                audioTracks: audioTracks,
                audioJobs: jobs,
                localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                selectedShotId: $selectedTimelineShotId,
                playbackRequestToken: previewPlaybackRequestToken,
                showTooltips: showTooltips,
                isCollapsed: .constant(false),
                isPoppedOut: true,
                onTogglePopout: { isPreviewPoppedOut = false }
            )
        } else {
            EditorPreviewPanel(
                shots: sortedShots,
                localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                selectedShotId: $selectedTimelineShotId,
                playbackRequestToken: previewPlaybackRequestToken,
                showTooltips: showTooltips,
                isCollapsed: .constant(false),
                isPoppedOut: true,
                onTogglePopout: { isPreviewPoppedOut = false },
                onPersistShotPreviewTrim: onPersistShotPreviewTrim
            )
        }
    }

    private var leftPaneStack: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            if isAudioCreationMode {
                SoundBlueprintsPanel(
                    blueprints: $soundBlueprints,
                    showTooltips: showTooltips,
                    isCollapsed: $collapseSoundBlueprintsPanel,
                    uploadProjectFiles: uploadProjectFiles,
                    onCreate: onCreateSoundBlueprint,
                    onPlayReferenceFile: onPlayBlueprintReferenceFile
                )
            } else {
                StoryboardPanel(
                    scenes: scenes,
                    onGenerateStoryboard: onGenerateStoryboard,
                    onReviseScene: onReviseScene,
                    isCollapsed: $collapseStoryboardPanel
                )
                CharacterPanel(
                    characters: characters,
                    newCharacterName: $newCharacterName,
                    newCharacterDescription: $newCharacterDescription,
                    onCreateCharacter: onCreateCharacter,
                    uploadProjectFiles: uploadProjectFiles,
                    onTrainCharacter: onTrainCharacter,
                    showTooltips: showTooltips,
                    isCollapsed: $collapseCharacterPanel
                )
            }
        }
        .padding(CinefuseTokens.Spacing.s)
    }

    private var leftPaneContent: some View {
        ScrollView {
            leftPaneStack
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private var rightPaneContent: some View {
        ScrollView {
            rightPaneStack
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    private var rightPaneStack: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ShotsPanel(
                    shots: shotsForSoundsPanelIfNeeded,
                    jobs: jobs,
                    localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
                    localThumbnailURLByShotId: localThumbnailURLByShotId,
                    shotRequestStateById: shotRequestStateById,
                    characterOptions: characters,
                    shotPromptDraft: $shotPromptDraft,
                    shotModelTierDraft: $shotModelTierDraft,
                    selectedCharacterLockId: $selectedCharacterLockId,
                    quotedShotCost: quotedShotCost,
                    onQuote: onQuote,
                    onCreateShot: onCreateShot,
                    onGenerateShot: onGenerateShot,
                    onRetryShot: onRetryShot,
                    onDeleteShot: onDeleteShot,
                    onPreviewShot: { shotId in
                        selectedTimelineShotId = shotId
                        previewPlaybackRequestToken += 1
                    },
                    showTooltips: showTooltips,
                    isCollapsed: $collapseShotsPanel,
                    panelMode: isAudioCreationMode ? .audioSounds : .videoClips,
                    soundBlueprints: soundBlueprints,
                    selectedSoundBlueprintIdsByShotId: $selectedSoundBlueprintIdsByShotId,
                    draftSoundBlueprintIds: $draftSoundBlueprintIds,
                    selectedTimelineShotId: $selectedTimelineShotId,
                    soundSourceLabel: soundSourceLabel,
                    soundTagsDraft: $soundTagsDraft,
                    onRefreshStatusDetails: onRefreshStatusDetails,
                    showScoreGenerationControls: isAudioCreationWorkspace,
                    scoreDurationSeconds: $scoreDurationSeconds,
                    scoreLyricsModeSelection: $scoreLyricsModeSelection,
                    scoreCustomLyricsDraft: $scoreCustomLyricsDraft
                )
                if isAudioCreationMode {
                    SectionCard(
                        title: "Audio export",
                        subtitle: "Mixes layered audio lanes into one file. Job appears in Jobs when complete.",
                        isCollapsed: $collapseExportPanel
                    ) {
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                            Button {
                                onExportAudioMix()
                            } label: {
                                Label("Export layered mix", systemImage: "waveform.path")
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .tooltip("Run audio mixdown for all lanes", enabled: showTooltips)
                            if let exportStatus = latestExportArtifactStatus {
                                GenerationStatusDot(status: exportStatus)
                                    .tooltip(exportStatus.summary, enabled: showTooltips)
                                    .onTapGesture {
                                        onOpenDebugWindow()
                                    }
                            }
                        }
                        .padding(CinefuseTokens.Spacing.s)
                    }
                }
                if !isAudioCreationMode {
                SectionCard(
                    title: "Export",
                    isCollapsed: $collapseExportPanel
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
                            if let exportStatus = latestExportArtifactStatus {
                                GenerationStatusDot(status: exportStatus)
                                    .tooltip(exportStatus.summary, enabled: showTooltips)
                                    .onTapGesture {
                                        showDebugWindow = true
                                    }
                            }
                            Button("Debug Window") {
                                onOpenDebugWindow()
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .tooltip("Open prompt and file generation diagnostics", enabled: showTooltips)
                        }.padding(CinefuseTokens.Spacing.s)
                    }
                    .padding(CinefuseTokens.Spacing.s)
                }
            }

        }
        .padding(CinefuseTokens.Spacing.s)
    }

    private var audioLanesPanelCard: some View {
        SectionCard(
            title: "Audio Lanes",
            isCollapsed: $collapseAudioPanel
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
                Button {
                    onAddAudioTrack()
                } label: {
                    Label("Add audio lane", systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .tooltip("Add an empty lane for manual placement", enabled: showTooltips)
                Group {
                    if editorMobileInspectorSheet {
                        AudioLaneView(
                            audioTracks: audioTracks,
                            shotBoundaries: timelineShotBoundaries,
                            syncModes: $trackSyncModes,
                            themePalette: timelineThemeMode.palette,
                            laneVolumes: $laneVolumeByIndex,
                            masterVolume: $masterMixGain
                        )
                        .frame(minHeight: 200)
                    } else {
                        ScrollView {
                            AudioLaneView(
                                audioTracks: audioTracks,
                                shotBoundaries: timelineShotBoundaries,
                                syncModes: $trackSyncModes,
                                themePalette: timelineThemeMode.palette,
                                laneVolumes: $laneVolumeByIndex,
                                masterVolume: $masterMixGain
                            )
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    private var jobsPanelCard: some View {
        JobsPanel(
            jobs: jobs,
            shots: shots,
            localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
            localThumbnailURLByShotId: localThumbnailURLByShotId,
            localThumbnailURLByJobId: localThumbnailURLByJobId,
            jobRequestStateById: jobRequestStateById,
            jobKindDraft: $jobKindDraft,
            onCreateJob: onCreateJob,
            onRetryJob: onRetryJob,
            onDeleteJob: onDeleteJob,
            showTooltips: showTooltips,
            isCollapsed: $collapseJobsPanel,
            onRefreshStatusDetails: onRefreshStatusDetails
        )
    }

    /// Jobs sheet uses `editorMobileInspectorSheet` so the outer sheet `ScrollView` owns vertical scrolling (no collapsed header / infinite blank gap).
    private var jobsPanelMobileSheet: some View {
        JobsPanel(
            jobs: jobs,
            shots: shots,
            localFileRecordsByRemoteURL: localFileRecordsByRemoteURL,
            localThumbnailURLByShotId: localThumbnailURLByShotId,
            localThumbnailURLByJobId: localThumbnailURLByJobId,
            jobRequestStateById: jobRequestStateById,
            jobKindDraft: $jobKindDraft,
            onCreateJob: onCreateJob,
            onRetryJob: onRetryJob,
            onDeleteJob: onDeleteJob,
            showTooltips: showTooltips,
            isCollapsed: .constant(false),
            onRefreshStatusDetails: onRefreshStatusDetails
        )
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
        let left = effectiveShowLeftPane
            ? min(max(leftPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)), Double(CinefuseTokens.Control.maxSidePanelWidth))
            : 0
        let right = effectiveShowRightPane
            ? min(max(rightPaneWidth, Double(CinefuseTokens.Control.minSidePanelWidth)), Double(CinefuseTokens.Control.maxSidePanelWidth))
            : 0
        let handles = (effectiveShowLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (effectiveShowRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + Double(CinefuseTokens.Control.layoutHandleReserve)
        let availableForSides = max(totalWidth - minCenter - handles, 0)
        if !effectiveShowLeftPane && !effectiveShowRightPane {
            return (0, 0)
        }
        if !effectiveShowLeftPane {
            return (0, min(right, availableForSides))
        }
        if !effectiveShowRightPane {
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
        let reservedHandles = (effectiveShowLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (effectiveShowRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + Double(CinefuseTokens.Control.layoutHandleReserve)
        let maxByCenter = max(totalWidth - minCenter - reservedHandles - opposingPaneWidth, minPane)
        return min(max(width, minPane), min(maxPane, maxByCenter))
    }

    private func clampedRightPaneWidth(_ width: Double, totalWidth: Double, opposingPaneWidth: Double) -> Double {
        let minPane = Double(CinefuseTokens.Control.minSidePanelWidth)
        let maxPane = Double(CinefuseTokens.Control.maxSidePanelWidth)
        let minCenter = Double(CinefuseTokens.Control.minCenterPreviewWidth)
        let reservedHandles = (effectiveShowLeftPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
            + (effectiveShowRightPane ? Double(CinefuseTokens.Control.splitterHitArea) : 0)
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
        timelineStripHeight = clampedTimelineStripHeight(timelineStripHeight)
    }

    private func clampedTimelineStripHeight(_ height: Double) -> Double {
        // Floor fits ruler + synchronized clip row (see `HorizontalTimelineTrack.timelineTrackScrollableHeight`).
        min(max(height, 148), 560)
    }

    private func header(project: Project) -> some View {
        HStack(alignment: .top, spacing: CinefuseTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                if isRenamingProjectTitle {
                    HStack(spacing: CinefuseTokens.Spacing.xs) {
                        TextField("Project title", text: $projectTitleDraft)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let nextTitle = projectTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nextTitle.isEmpty && nextTitle != project.title {
                                onRenameProject(nextTitle)
                            }
                            isRenamingProjectTitle = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        Button {
                            isRenamingProjectTitle = false
                            projectTitleDraft = project.title
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                } else {
                    HStack(spacing: CinefuseTokens.Spacing.xs) {
                        Text(project.title)
                            .font(CinefuseTokens.Typography.sectionTitle)
                        Button {
                            projectTitleDraft = project.title
                            isRenamingProjectTitle = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .tooltip("Rename project", enabled: showTooltips)
                    }
                }
                Text("Project ID: \(project.id) · \(shots.count) clips · \(audioTracks.count) tracks")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            Spacer(minLength: CinefuseTokens.Spacing.s)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CinefuseTokens.Spacing.xs) {
                    if isPreviewPoppedOut {
                        Button {
                            isPreviewPoppedOut = false
                        } label: {
                            Label("Pop In Preview", systemImage: "rectangle.inset.filled.and.person.filled")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .tooltip("Dock preview back into workspace", enabled: showTooltips)
                    }
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
                    if isPreviewPoppedOut {
                        Button {
                            isPreviewPoppedOut = false
                        } label: {
                            Label("Pop In Preview", systemImage: "rectangle.inset.filled.and.person.filled")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .tooltip("Dock preview back into workspace", enabled: showTooltips)
                    }
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
    case render

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editing: return "Edit"
        case .audio: return "Audio"
        case .review: return "Review"
        case .render: return "Render"
        }
    }
}

/// Edit / Audio / Review / Render layout presets; matches ``CreationModeBinarySwitch`` styling (segmented “radio” row).
private struct EditorWorkspacePresetSegmentSwitch: View {
    @Binding var workspacePresetRaw: String

    private var selectedPreset: EditorWorkspacePreset {
        EditorWorkspacePreset(rawValue: workspacePresetRaw) ?? .editing
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorWorkspacePreset.allCases) { preset in
                let isSelected = selectedPreset == preset
                Button {
                    workspacePresetRaw = preset.rawValue
                } label: {
                    segmentLabel(preset: preset, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: preset))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(CinefuseTokens.ColorRole.borderSubtle.opacity(0.45), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace layout")
    }

    @ViewBuilder
    private func segmentLabel(preset: EditorWorkspacePreset, isSelected: Bool) -> some View {
        Text(preset.label)
            .font(CinefuseTokens.Typography.micro)
            .foregroundStyle(
                isSelected
                    ? CinefuseTokens.ColorRole.textPrimary
                    : CinefuseTokens.ColorRole.textSecondary
            )
            .frame(minWidth: 26)
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isSelected ? CinefuseTokens.ColorRole.borderSubtle.opacity(0.65) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.22) : .clear,
                radius: 0,
                x: 0,
                y: 1
            )
            .padding(1)
    }

    private func accessibilityLabel(for preset: EditorWorkspacePreset) -> String {
        switch preset {
        case .editing: return "Editing layout"
        case .audio: return "Audio workspace layout"
        case .review: return "Review layout"
        case .render: return "Render layout"
        }
    }
}

/// Card chrome for the horizontal timeline (video thumbnails vs audio waveform tiles).
enum TimelineClipVisualStyle: Equatable {
    case videoThumbnail
    case audioWaveform
}

enum ShotsPanelMode: Equatable {
    case videoClips
    case audioSounds
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
    let jobs: [Job]
    let localThumbnailURLByShotId: [String: URL]
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    let shotRequestStateById: [String: RenderRequestState]
    @Binding var selectedShotId: String?
    let onPreviewShot: (String) -> Void
    let onMoveShot: (IndexSet, Int) -> Void
    let showTooltips: Bool
    let themePalette: CinefuseTokens.ThemePalette
    @Binding var isCollapsed: Bool
    var clipVisualStyle: TimelineClipVisualStyle = .videoThumbnail
    @Binding var isTimelineFullscreen: Bool
    @AppStorage("cinefuse.editor.timeline.clipDensity") private var clipDensityRaw = TimelineClipDensity.large.rawValue
    /// 0 = zoomed out … 4 = zoomed in (`pixelsPerSecond` ladder below).
    @AppStorage("cinefuse.editor.timeline.zoomStep") private var timelineZoomStep = 2
    @EnvironmentObject private var editorPlaybackState: EditorPlaybackState
    @State private var orderedShots: [Shot] = []
    @State private var draggingShotId: String?
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var hiddenShotIds: Set<String> = []
    @State private var trimByShotId: [String: ClosedRange<Double>] = [:]
    /// Measured media duration (seconds) per shot when `playbackURL` resolves; overrides `durationSec` for card width + ruler.
    @State private var measuredDurationSecondsByShotId: [String: Double] = [:]

    private var clipDensity: TimelineClipDensity {
        TimelineClipDensity(rawValue: clipDensityRaw) ?? .large
    }

    private static let timelineZoomPixelsPerSecond: [CGFloat] = [6, 9, 12, 18, 24]

    private var timelinePixelsPerSecond: CGFloat {
        let idx = min(max(timelineZoomStep, 0), Self.timelineZoomPixelsPerSecond.count - 1)
        return Self.timelineZoomPixelsPerSecond[idx]
    }

    private var rulerAndCardsSpacing: CGFloat {
        clipVisualStyle == .audioWaveform ? 2 : CinefuseTokens.Spacing.xs
    }

    /// Ruler + gap + clip row — single scroll column height.
    private var timelineTrackScrollableHeight: CGFloat {
        CinefuseTokens.Control.timelineRulerHeight + rulerAndCardsSpacing + timelineCardsStripHeight
    }

    /// Vertical space for the scrolling strip of clip cards (cards + padding inside the inner timeline tray).
    private var timelineCardsStripHeight: CGFloat {
        switch clipDensity {
        case .thin:
            return clipVisualStyle == .audioWaveform ? 54 : 62
        case .medium:
            return clipVisualStyle == .audioWaveform ? 92 : 118
        case .large:
            return clipVisualStyle == .audioWaveform ? 118 : 136
        }
    }

    private var timelineDensityToolbar: some View {
        HStack(spacing: CinefuseTokens.Spacing.xxs) {
            Button {
                isTimelineFullscreen.toggle()
            } label: {
                Image(systemName: isTimelineFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: CinefuseTokens.Control.iconSymbolSize * 0.88, weight: .medium))
                    .foregroundStyle(
                        isTimelineFullscreen
                            ? CinefuseTokens.ColorRole.accent
                            : CinefuseTokens.ColorRole.textSecondary.opacity(0.92)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isTimelineFullscreen ? "Exit full-screen timeline" : "Full-screen timeline"))
            .tooltip(
                isTimelineFullscreen
                    ? "Show preview and side panels again"
                    : "Expand the timeline; hide the preview workspace",
                enabled: showTooltips
            )
            Button {
                timelineZoomStep = max(0, timelineZoomStep - 1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: CinefuseTokens.Control.iconSymbolSize * 0.88, weight: .medium))
                    .foregroundStyle(
                        timelineZoomStep <= 0
                            ? CinefuseTokens.ColorRole.textSecondary.opacity(0.35)
                            : CinefuseTokens.ColorRole.textSecondary.opacity(0.92)
                    )
            }
            .buttonStyle(.plain)
            .disabled(timelineZoomStep <= 0)
            .accessibilityLabel(Text("Zoom timeline out"))
            .tooltip("Show more timeline in view", enabled: showTooltips)
            Button {
                timelineZoomStep = min(Self.timelineZoomPixelsPerSecond.count - 1, timelineZoomStep + 1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: CinefuseTokens.Control.iconSymbolSize * 0.88, weight: .medium))
                    .foregroundStyle(
                        timelineZoomStep >= Self.timelineZoomPixelsPerSecond.count - 1
                            ? CinefuseTokens.ColorRole.textSecondary.opacity(0.35)
                            : CinefuseTokens.ColorRole.textSecondary.opacity(0.92)
                    )
            }
            .buttonStyle(.plain)
            .disabled(timelineZoomStep >= Self.timelineZoomPixelsPerSecond.count - 1)
            .accessibilityLabel(Text("Zoom timeline in"))
            .tooltip("Magnify clip widths on the timeline", enabled: showTooltips)
            ForEach(TimelineClipDensity.allCases) { density in
                Button {
                    clipDensityRaw = density.rawValue
                } label: {
                    Image(systemName: density.toolbarSymbolName)
                        .font(.system(size: CinefuseTokens.Control.iconSymbolSize * 0.88, weight: clipDensity == density ? .bold : .regular))
                        .foregroundStyle(
                            clipDensity == density
                                ? CinefuseTokens.ColorRole.accent
                                : CinefuseTokens.ColorRole.textSecondary.opacity(0.92)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(density.accessibilityLabel))
            }
        }
    }

    private func effectiveDurationSeconds(for shot: Shot) -> Double {
        if let m = measuredDurationSecondsByShotId[shot.id], m > 0.25 {
            return m
        }
        return Double(max(shot.durationSec ?? 5, 1))
    }

    private func totalTimelineDurationSeconds(for shots: [Shot]) -> Int {
        let sum = shots.reduce(0.0) { $0 + effectiveDurationSeconds(for: $1) }
        return max(1, Int(ceil(sum)))
    }

#if canImport(AVFoundation)
    private func refreshMeasuredDurations() async {
        var next: [String: Double] = [:]
        for shot in visibleShots {
            guard let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL) else { continue }
            let asset = AVURLAsset(url: url)
            do {
                let seconds = try await asset.load(.duration).seconds
                if seconds.isFinite, seconds > 0.25 {
                    next[shot.id] = seconds
                }
            } catch {
                continue
            }
        }
        await MainActor.run {
            measuredDurationSecondsByShotId = next
        }
    }
#endif

    private var measurementSignature: String {
        visibleShots.map { "\($0.id):\($0.clipUrl ?? "")" }.joined(separator: "|")
    }

    /// Ruler and clip row share one horizontal scroll width so the playhead aligns with time marks.
    @ViewBuilder
    private var timelineTrackWithSyncedRuler: some View {
        if clipVisualStyle == .audioWaveform {
            ScrollView(.vertical, showsIndicators: true) {
                timelineHorizontalStripGeometry
            }
        } else {
            timelineHorizontalStripGeometry
        }
    }

    private var timelineHorizontalStripGeometry: some View {
        GeometryReader { geo in
            let spacing = clipVisualStyle == .audioWaveform ? CinefuseTokens.Spacing.xs : CinefuseTokens.Spacing.s
            let totalSec = totalTimelineDurationSeconds(for: visibleShots)
            let widths = proportionalCardWidths(
                for: visibleShots,
                viewportWidth: geo.size.width,
                spacing: spacing,
                clipDensity: clipDensity,
                pixelsPerSecond: timelinePixelsPerSecond
            )
            let contentWidth = widths.reduce(0, +) + spacing * CGFloat(max(0, visibleShots.count - 1))
            let stripW = max(geo.size.width, contentWidth)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: rulerAndCardsSpacing) {
                    TimelineRulerStrip(
                        totalSeconds: totalSec,
                        contentWidth: stripW,
                        palette: themePalette
                    )
                    HStack(spacing: spacing) {
                        ForEach(Array(visibleShots.enumerated()), id: \.element.id) { index, shot in
                            TimelineClipCard(
                                shot: shot,
                                localThumbnailURL: localThumbnailURLByShotId[shot.id],
                                clipStatusPresentation: clipArtifactStatus(for: shot),
                                index: index,
                                backendProgressPercent: latestBackendProgressPercent(for: shot.id),
                                trimRange: trimByShotId[shot.id],
                                isSelected: selectedShotId == shot.id,
                                canMoveLeft: index > 0,
                                canMoveRight: index < (visibleShots.count - 1),
                                onSelect: { selectedShotId = shot.id },
                                onPreview: { onPreviewShot(shot.id) },
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
                                },
                                clipVisualStyle: clipVisualStyle,
                                clipDensity: clipDensity,
                                cardWidth: widths.indices.contains(index) ? widths[index] : nil,
                                playbackProgressFraction: playbackFraction(for: shot),
                                playbackFileURL: shot.playbackURL(localRecords: localFileRecordsByRemoteURL)
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
                    .frame(width: stripW, alignment: .leading)
                }
                .frame(width: stripW, alignment: .leading)
                .padding(.vertical, clipVisualStyle == .audioWaveform ? 2 : CinefuseTokens.Spacing.xxs)
            }
#if canImport(AVFoundation)
            .task(id: measurementSignature) {
                await refreshMeasuredDurations()
            }
#endif
        }
        .frame(height: timelineTrackScrollableHeight)
    }

    var body: some View {
        SectionCard(
            title: clipVisualStyle == .audioWaveform ? "Sound timeline" : "Timeline",
            isCollapsed: $isCollapsed,
            titleFont: clipVisualStyle == .audioWaveform
                ? CinefuseTokens.Typography.caption.weight(.semibold)
                : CinefuseTokens.Typography.sectionTitle,
            stackSpacing: clipVisualStyle == .audioWaveform ? CinefuseTokens.Spacing.xxs : CinefuseTokens.Spacing.s,
            contentPadding: clipVisualStyle == .audioWaveform ? CinefuseTokens.Spacing.s : CinefuseTokens.Spacing.m,
            headerAccessory: AnyView(timelineDensityToolbar)
        ) {
            if visibleShots.isEmpty {
                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                    EmptyStateCard(
                        title: clipVisualStyle == .audioWaveform ? "No sounds in timeline" : "No clips in timeline",
                        message: clipVisualStyle == .audioWaveform
                            ? "Create sounds from the Sounds panel, then arrange them here."
                            : "Create or generate shots, then reorder them in this track."
                    )
                    if !hiddenShots.isEmpty {
                        hiddenShotsControls
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: clipVisualStyle == .audioWaveform ? CinefuseTokens.Spacing.xxs : CinefuseTokens.Spacing.xs) {
                    timelineTrackWithSyncedRuler
                    if !hiddenShots.isEmpty {
                        hiddenShotsControls
                    }
                }
                .padding(clipVisualStyle == .audioWaveform ? CinefuseTokens.Spacing.xs : CinefuseTokens.Spacing.s)
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
        .onChange(of: shotContentSignature) { _, _ in
            syncDisplayedShots()
        }
    }

    private var displayedShots: [Shot] {
        orderedShots.isEmpty ? shots : orderedShots
    }

    private var visibleShots: [Shot] {
        displayedShots.filter { !hiddenShotIds.contains($0.id) }
    }

    private var hiddenShots: [Shot] {
        displayedShots.filter { hiddenShotIds.contains($0.id) }
    }

    private var hiddenShotsControls: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            HStack(spacing: CinefuseTokens.Spacing.xs) {
                Text("Hidden clips: \(hiddenShots.count)")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                Button("Unhide all") {
                    hiddenShotIds.removeAll()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CinefuseTokens.Spacing.xs) {
                    ForEach(hiddenShots) { shot in
                        Button {
                            toggleHidden(shot.id)
                        } label: {
                            Label(
                                shot.prompt.isEmpty ? "Untitled clip" : shot.prompt,
                                systemImage: "eye"
                            )
                            .lineLimit(1)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .tooltip("Unhide this clip", enabled: showTooltips)
                    }
                }
            }
        }
    }

    private var shotContentSignature: String {
        shots
            .map { shot in
                [
                    shot.id,
                    String(shot.orderIndex ?? -1),
                    shot.status,
                    shot.prompt,
                    shot.clipUrl ?? ""
                ]
                .joined(separator: "::")
            }
            .joined(separator: "|")
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
            characterLocks: source.characterLocks,
            soundGeneration: source.soundGeneration,
            previewTrimInMs: source.previewTrimInMs,
            previewTrimOutMs: source.previewTrimOutMs
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

    /// Latest job-attached percent from the gateway (nil until the worker reports ticks).
    private func latestBackendProgressPercent(for shotId: String) -> Int? {
        guard let job = jobs
            .filter({ $0.shotId == shotId })
            .max(by: { timelineParseTimestamp($0.updatedAt) < timelineParseTimestamp($1.updatedAt) }),
            let pct = job.progressPct
        else {
            return nil
        }
        return max(0, min(100, pct))
    }

    private func timelineParseTimestamp(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    private func latestJob(for shotId: String) -> Job? {
        jobs
            .filter { $0.shotId == shotId }
            .max { lhs, rhs in
                timelineParseTimestamp(lhs.updatedAt) < timelineParseTimestamp(rhs.updatedAt)
            }
    }

    private func clipArtifactStatus(for shot: Shot) -> ArtifactStatusPresentation {
        let localRecord = shot.clipUrl.flatMap { localFileRecordsByRemoteURL[$0] }
        return shotArtifactStatusPresentation(
            shot: shot,
            job: latestJob(for: shot.id),
            localRecord: localRecord,
            requestState: shotRequestStateById[shot.id]
        )
    }

    private func playbackFraction(for shot: Shot) -> Double? {
        guard editorPlaybackState.activeShotId == shot.id,
              editorPlaybackState.durationSeconds > 0
        else {
            return nil
        }
        let p = editorPlaybackState.currentTimeSeconds / editorPlaybackState.durationSeconds
        guard p.isFinite else { return nil }
        return min(1, max(0, p))
    }

    private func proportionalCardWidths(
        for shots: [Shot],
        viewportWidth: CGFloat,
        spacing: CGFloat,
        clipDensity: TimelineClipDensity,
        pixelsPerSecond: CGFloat
    ) -> [CGFloat] {
        let fallback = CinefuseTokens.Control.timelineCardWidth
        guard !shots.isEmpty else { return [] }
        let minW: CGFloat = {
            let audioMin: CGFloat = switch clipDensity {
            case .thin: 108
            case .medium: 80
            case .large: 72
            }
            let videoMin: CGFloat = switch clipDensity {
            case .thin: 132
            case .medium: 104
            case .large: 96
            }
            return clipVisualStyle == .audioWaveform ? audioMin : videoMin
        }()
        let maxW: CGFloat = clipVisualStyle == .audioWaveform ? 440 : 560
        let durations = shots.map { effectiveDurationSeconds(for: $0) }
        let totalDur = durations.reduce(0, +)
        guard totalDur > 0 else {
            return shots.map { _ in fallback }
        }
        let spacingTotal = spacing * CGFloat(max(0, shots.count - 1))
        var widths = durations.map { dur -> CGFloat in
            max(minW, min(maxW, CGFloat(dur) * pixelsPerSecond))
        }
        let natural = widths.reduce(0, +) + spacingTotal
        let target = max(viewportWidth, natural)
        let inner = max(0, target - spacingTotal)
        let sumW = widths.reduce(0, +)
        if sumW > 0, inner > 0 {
            let scale = inner / sumW
            widths = widths.map { $0 * scale }
        }
        return widths
    }

}

struct TimelineClipCard: View {
    let shot: Shot
    let localThumbnailURL: URL?
    let clipStatusPresentation: ArtifactStatusPresentation
    let index: Int
    /// When non-nil, shows a determinate bar; otherwise an animated indeterminate strip while in-flight.
    let backendProgressPercent: Int?
    let trimRange: ClosedRange<Double>?
    let isSelected: Bool
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
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
    var clipVisualStyle: TimelineClipVisualStyle = .videoThumbnail
    /// Row height / chrome density for this clip (timeline toolbar).
    var clipDensity: TimelineClipDensity = .large
    /// When set, horizontal size follows timeline duration scaling (see `HorizontalTimelineTrack`).
    var cardWidth: CGFloat?
    /// Playhead position within this clip when it matches active preview (`0...1`).
    var playbackProgressFraction: Double?
    /// Resolved local/network URL for waveform rendering on audio timeline clips.
    var playbackFileURL: URL? = nil

    @State private var waveformPeaks: [Float] = []

    private var previewFrameURL: URL? {
        if let localThumbnailURL {
            return localThumbnailURL
        }
        if let thumbnail = shot.thumbnailUrl, let url = URL(string: thumbnail) {
            return url
        }
        if let clip = shot.clipUrl, let url = URL(string: clip) {
            return url
        }
        return nil
    }

    private var cardFillColor: Color {
        isSelected ? CinefuseTokens.ColorRole.surfacePrimary : CinefuseTokens.ColorRole.surfaceSecondary
    }

    private var isAudioTimelineCard: Bool {
        clipVisualStyle == .audioWaveform
    }

    private var resolvedCardWidth: CGFloat {
        if let cardWidth {
            return cardWidth
        }
        return isAudioTimelineCard ? min(CinefuseTokens.Control.timelineCardWidth, 208) : CinefuseTokens.Control.timelineCardWidth
    }

    private var resolvedCardHeight: CGFloat {
        switch clipDensity {
        case .thin:
            return isAudioTimelineCard ? 44 : 52
        case .medium:
            return isAudioTimelineCard ? 78 : CinefuseTokens.Control.timelineCardHeight
        case .large:
            return isAudioTimelineCard ? 102 : CinefuseTokens.Control.timelineCardHeight
        }
    }

    /// Video timeline: show waveform instead of thumbnail when `clipUrl` looks like an audio artifact.
    private var showsWaveformOnVideoTimeline: Bool {
        clipVisualStyle == .videoThumbnail
            && shot.isLikelyAudioClipArtifact()
            && shot.status.lowercased() == "ready"
            && playbackFileURL != nil
    }

    /// Waveform view includes fill + line; hide the legacy vertical overlay to avoid double playheads.
    private var shouldUseTimelineWaveformPlayhead: Bool {
        guard shot.status.lowercased() == "ready" else { return false }
        guard !waveformPeaks.isEmpty else { return false }
        return isAudioTimelineCard || showsWaveformOnVideoTimeline
    }

    private var waveformBucketCount: Int {
        let w = max(Int(resolvedCardWidth), 40)
        switch clipDensity {
        case .thin:
            return 40
        case .medium:
            return min(140, max(48, w / 3))
        case .large:
            return min(180, max(64, w / 2))
        }
    }

    private var waveformTaskIdentity: String {
        "\(shot.id)|\(playbackFileURL?.absoluteString ?? "")|\(clipDensity.rawValue)|\(Int(resolvedCardWidth))|\(clipVisualStyle == .audioWaveform ? "a" : "v")|\(shot.isLikelyAudioClipArtifact())"
    }

    private var contentHorizontalPadding: CGFloat {
        switch clipDensity {
        case .thin: return CinefuseTokens.Spacing.xxs + 1
        case .medium: return CinefuseTokens.Spacing.xs
        case .large: return isAudioTimelineCard ? CinefuseTokens.Spacing.xs : CinefuseTokens.Spacing.s
        }
    }

    private var promptFont: Font {
        switch clipDensity {
        case .thin: return CinefuseTokens.Typography.micro
        case .medium: return isAudioTimelineCard ? CinefuseTokens.Typography.micro : CinefuseTokens.Typography.label
        case .large: return isAudioTimelineCard ? CinefuseTokens.Typography.micro : CinefuseTokens.Typography.label
        }
    }

    /// Compact strip: waveform/thumbnail at fixed width + single-line prompt (thin density).
    @ViewBuilder
    private var thinTimelineStripBody: some View {
        let mediaH: CGFloat = isAudioTimelineCard ? 34 : 38
        let mediaW: CGFloat = isAudioTimelineCard ? 36 : 42
        HStack(alignment: .center, spacing: CinefuseTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                    .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                if clipVisualStyle == .audioWaveform || showsWaveformOnVideoTimeline {
                    if shouldUseTimelineWaveformPlayhead {
                        AudioWaveformWithPlayhead(
                            peaks: waveformPeaks,
                            progressFraction: playbackProgressFraction ?? 0,
                            onSeekFraction: { _ in },
                            interactive: false
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                    } else {
                        LinearGradient(
                            colors: [
                                CinefuseTokens.ColorRole.accent.opacity(0.4),
                                CinefuseTokens.ColorRole.surfaceSecondary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.65))
                    }
                } else if let previewFrameURL {
                    AsyncImage(url: previewFrameURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .overlay(
                                    LinearGradient(
                                        colors: [.black.opacity(0.35), .black.opacity(0.65)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        default:
                            Color.clear
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                }
            }
            .frame(width: mediaW, height: mediaH)
            .clipped()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("#\(index + 1)")
                        .font(CinefuseTokens.Typography.nano.weight(.semibold))
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    if shot.status.lowercased() != "ready" {
                        StatusBadge(status: shot.status)
                            .scaleEffect(0.78)
                    }
                    Spacer(minLength: 0)
                }
                Text(shot.prompt.isEmpty ? "Untitled clip" : shot.prompt)
                    .font(CinefuseTokens.Typography.micro)
                    .lineLimit(1)
                    .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
                Text("\(shot.modelTier.capitalized) · \(shot.durationSec ?? 0)s")
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.vertical, CinefuseTokens.Spacing.xxs)
        .frame(width: resolvedCardWidth, height: resolvedCardHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .stroke(
                    isSelected ? CinefuseTokens.ColorRole.accent : CinefuseTokens.ColorRole.borderSubtle,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(thinTimelinePlayheadOverlay)
    }

    @ViewBuilder
    private var thinTimelinePlayheadOverlay: some View {
        if shouldUseTimelineWaveformPlayhead {
            EmptyView()
        } else {
            timelineVerticalPlayheadOverlay
        }
    }

    @ViewBuilder
    private var timelineVerticalPlayheadOverlay: some View {
        if let playbackProgressFraction {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let x = w * CGFloat(min(1, max(0, playbackProgressFraction)))
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(CinefuseTokens.ColorRole.accent)
                        .frame(width: 2, height: h)
                        .offset(x: max(0, min(w - 2, x - 1)))
                }
                .frame(width: w, height: h)
            }
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        Group {
            if clipDensity == .thin {
                thinTimelineStripBody
            } else {
                standardTimelineClipBody
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPreview)
        .onTapGesture(count: 1, perform: onSelect)
        .opacity(isDragging ? 0.75 : 1)
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: NSString(string: shot.id))
        }
        .contextMenu {
            Button {
                onPreview()
            } label: {
                Label("Preview clip", systemImage: "play.circle")
            }
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
        .task(id: waveformTaskIdentity) {
            guard shot.status.lowercased() == "ready",
                  let url = playbackFileURL,
                  isAudioTimelineCard || showsWaveformOnVideoTimeline
            else {
                waveformPeaks = []
                return
            }
            let peaks = (try? await WaveformPeakLoader.loadPeaks(from: url, bucketCount: waveformBucketCount)) ?? []
            waveformPeaks = peaks
        }
    }

    @ViewBuilder
    private var standardTimelineClipBody: some View {
        VStack(alignment: .leading, spacing: isAudioTimelineCard ? 2 : CinefuseTokens.Spacing.xxs) {
            HStack(spacing: isAudioTimelineCard ? 4 : CinefuseTokens.Spacing.xs) {
                GenerationStatusDot(status: clipStatusPresentation)
                    .scaleEffect(isAudioTimelineCard ? 0.62 : 1)
                Text("#\(index + 1)")
                    .font(isAudioTimelineCard ? CinefuseTokens.Typography.micro.weight(.semibold) : CinefuseTokens.Typography.caption.weight(.semibold))
                Spacer()
                if shot.status.lowercased() != "ready" {
                    StatusBadge(status: shot.status)
                        .scaleEffect(isAudioTimelineCard ? 0.88 : 1)
                }
            }

            Text(shot.prompt.isEmpty ? "Untitled clip" : shot.prompt)
                .font(promptFont)
                .lineLimit(2)
                .textSelection(.enabled)
                .contextMenu {
                    Button("Copy prompt") {
                        copyTextToClipboard(shot.prompt.isEmpty ? "Untitled clip" : shot.prompt)
                    }
                }

            Group {
                Text("\(shot.modelTier.capitalized) · \(shot.durationSec ?? 0)s")
                    .font(clipDensity == .medium ? CinefuseTokens.Typography.nano : (isAudioTimelineCard ? CinefuseTokens.Typography.micro : CinefuseTokens.Typography.caption))
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                if ["queued", "generating", "running", "processing"].contains(shot.status) {
                    if let p = backendProgressPercent {
                        HStack(spacing: CinefuseTokens.Spacing.xxs) {
                            ProgressView(value: Double(p), total: 100)
                                .controlSize(.mini)
                                .tint(CinefuseTokens.ColorRole.accent)
                                .animation(.easeInOut(duration: 0.28), value: p)
                            Text("\(p)%")
                                .font(CinefuseTokens.Typography.nano)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        }
                    } else {
                        HStack(spacing: CinefuseTokens.Spacing.xxs) {
                            AnimatedIndeterminateProgressBar(height: 4)
                                .frame(maxWidth: .infinity)
                            Text(clipVisualStyle == .audioWaveform ? "Generating…" : "Rendering…")
                                .font(CinefuseTokens.Typography.nano)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        }
                    }
                }
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
                    .scaleEffect(clipDensity == .medium ? 0.88 : 1)

                    IconCommandButton(
                        systemName: "arrow.right",
                        label: "Move clip right",
                        action: onMoveRight,
                        tooltipEnabled: showTooltips
                    )
                    .disabled(!canMoveRight)
                    .scaleEffect(clipDensity == .medium ? 0.88 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(contentHorizontalPadding)
        .frame(
            width: resolvedCardWidth,
            height: resolvedCardHeight,
            alignment: .topLeading
        )
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(cardFillColor)
                if clipVisualStyle == .audioWaveform || showsWaveformOnVideoTimeline {
                    Group {
                        if shouldUseTimelineWaveformPlayhead {
                            AudioWaveformWithPlayhead(
                                peaks: waveformPeaks,
                                progressFraction: playbackProgressFraction ?? 0,
                                onSeekFraction: { _ in },
                                interactive: false
                            )
                            .padding(.horizontal, contentHorizontalPadding)
                            .padding(.vertical, clipDensity == .large ? CinefuseTokens.Spacing.xs : CinefuseTokens.Spacing.xxs)
                        } else {
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            CinefuseTokens.ColorRole.accent.opacity(0.35),
                                            CinefuseTokens.ColorRole.surfaceSecondary
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Group {
                                        if shot.status.lowercased() == "ready", playbackFileURL != nil, waveformPeaks.isEmpty {
                                            ProgressView()
                                                .scaleEffect(0.85)
                                        } else {
                                            Image(systemName: "waveform")
                                                .font(.system(
                                                    size: clipDensity == .medium ? 22 : (isAudioTimelineCard ? 30 : 44),
                                                    weight: .light
                                                ))
                                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.5))
                                        }
                                    }
                                )
                        }
                    }
                } else if let previewFrameURL {
                    AsyncImage(url: previewFrameURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .overlay(
                                    LinearGradient(
                                        colors: [.black.opacity(0.48), .black.opacity(0.82)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        default:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
                }
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .stroke(
                        isSelected ? CinefuseTokens.ColorRole.accent : CinefuseTokens.ColorRole.borderSubtle,
                        lineWidth: isSelected ? 2 : 1
                    )

                if shouldUseTimelineWaveformPlayhead {
                    EmptyView()
                } else {
                    timelineVerticalPlayheadOverlay
                }
            }
        )
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
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    @Binding var selectedShotId: String?
    let playbackRequestToken: Int
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    let isPoppedOut: Bool
    let onTogglePopout: () -> Void
    /// Persist preview trim to the API (`nil` clears stored trim = full length).
    let onPersistShotPreviewTrim: (String, Int?, Int?) async -> Void
    @EnvironmentObject private var editorPlaybackState: EditorPlaybackState
    @State private var queuePlayer = AVQueuePlayer()
    @AppStorage("cinefuse.editor.preview.loopEnabled") private var loopPreviewEnabled = true
    @AppStorage("cinefuse.editor.preview.playbackRate") private var previewPlaybackRate = 1.0
    @State private var loopObserver: NSObjectProtocol?
    private static let loopPreferenceKey = "cinefuse.editor.preview.loopEnabled"
    private static let playbackRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    /// `nil` while classifying the selected clip (audio-only vs video).
    @State private var assetIsAudioOnly: Bool?
    @State private var waveformPeaks: [Float] = []
    /// Matches `queuePlayer` item order for applying per-shot trim while sequencing.
    @State private var playbackQueueShots: [Shot] = []
    @State private var lastSequenceStartedFromSelection = false
    @State private var trimStartFraction: Double = 0
    @State private var trimEndFraction: Double = 1
    @State private var previewAssetDurationSeconds: Double = 0
    @State private var currentItemObservation: NSKeyValueObservation?
    @State private var persistTrimTask: Task<Void, Never>?
    @State private var lastPlaybackWasSequence = false

    /// Trim handles edit the selection and are hidden while a multi-item queue is playing (trim differs per shot).
    private var trimHandlesVisible: Bool {
        queuePlayer.items().count <= 1
    }

    private var waveformProgressFraction: Double {
        guard editorPlaybackState.durationSeconds > 0 else { return 0 }
        return min(1, max(0, editorPlaybackState.currentTimeSeconds / editorPlaybackState.durationSeconds))
    }

    private var playableShots: [Shot] {
        shots.filter { shot in
            guard shot.clipUrl != nil else { return false }
            return shot.playbackURL(localRecords: localFileRecordsByRemoteURL) != nil
        }
    }

    private var selectedShot: Shot? {
        if let selectedShotId {
            return playableShots.first(where: { $0.id == selectedShotId })
        }
        return playableShots.first
    }

    private func syncTrimFractionsFromSelectedShot() {
        guard let shot = selectedShot, previewAssetDurationSeconds > 0.25 else { return }
        let durMs = previewAssetDurationSeconds * 1000
        let inMs = shot.previewTrimInMs.map(Double.init) ?? 0
        let outMs = shot.previewTrimOutMs.map(Double.init) ?? durMs
        trimStartFraction = max(0, min(1, inMs / durMs))
        trimEndFraction = max(trimStartFraction + 0.0001, min(1, outMs / durMs))
        editorPlaybackState.setPreviewTrim(startFraction: trimStartFraction, endFraction: trimEndFraction)
    }

    private func previewTrimMsFromFractions() -> (Int?, Int?) {
        guard previewAssetDurationSeconds > 0.25 else { return (nil, nil) }
        let durMs = previewAssetDurationSeconds * 1000
        let fullRange = trimStartFraction <= 0.002 && trimEndFraction >= 0.998
        if fullRange {
            return (nil, nil)
        }
        let inMs = Int((trimStartFraction * durMs).rounded())
        let outMs = Int((trimEndFraction * durMs).rounded())
        guard outMs > inMs else { return (nil, nil) }
        return (inMs, outMs)
    }

    private func schedulePersistPreviewTrim() {
        guard let shotId = selectedShot?.id else { return }
        persistTrimTask?.cancel()
        persistTrimTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            let pair = previewTrimMsFromFractions()
            await onPersistShotPreviewTrim(shotId, pair.0, pair.1)
        }
    }

#if canImport(AVFoundation)
    /// Applies editor trim sliders to the current item (selected-shot preview).
    private func applyPlaybackTrimFromEditorState() {
        guard let item = queuePlayer.currentItem else { return }
        let seconds = previewAssetDurationSeconds > 0.25
            ? previewAssetDurationSeconds
            : item.duration.seconds
        guard seconds.isFinite, seconds > 0.25 else { return }
        previewAssetDurationSeconds = seconds
        let startAbs = trimStartFraction * seconds
        let endAbs = trimEndFraction * seconds
        editorPlaybackState.setPreviewTrim(startFraction: trimStartFraction, endFraction: trimEndFraction)
        item.forwardPlaybackEndTime = CMTime(seconds: endAbs, preferredTimescale: 600)
        item.seek(
            to: CMTime(seconds: startAbs, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        )
    }

    /// Applies persisted shot trim while advancing the queue (does not move the on-screen handles).
    private func applyPlaybackTrim(for shot: Shot, item: AVPlayerItem, assetSeconds: Double) {
        guard assetSeconds.isFinite, assetSeconds > 0.25 else { return }
        let durMs = assetSeconds * 1000
        let inMs = shot.previewTrimInMs.map(Double.init) ?? 0
        let outMs = shot.previewTrimOutMs.map(Double.init) ?? durMs
        let ts = max(0, min(1, inMs / durMs))
        let te = max(ts + 0.0001, min(1, outMs / durMs))
        editorPlaybackState.setPreviewTrim(startFraction: ts, endFraction: te)
        item.forwardPlaybackEndTime = CMTime(seconds: te * assetSeconds, preferredTimescale: 600)
        item.seek(
            to: CMTime(seconds: ts * assetSeconds, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        )
    }

    private func observeQueueCurrentItem() {
        currentItemObservation?.invalidate()
        currentItemObservation = queuePlayer.observe(\.currentItem, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                guard let item = queuePlayer.currentItem else { return }
                let loaded = try? await item.asset.load(.duration)
                let sec = loaded?.seconds ?? item.duration.seconds
                guard sec.isFinite, sec > 0.25 else { return }
                if let idx = queuePlayer.items().firstIndex(where: { $0 === item }),
                   idx < playbackQueueShots.count {
                    let shot = playbackQueueShots[idx]
                    applyPlaybackTrim(for: shot, item: item, assetSeconds: sec)
                }
            }
        }
    }
#endif

    var body: some View {
        SectionCard(
            title: "Preview",
            isCollapsed: $isCollapsed
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                if playableShots.isEmpty {
                    EmptyStateCard(
                        title: "No playable clips yet",
                        message: "Generate clips to preview timeline playback."
                    )
                } else {
                    Group {
                        if assetIsAudioOnly == nil {
                            ProgressView("Loading preview…")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else if assetIsAudioOnly == true {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                        .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.55))
                                    if waveformPeaks.isEmpty {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 48)
                                    } else {
                                        AudioWaveformWithPlayhead(
                                            peaks: waveformPeaks,
                                            progressFraction: waveformProgressFraction,
                                            onSeekFraction: { editorPlaybackState.seek(fraction: $0) }
                                        )
                                        .padding(.horizontal, CinefuseTokens.Spacing.s)
                                        .padding(.vertical, CinefuseTokens.Spacing.s)
                                    }
                                    if trimHandlesVisible {
                                        PreviewTrimHandlesOverlay(
                                            trimStartFraction: $trimStartFraction,
                                            trimEndFraction: $trimEndFraction,
                                            onDragEnded: {
                                                editorPlaybackState.setPreviewTrim(
                                                    startFraction: trimStartFraction,
                                                    endFraction: trimEndFraction
                                                )
#if canImport(AVFoundation)
                                                applyPlaybackTrimFromEditorState()
#endif
                                                schedulePersistPreviewTrim()
                                            }
                                        )
                                        .padding(.horizontal, CinefuseTokens.Spacing.s)
                                        .padding(.vertical, CinefuseTokens.Spacing.s)
                                        .allowsHitTesting(true)
                                    }
                                }
                                .frame(minHeight: 112)
                                PlaybackTimeLabels(playback: editorPlaybackState)
                                InlinePreviewPlayerSurface(player: queuePlayer)
                                    .frame(height: 2)
                                    .opacity(0.02)
                                    .allowsHitTesting(false)
                            }
                        } else {
                            ZStack {
                                InlinePreviewPlayerSurface(player: queuePlayer)
                                    .frame(minHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
                                if trimHandlesVisible {
                                    PreviewTrimHandlesOverlay(
                                        trimStartFraction: $trimStartFraction,
                                        trimEndFraction: $trimEndFraction,
                                        onDragEnded: {
                                            editorPlaybackState.setPreviewTrim(
                                                startFraction: trimStartFraction,
                                                endFraction: trimEndFraction
                                            )
#if canImport(AVFoundation)
                                            applyPlaybackTrimFromEditorState()
#endif
                                            schedulePersistPreviewTrim()
                                        }
                                    )
                                    .padding(CinefuseTokens.Spacing.s)
                                }
                            }

                            PlaybackTimeLabels(playback: editorPlaybackState)
                        }
                    }

                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        IconCommandButton(
                            systemName: "arrowtriangle.forward.circle",
                            label: "Play all clips from the start",
                            action: { playSequence(fromSelected: false) },
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: "play.fill",
                            label: "Play from selection through end",
                            action: { playSequence(fromSelected: true) },
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: "play.square.fill",
                            label: "Play selected clip only",
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
                        IconCommandButton(
                            systemName: "airplayvideo",
                            label: "AirPlay output",
                            action: {},
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: loopPreviewEnabled ? "repeat.1.circle.fill" : "repeat.circle",
                            label: loopPreviewEnabled ? "Disable loop playback" : "Enable loop playback",
                            action: { loopPreviewEnabled.toggle() },
                            tooltipEnabled: showTooltips
                        )
                        IconCommandButton(
                            systemName: isPoppedOut ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle",
                            label: isPoppedOut ? "Dock preview panel" : "Pop out preview panel",
                            action: onTogglePopout,
                            tooltipEnabled: showTooltips
                        )
                        HStack(spacing: CinefuseTokens.Spacing.xxs) {
                            Text("Speed")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            Picker("Speed", selection: $previewPlaybackRate) {
                                ForEach(Self.playbackRates, id: \.self) { speed in
                                    Text(playbackRateLabel(speed))
                                        .font(CinefuseTokens.Typography.micro)
                                        .tag(speed)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 74)
                            .font(CinefuseTokens.Typography.micro)
                        }

                        Spacer()
                        Text("Queue: \(playableShots.count) clips")
                            .font(CinefuseTokens.Typography.caption)
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            ensureLoopDefaultEnabled()
            if selectedShotId == nil {
                selectedShotId = playableShots.first?.id
            }
            configureLoopObserver()
#if canImport(AVFoundation)
            observeQueueCurrentItem()
#endif
            playSelectedOnly()
            attachPlaybackState()
        }
        .onDisappear {
            removeLoopObserver()
            persistTrimTask?.cancel()
#if canImport(AVFoundation)
            currentItemObservation?.invalidate()
            currentItemObservation = nil
#endif
        }
        .onChange(of: loopPreviewEnabled) { _, _ in
            configureLoopObserver()
        }
        .onChange(of: previewPlaybackRate) { _, _ in
            applyPlaybackRateIfPlaying()
        }
        .onChange(of: playbackRequestToken) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
        }
        .onChange(of: shots.map { "\($0.id):\($0.clipUrl ?? "")" }.joined(separator: "|")) { _, _ in
            if selectedShotId == nil {
                selectedShotId = playableShots.first?.id
            }
            playSelectedOnly()
            attachPlaybackState()
        }
        .onChange(of: selectedShotId) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
        }
        .onChange(of: selectedShot?.previewTrimInMs) { _, _ in
            syncTrimFractionsFromSelectedShot()
        }
        .onChange(of: selectedShot?.previewTrimOutMs) { _, _ in
            syncTrimFractionsFromSelectedShot()
        }
    }

    /// Extensions we treat as audio-only without probing the asset (instant waveform path).
    private static func urlLooksAudioOnly(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["wav", "mp3", "aac", "m4a", "flac", "ogg", "aiff", "aif", "caf"].contains(ext)
    }

#if canImport(AVFoundation)
    /// True when the file has no video track but has audio (or unknown tracks — defer to video surface).
    private static func assetHasNoVideoTrack(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let videos = try await asset.loadTracks(withMediaType: .video)
            if !videos.isEmpty { return false }
            let audios = try await asset.loadTracks(withMediaType: .audio)
            return !audios.isEmpty
        } catch {
            return false
        }
    }

    private func reloadAssetKindAndWaveform() async {
        guard let shot = selectedShot,
              let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL)
        else {
            await MainActor.run {
                assetIsAudioOnly = nil
                waveformPeaks = []
                previewAssetDurationSeconds = 0
            }
            return
        }
        let asset = AVURLAsset(url: url)
        let dur = try? await asset.load(.duration)
        let sec = dur?.seconds ?? 0
        if Self.urlLooksAudioOnly(url) {
            await MainActor.run { assetIsAudioOnly = true }
            let peaks = (try? await WaveformPeakLoader.loadPeaks(from: url)) ?? []
            await MainActor.run {
                waveformPeaks = peaks
                if sec.isFinite, sec > 0.25 {
                    previewAssetDurationSeconds = sec
                }
                syncTrimFractionsFromSelectedShot()
                if queuePlayer.items().count <= 1 {
                    applyPlaybackTrimFromEditorState()
                }
            }
            return
        }
        await MainActor.run { assetIsAudioOnly = nil }
        let audioOnly = await Self.assetHasNoVideoTrack(url: url)
        let peaks: [Float]
        if audioOnly {
            peaks = (try? await WaveformPeakLoader.loadPeaks(from: url)) ?? []
        } else {
            peaks = []
        }
        await MainActor.run {
            assetIsAudioOnly = audioOnly
            waveformPeaks = peaks
            if sec.isFinite, sec > 0.25 {
                previewAssetDurationSeconds = sec
            }
            syncTrimFractionsFromSelectedShot()
            if queuePlayer.items().count <= 1 {
                applyPlaybackTrimFromEditorState()
            }
        }
    }
#endif

    private func attachPlaybackState() {
        editorPlaybackState.attach(player: queuePlayer, shotId: selectedShot?.id)
        editorPlaybackState.setPreviewTrim(startFraction: trimStartFraction, endFraction: trimEndFraction)
    }

    private func playSequence(fromSelected: Bool) {
        let sequence: [Shot]
        if fromSelected, let selected = selectedShot, let selectedIndex = playableShots.firstIndex(where: { $0.id == selected.id }) {
            sequence = Array(playableShots[selectedIndex...])
        } else {
            sequence = playableShots
        }
        let items = sequence.compactMap { shot -> AVPlayerItem? in
            guard let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL) else { return nil }
            return AVPlayerItem(url: url)
        }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        playbackQueueShots = sequence
        lastPlaybackWasSequence = true
        lastSequenceStartedFromSelection = fromSelected
        for item in items {
            queuePlayer.insert(item, after: nil)
        }
        startPlayback()
        attachPlaybackState()
#if canImport(AVFoundation)
        Task { await reloadAssetKindAndWaveform() }
#endif
    }

    private func playSelectedOnly() {
        guard let selected = selectedShot,
              let url = selected.playbackURL(localRecords: localFileRecordsByRemoteURL)
        else {
            return
        }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        playbackQueueShots = [selected]
        lastPlaybackWasSequence = false
        queuePlayer.insert(AVPlayerItem(url: url), after: nil)
        startPlayback()
        attachPlaybackState()
#if canImport(AVFoundation)
        Task { await reloadAssetKindAndWaveform() }
#endif
    }

    private func configureLoopObserver() {
        removeLoopObserver()
        guard loopPreviewEnabled else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { _ in
            guard queuePlayer.items().isEmpty else { return }
            if lastPlaybackWasSequence {
                playSequence(fromSelected: lastSequenceStartedFromSelection)
            } else {
                playSelectedOnly()
            }
        }
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    private func ensureLoopDefaultEnabled() {
        if UserDefaults.standard.object(forKey: Self.loopPreferenceKey) == nil {
            loopPreviewEnabled = true
        }
    }

    private func playbackRateLabel(_ value: Double) -> String {
        if value == floor(value) {
            return "\(Int(value))x"
        }
        return "\(value.formatted(.number.precision(.fractionLength(2))))x"
    }

    private func startPlayback() {
        queuePlayer.play()
        queuePlayer.rate = Float(previewPlaybackRate)
    }

    private func applyPlaybackRateIfPlaying() {
        if queuePlayer.timeControlStatus == .playing {
            queuePlayer.rate = Float(previewPlaybackRate)
        }
    }
}

struct EditorAudioPreviewPanel: View {
    let shots: [Shot]
    let audioTracks: [AudioTrack]
    let audioJobs: [Job]
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    @Binding var selectedShotId: String?
    let playbackRequestToken: Int
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    let isPoppedOut: Bool
    let onTogglePopout: () -> Void
    @EnvironmentObject private var editorPlaybackState: EditorPlaybackState
    @State private var waveformPeaks: [Float] = []
    @State private var queuePlayer = AVQueuePlayer()
    @AppStorage("cinefuse.editor.preview.loopEnabled") private var loopPreviewEnabled = true
    @AppStorage("cinefuse.editor.preview.playbackRate") private var previewPlaybackRate = 1.0
    @State private var loopObserver: NSObjectProtocol?
    private static let loopPreferenceKey = "cinefuse.editor.preview.loopEnabled"
    private static let playbackRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private func shotMayPlayClipUrl(_ shot: Shot) -> Bool {
        shot.qualifiesForAudioModeLists(
            audioTracks: audioTracks,
            syncedLocalRecords: localFileRecordsByRemoteURL,
            audioJobs: audioJobs
        )
    }

    private var playableMediaURLs: [URL] {
        var urls: [URL] = []
        for shot in shots where shotMayPlayClipUrl(shot) {
            if let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL) {
                urls.append(url)
            }
        }
        for track in audioTracks {
            if let url = CinefusePlaybackURLResolver.resolveForPlayback(
                remoteURLString: track.sourceUrl,
                localRecords: localFileRecordsByRemoteURL
            ) {
                urls.append(url)
            }
        }
        return urls
    }

    private var primaryPreviewURL: URL? {
        if let selectedShotId,
           let shot = shots.first(where: { $0.id == selectedShotId }),
           shotMayPlayClipUrl(shot) {
            if let track = audioTracks.first(where: { $0.shotId == shot.id }),
               let url = CinefusePlaybackURLResolver.resolveForPlayback(
                   remoteURLString: track.sourceUrl,
                   localRecords: localFileRecordsByRemoteURL
               ) {
                return url
            }
            if let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL) {
                return url
            }
        }
        if let shot = shots.first(where: { shotMayPlayClipUrl($0) }),
           let url = shot.playbackURL(localRecords: localFileRecordsByRemoteURL) {
            return url
        }
        return audioTracks.compactMap { track -> URL? in
            CinefusePlaybackURLResolver.resolveForPlayback(
                remoteURLString: track.sourceUrl,
                localRecords: localFileRecordsByRemoteURL
            )
        }.first
    }

    private var shotsClipSignature: String {
        shots.map { "\($0.id):\($0.clipUrl ?? ""):\(shotMayPlayClipUrl($0))" }.joined(separator: "|")
    }

    private var tracksSourceSignature: String {
        audioTracks.map { "\($0.id):\($0.sourceUrl ?? "")" }.joined(separator: "|")
    }

    private var waveformProgressFraction: Double {
        guard editorPlaybackState.durationSeconds > 0 else { return 0 }
        return min(1, max(0, editorPlaybackState.currentTimeSeconds / editorPlaybackState.durationSeconds))
    }

    var body: some View {
        SectionCard(
            title: "Audio preview",
            isCollapsed: $isCollapsed
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                Group {
                    if primaryPreviewURL == nil {
                        EmptyStateCard(
                            title: "No playable audio yet",
                            message: "Generate lanes or attach clips, then preview the selection."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            ZStack {
                                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                    .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.55))
                                if waveformPeaks.isEmpty {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 48)
                                } else {
                                    AudioWaveformWithPlayhead(
                                        peaks: waveformPeaks,
                                        progressFraction: waveformProgressFraction,
                                        onSeekFraction: { editorPlaybackState.seek(fraction: $0) }
                                    )
                                    .padding(.horizontal, CinefuseTokens.Spacing.s)
                                    .padding(.vertical, CinefuseTokens.Spacing.s)
                                }
                            }
                            .frame(minHeight: 112)
                            PlaybackTimeLabels(playback: editorPlaybackState)
                            InlinePreviewPlayerSurface(player: queuePlayer)
                                .frame(height: 2)
                                .opacity(0.02)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .layoutPriority(1)
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    IconCommandButton(
                        systemName: "play.fill",
                        label: "Play all sources",
                        action: { playAllSources() },
                        tooltipEnabled: showTooltips
                    )
                    IconCommandButton(
                        systemName: "play.square.fill",
                        label: "Play selected",
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
                    IconCommandButton(
                        systemName: loopPreviewEnabled ? "repeat.1.circle.fill" : "repeat.circle",
                        label: loopPreviewEnabled ? "Disable loop playback" : "Enable loop playback",
                        action: { loopPreviewEnabled.toggle() },
                        tooltipEnabled: showTooltips
                    )
                    IconCommandButton(
                        systemName: isPoppedOut ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle",
                        label: isPoppedOut ? "Dock preview panel" : "Pop out preview panel",
                        action: onTogglePopout,
                        tooltipEnabled: showTooltips
                    )
                    HStack(spacing: CinefuseTokens.Spacing.xxs) {
                        Text("Speed")
                            .font(CinefuseTokens.Typography.caption)
                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        Picker("Speed", selection: $previewPlaybackRate) {
                            ForEach(Self.playbackRates, id: \.self) { speed in
                                Text(playbackRateLabel(speed))
                                    .font(CinefuseTokens.Typography.micro)
                                    .tag(speed)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 74)
                    }
                    Spacer()
                    Text("\(playableMediaURLs.count) sources")
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            ensureLoopDefaultEnabled()
            configureLoopObserver()
            playSelectedOnly()
            attachPlaybackState()
            Task { await reloadWaveformPeaks() }
        }
        .onDisappear {
            removeLoopObserver()
        }
        .onChange(of: loopPreviewEnabled) { _, _ in
            configureLoopObserver()
        }
        .onChange(of: previewPlaybackRate) { _, _ in
            if queuePlayer.timeControlStatus == .playing {
                queuePlayer.rate = Float(previewPlaybackRate)
            }
        }
        .onChange(of: playbackRequestToken) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
        }
        .onChange(of: shotsClipSignature) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
            Task { await reloadWaveformPeaks() }
        }
        .onChange(of: tracksSourceSignature) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
            Task { await reloadWaveformPeaks() }
        }
        .onChange(of: selectedShotId) { _, _ in
            playSelectedOnly()
            attachPlaybackState()
            Task { await reloadWaveformPeaks() }
        }
    }

    private func attachPlaybackState() {
        editorPlaybackState.attach(player: queuePlayer, shotId: selectedShotId)
    }

    private func reloadWaveformPeaks() async {
        guard let url = primaryPreviewURL else {
            await MainActor.run { waveformPeaks = [] }
            return
        }
        let peaks = (try? await WaveformPeakLoader.loadPeaks(from: url)) ?? []
        await MainActor.run {
            waveformPeaks = peaks
        }
    }

    private func playAllSources() {
        let items = playableMediaURLs.map { AVPlayerItem(url: $0) }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        for item in items {
            queuePlayer.insert(item, after: nil)
        }
        queuePlayer.play()
        queuePlayer.rate = Float(previewPlaybackRate)
        attachPlaybackState()
    }

    private func playSelectedOnly() {
        guard let url = primaryPreviewURL else { return }
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        queuePlayer.insert(AVPlayerItem(url: url), after: nil)
        queuePlayer.play()
        queuePlayer.rate = Float(previewPlaybackRate)
        attachPlaybackState()
    }

    private func configureLoopObserver() {
        removeLoopObserver()
        guard loopPreviewEnabled else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { _ in
            playSelectedOnly()
        }
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }

    private func ensureLoopDefaultEnabled() {
        if UserDefaults.standard.object(forKey: Self.loopPreferenceKey) == nil {
            loopPreviewEnabled = true
        }
    }

    private func playbackRateLabel(_ value: Double) -> String {
        if value == floor(value) {
            return "\(Int(value))x"
        }
        return "\(value.formatted(.number.precision(.fractionLength(2))))x"
    }
}

#if canImport(AVFoundation)
/// Sound blueprint references: accept audio-bearing media (audio track present) or stills (no video track). Rejects silent video (video track without audio).
private func urlPassesSoundBlueprintAudioPolicy(_ url: URL) async -> Bool {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let asset = AVURLAsset(url: url)
    do {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty { return true }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        return videoTracks.isEmpty
    } catch {
        return fallbackSoundBlueprintReferenceEligible(url)
    }
}

private func fallbackSoundBlueprintReferenceEligible(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    let videoExt: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi"]
    let audioExt: Set<String> = ["m4a", "wav", "aac", "mp3", "caf", "aiff", "flac", "ogg", "mp2"]
    if audioExt.contains(ext) { return true }
    if videoExt.contains(ext) { return false }
    return true
}
#endif

struct SoundBlueprintsPanel: View {
    @Binding var blueprints: [SoundBlueprint]
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    let uploadProjectFiles: ([URL]) async throws -> [String]
    let onCreate: (CreateSoundBlueprintRequest) -> Void
    let onPlayReferenceFile: (String) -> Void
    @State private var draftName = "Ambient blueprint"
    @State private var draftTemplate = "neutral"
    @State private var draftReferenceURLs: [URL] = []
    @State private var isImporterPresented = false
#if canImport(PhotosUI)
    @State private var draftPhotoPickerItems: [PhotosPickerItem] = []
#endif
    @State private var isSavingBlueprint = false
    @State private var blueprintError: String?

    private var blueprintPresetPicker: some View {
        Picker("Style preset", selection: $draftTemplate) {
            Text("Neutral").tag("neutral")
            Text("Punchy trailer").tag("punchy_trailer")
            Text("Soft vocal").tag("soft_vocal")
        }
        .pickerStyle(.menu)
    }

    private var addReferencesButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label("Add references…", systemImage: "waveform.badge.plus")
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .tooltip("Audio, video with sound, or stills — silent video files are skipped", enabled: showTooltips)
    }

    private var saveBlueprintButton: some View {
        Button {
            blueprintError = nil
            let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            Task {
                isSavingBlueprint = true
                defer { isSavingBlueprint = false }
                do {
                    let ids = try await uploadProjectFiles(draftReferenceURLs)
                    onCreate(CreateSoundBlueprintRequest(
                        name: name,
                        templateId: draftTemplate,
                        referenceFileIds: ids
                    ))
                    draftReferenceURLs = []
                } catch {
                    blueprintError = error.localizedDescription
                }
            }
        } label: {
            Label("Save blueprint", systemImage: "plus.rectangle.on.folder")
        }
        .buttonStyle(PrimaryActionButtonStyle())
        .tooltip("Upload references and persist blueprint for this project", enabled: showTooltips)
        .disabled(isSavingBlueprint)
    }

#if canImport(PhotosUI)
    private var chooseFromPhotosButton: some View {
        PhotosPicker(
            selection: $draftPhotoPickerItems,
            maxSelectionCount: 25,
            matching: .any(of: [.images, .videos])
        ) {
            Label("Choose from Photos…", systemImage: "photo.on.rectangle.angled")
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .tooltip("Pick stills or videos from your library as references", enabled: showTooltips)
    }
#endif

    private var blueprintActionButtonsHorizontal: some View {
        HStack(spacing: CinefuseTokens.Spacing.s) {
            addReferencesButton
#if canImport(PhotosUI)
            chooseFromPhotosButton
#endif
            saveBlueprintButton
        }
    }

    private var blueprintActionButtonsStacked: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
            addReferencesButton
                .frame(maxWidth: .infinity, alignment: .leading)
#if canImport(PhotosUI)
            chooseFromPhotosButton
                .frame(maxWidth: .infinity, alignment: .leading)
#endif
            saveBlueprintButton
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        SectionCard(
            title: "Sound blueprints",
            subtitle: "Add references from Files or Photos — audio, video with sound, or stills. Silent video (no audio track) is skipped.",
            isCollapsed: $isCollapsed
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: CinefuseTokens.Spacing.s) {
                        TextField("Blueprint name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                        blueprintPresetPicker
                        blueprintActionButtonsHorizontal
                    }
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        TextField("Blueprint name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                        blueprintPresetPicker
                        blueprintActionButtonsStacked
                    }
                }
                if !draftReferenceURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: CinefuseTokens.Spacing.xs) {
                            ForEach(Array(draftReferenceURLs.enumerated()), id: \.offset) { index, url in
                                HStack(spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(CinefuseTokens.Typography.micro)
                                        .lineLimit(1)
                                    Button {
                                        draftReferenceURLs.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                            }
                        }
                    }
                }
                if let blueprintError {
                    Text(blueprintError)
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.danger)
                }
                if blueprints.isEmpty {
                    EmptyStateCard(
                        title: "No blueprints yet",
                        message: "Add references and save a blueprint to reuse it when generating sounds."
                    )
                } else {
                    ForEach(blueprints) { blueprint in
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                            Text(blueprint.name)
                                .font(CinefuseTokens.Typography.cardTitle)
                            if let template = blueprint.templateId, !template.isEmpty {
                                Text("Style preset: \(template)")
                                    .font(CinefuseTokens.Typography.caption)
                                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            }
                            if !blueprint.referenceFileIds.isEmpty {
                                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                    Text("Reference files")
                                        .font(CinefuseTokens.Typography.micro.weight(.semibold))
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                    ForEach(blueprint.referenceFileIds, id: \.self) { fileId in
                                        HStack(spacing: CinefuseTokens.Spacing.xs) {
                                            Text(fileId)
                                                .font(CinefuseTokens.Typography.micro)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Button {
                                                onPlayReferenceFile(fileId)
                                            } label: {
                                                Image(systemName: "play.circle.fill")
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(CinefuseTokens.ColorRole.accent)
                                            .tooltip("Play reference audio", enabled: showTooltips)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(CinefuseTokens.Spacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image, .audio, .movie, .mpeg4Movie, UTType(filenameExtension: "wav") ?? .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
#if canImport(AVFoundation)
                Task { await appendFilteredBlueprintURLs(urls) }
#else
                draftReferenceURLs.append(contentsOf: urls)
#endif
            case .failure:
                break
            }
        }
#if canImport(PhotosUI)
        .onChange(of: draftPhotoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await appendDraftURLsFromPhotoPickerItems(newItems)
                draftPhotoPickerItems = []
            }
        }
#endif
    }

#if canImport(PhotosUI)
    @MainActor
    private func appendDraftURLsFromPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        var toAppend: [URL] = []
#if canImport(AVFoundation)
        var silentVideosSkipped = 0
#endif
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    blueprintError = "Could not load one or more items from your photo library."
                    continue
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("cinefuse-blueprint-\(UUID().uuidString).\(ext)")
                try data.write(to: dest)
#if canImport(AVFoundation)
                if await urlPassesSoundBlueprintAudioPolicy(dest) {
                    toAppend.append(dest)
                } else {
                    silentVideosSkipped += 1
                }
#else
                toAppend.append(dest)
#endif
            } catch {
                blueprintError = error.localizedDescription
            }
        }
        draftReferenceURLs.append(contentsOf: toAppend)
#if canImport(AVFoundation)
        if silentVideosSkipped > 0 {
            blueprintError = silentVideosSkipped == 1
                ? "Skipped 1 video with no audio track."
                : "Skipped \(silentVideosSkipped) videos with no audio track."
        }
#endif
    }
#endif

#if canImport(AVFoundation)
    @MainActor
    private func appendFilteredBlueprintURLs(_ urls: [URL]) async {
        blueprintError = nil
        var skipped = 0
        var accepted: [URL] = []
        for url in urls {
            if await urlPassesSoundBlueprintAudioPolicy(url) {
                accepted.append(url)
            } else {
                skipped += 1
            }
        }
        draftReferenceURLs.append(contentsOf: accepted)
        if skipped > 0 {
            blueprintError = skipped == 1
                ? "Skipped 1 video with no audio track. Use audio, video that includes sound, or stills."
                : "Skipped \(skipped) videos with no audio track. Use audio, video that includes sound, or stills."
        }
    }
#endif
}

private struct InlinePreviewPlayerSurface: View {
    let player: AVPlayer

    var body: some View {
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
        InlinePreviewPlayerMac(player: player)
#elseif canImport(UIKit)
        InlinePreviewPlayerIOS(player: player)
#else
        VideoPlayer(player: player)
#endif
    }
}

#if canImport(AppKit) && canImport(AVKit) && !targetEnvironment(macCatalyst)
private struct InlinePreviewPlayerMac: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.controlsStyle = .none
    }
}
#endif

#if canImport(UIKit) && canImport(AVKit)
private struct InlinePreviewPlayerIOS: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.showsPlaybackControls = false
    }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
private final class PreviewPopoutWindowController: NSWindowController, NSWindowDelegate {
    private let onWindowClose: () -> Void

    init<Content: View>(rootView: Content, onWindowClose: @escaping () -> Void) {
        self.onWindowClose = onWindowClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preview"
        window.minSize = NSSize(width: 760, height: 440)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.contentView = NSHostingView(rootView: AnyView(rootView))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update<Content: View>(rootView: Content) {
        window?.contentView = NSHostingView(rootView: AnyView(rootView))
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
private struct ResizeSplitCursorModifier: ViewModifier {
    enum Axis {
        case horizontalDrag
        case verticalDrag
    }

    let axis: Axis

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                switch axis {
                case .horizontalDrag:
                    NSCursor.resizeLeftRight.push()
                case .verticalDrag:
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }
}
#else
private struct ResizeSplitCursorModifier: ViewModifier {
    enum Axis {
        case horizontalDrag
        case verticalDrag
    }

    let axis: Axis

    func body(content: Content) -> some View {
        content
    }
}
#endif

struct VerticalPanelHandle: View {
    var accessibilityLabel: String = "Drag to resize panels"
    let onDrag: (Double) -> Void
    @State private var lastTranslation: Double = 0
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CinefuseTokens.ColorRole.accent.opacity(isHovering ? 0.22 : 0))
            Rectangle()
                .fill(CinefuseTokens.ColorRole.borderSubtle.opacity(isHovering ? 0.95 : 0.65))
                .frame(width: max(2, CinefuseTokens.Control.splitterThickness - 1))
            Capsule()
                .fill(CinefuseTokens.ColorRole.textSecondary.opacity(isHovering ? 0.55 : 0.3))
                .frame(width: 2, height: 36)
        }
        .frame(width: CinefuseTokens.Control.splitterThickness)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .modifier(ResizeSplitCursorModifier(axis: .horizontalDrag))
        .accessibilityLabel(accessibilityLabel)
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
    var accessibilityLabel: String = "Drag to resize panels"
    let onDrag: (Double) -> Void
    @State private var lastTranslation: Double = 0
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CinefuseTokens.ColorRole.accent.opacity(isHovering ? 0.22 : 0))
            Rectangle()
                .fill(CinefuseTokens.ColorRole.borderSubtle.opacity(isHovering ? 0.95 : 0.65))
                .frame(height: max(2, CinefuseTokens.Control.splitterThickness - 1))
            Capsule()
                .fill(CinefuseTokens.ColorRole.textSecondary.opacity(isHovering ? 0.55 : 0.3))
                .frame(width: 36, height: 2)
        }
        .frame(height: CinefuseTokens.Control.splitterThickness)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .modifier(ResizeSplitCursorModifier(axis: .verticalDrag))
        .accessibilityLabel(accessibilityLabel)
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
    @Binding var isCollapsed: Bool

    @State private var revisionDraftBySceneId: [String: String] = [:]

    var body: some View {
        SectionCard(
            title: "Storyboard",
            isCollapsed: $isCollapsed
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

private enum CharacterTrainingRefMediaKind {
    case image, video, audio, unknown
}

private func characterTrainingRefMediaKind(for url: URL) -> CharacterTrainingRefMediaKind {
    let ext = url.pathExtension.lowercased()
    if let ut = UTType(filenameExtension: ext) {
        if ut.conforms(to: .image) { return .image }
        if ut.conforms(to: .movie) || ut.conforms(to: .video) || ut.conforms(to: .mpeg4Movie) {
            return .video
        }
        if ut.conforms(to: .audio) { return .audio }
    }
    let imageExt: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "bmp"]
    let videoExt: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
    let audioExt: Set<String> = ["m4a", "wav", "aac", "mp3", "caf", "aiff", "flac", "ogg"]
    if imageExt.contains(ext) { return .image }
    if videoExt.contains(ext) { return .video }
    if audioExt.contains(ext) { return .audio }
    return .unknown
}

private func characterTrainingImageFromFile(_ url: URL) -> Image? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    guard let ns = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: ns)
#elseif canImport(UIKit)
    guard let ui = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: ui)
#else
    return nil
#endif
}

private func characterTrainingImageFromJPEGData(_ data: Data) -> Image? {
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    guard let ns = NSImage(data: data) else { return nil }
    return Image(nsImage: ns)
#elseif canImport(UIKit)
    guard let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
#else
    return nil
#endif
}

#if canImport(AVFoundation)
private func characterTrainingVideoThumbnailJPEG(from url: URL) -> Data? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 512, height: 512)
    let frameTime = CMTime(seconds: 0.15, preferredTimescale: 600)
    guard let cgImage = try? generator.copyCGImage(at: frameTime, actualTime: nil) else {
        return nil
    }
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    let image = NSImage(cgImage: cgImage, size: .zero)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
#elseif canImport(UIKit)
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.88)
#else
    return nil
#endif
}
#endif

/// Local training reference: thumbnail in a square; double-click to confirm removal.
private struct CharacterTrainingReferenceTile: View {
    let url: URL
    let showTooltips: Bool
    let onRemove: () -> Void
    @State private var thumbnail: Image?
    @State private var loadedKind: CharacterTrainingRefMediaKind = .unknown
    @State private var confirmDelete = false

    private let tileSize: CGFloat = 56

    var body: some View {
        ZStack {
            Group {
                switch loadedKind {
                case .image, .video:
                    if let thumbnail {
                        thumbnail
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                            .scaleEffect(0.65)
                    }
                case .audio:
                    Image(systemName: "waveform")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(CinefuseTokens.ColorRole.accent)
                case .unknown:
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }
            }
            .frame(width: tileSize, height: tileSize)
            .clipped()

            VStack {
                Spacer()
                Text(url.lastPathComponent)
                    .font(CinefuseTokens.Typography.micro)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.55))
            }
        }
        .frame(width: tileSize, height: tileSize)
        .background(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            confirmDelete = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reference file \(url.lastPathComponent)")
        .accessibilityHint("Double tap to remove from training list")
        .tooltip(url.lastPathComponent, enabled: showTooltips)
        .confirmationDialog(
            "Remove this reference?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(url.lastPathComponent) from the training list. The file on disk is not deleted.")
        }
        .task(id: url) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        loadedKind = characterTrainingRefMediaKind(for: url)
        thumbnail = nil
        switch loadedKind {
        case .image:
            thumbnail = characterTrainingImageFromFile(url)
        case .video:
#if canImport(AVFoundation)
            if let data = characterTrainingVideoThumbnailJPEG(from: url) {
                thumbnail = characterTrainingImageFromJPEGData(data)
            }
#endif
            break
        case .audio, .unknown:
            break
        }
    }
}

private struct CharacterTrainingReferenceButtons: View {
    @Binding var trainingURLs: [URL]
    let showTooltips: Bool
    @State private var isImporterPresented = false
#if canImport(PhotosUI)
    @State private var photoPickerItems: [PhotosPickerItem] = []
#endif
    @State private var photoLoadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            HStack(spacing: CinefuseTokens.Spacing.xs) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Add reference", systemImage: "paperclip")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .tooltip("Attach reference media from Files (image, video, or audio). Multiple files allowed.", enabled: showTooltips)
#if canImport(PhotosUI)
                PhotosPicker(
                    selection: $photoPickerItems,
                    maxSelectionCount: 25,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("From Photos…", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .tooltip("Choose reference stills or videos from your library", enabled: showTooltips)
#endif
            }
            if let photoLoadError {
                Text(photoLoadError)
                    .font(CinefuseTokens.Typography.micro)
                    .foregroundStyle(CinefuseTokens.ColorRole.danger)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image, .movie, .audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var list = trainingURLs
                list.append(contentsOf: urls)
                trainingURLs = list
            case .failure:
                break
            }
        }
#if canImport(PhotosUI)
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await appendFromPhotoLibrary(newItems)
                photoPickerItems = []
            }
        }
#endif
    }

#if canImport(PhotosUI)
    @MainActor
    private func appendFromPhotoLibrary(_ items: [PhotosPickerItem]) async {
        photoLoadError = nil
        var list = trainingURLs
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    photoLoadError = "Could not load one or more items from your photo library."
                    continue
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("cinefuse-char-\(UUID().uuidString).\(ext)")
                try data.write(to: dest)
                list.append(dest)
            } catch {
                photoLoadError = error.localizedDescription
            }
        }
        trainingURLs = list
    }
#endif
}

struct CharacterPanel: View {
    let characters: [CharacterProfile]
    @Binding var newCharacterName: String
    @Binding var newCharacterDescription: String
    let onCreateCharacter: () -> Void
    let uploadProjectFiles: ([URL]) async throws -> [String]
    let onTrainCharacter: (String, [String]) -> Void
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    @State private var trainingRefsByCharacterId: [String: [URL]] = [:]
    @State private var trainBusyCharacterId: String?
    @State private var trainError: String?

    var body: some View {
        SectionCard(
            title: "Characters",
            subtitle: "Add reference images, video, or audio from Files or Photos, then Train — uploads register as referenceFileIds for identity training."
            ,
            isCollapsed: $isCollapsed
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

                if let trainError {
                    Text(trainError)
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.danger)
                }

                if characters.isEmpty {
                    EmptyStateCard(
                        title: "No characters created",
                        message: "Add a character and train it before locking to key shots."
                    )
                } else {
                    ForEach(characters) { character in
                        let isTrainingThis = trainBusyCharacterId == character.id
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: CinefuseTokens.Spacing.s) {
                                Text(character.name)
                                    .font(CinefuseTokens.Typography.cardTitle)
                                    .lineLimit(2)
                                    .layoutPriority(1)
                                Spacer(minLength: CinefuseTokens.Spacing.s)
                                if character.status.lowercased() != "ready" {
                                    StatusBadge(status: character.status)
                                }
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
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: CinefuseTokens.Spacing.xs) {
                                    if let preview = character.previewUrl, let url = URL(string: preview) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            default:
                                                Color.clear
                                            }
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                                                .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                                        )
                                    }
                                    ForEach(Array((trainingRefsByCharacterId[character.id] ?? []).enumerated()), id: \.offset) { _, ref in
                                        CharacterTrainingReferenceTile(
                                            url: ref,
                                            showTooltips: showTooltips,
                                            onRemove: {
                                                var list = trainingRefsByCharacterId[character.id] ?? []
                                                list.removeAll { $0 == ref }
                                                if list.isEmpty {
                                                    trainingRefsByCharacterId[character.id] = nil
                                                } else {
                                                    trainingRefsByCharacterId[character.id] = list
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            HStack(alignment: .top, spacing: CinefuseTokens.Spacing.xs) {
                                CharacterTrainingReferenceButtons(
                                    trainingURLs: Binding(
                                        get: { trainingRefsByCharacterId[character.id] ?? [] },
                                        set: { trainingRefsByCharacterId[character.id] = $0 }
                                    ),
                                    showTooltips: showTooltips
                                )
                                if character.status.lowercased() != "trained" {
                                    Button {
                                        trainError = nil
                                        Task {
                                            trainBusyCharacterId = character.id
                                            defer { trainBusyCharacterId = nil }
                                            do {
                                                let urls = trainingRefsByCharacterId[character.id] ?? []
                                                let ids = try await uploadProjectFiles(urls)
                                                onTrainCharacter(character.id, ids)
                                            } catch {
                                                trainError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Train", systemImage: "figure.strengthtraining.traditional")
                                    }
                                    .tooltip("Upload references and train this character for consistency", enabled: showTooltips)
                                    .buttonStyle(SecondaryActionButtonStyle())
                                    .disabled(isTrainingThis)
                                }
                                if character.status.lowercased() == "trained" || character.status.lowercased() == "ready" {
                                    Button {
                                        trainError = nil
                                        Task {
                                            trainBusyCharacterId = character.id
                                            defer { trainBusyCharacterId = nil }
                                            do {
                                                let urls = trainingRefsByCharacterId[character.id] ?? []
                                                let ids = try await uploadProjectFiles(urls)
                                                onTrainCharacter(character.id, ids)
                                            } catch {
                                                trainError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Retrain", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .tooltip("Run training again with updated references", enabled: showTooltips)
                                    .buttonStyle(SecondaryActionButtonStyle())
                                    .disabled(isTrainingThis)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    let jobs: [Job]
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    let localThumbnailURLByShotId: [String: URL]
    let shotRequestStateById: [String: RenderRequestState]
    let characterOptions: [CharacterProfile]
    @Binding var shotPromptDraft: String
    @Binding var shotModelTierDraft: String
    @Binding var selectedCharacterLockId: String
    let quotedShotCost: ShotQuote?
    let onQuote: () -> Void
    let onCreateShot: () -> Void
    let onGenerateShot: (String) -> Void
    let onRetryShot: (String) -> Void
    let onDeleteShot: (String) -> Void
    let onPreviewShot: (String) -> Void
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    var panelMode: ShotsPanelMode = .videoClips
    var soundBlueprints: [SoundBlueprint] = []
    @Binding var selectedSoundBlueprintIdsByShotId: [String: Set<String>]
    @Binding var draftSoundBlueprintIds: Set<String>
    @Binding var selectedTimelineShotId: String?
    let soundSourceLabel: (Shot) -> String
    @Binding var soundTagsDraft: String
    let onRefreshStatusDetails: () async -> Void
    /// Audio workspace: score settings card above Quote / Create Sound (ElevenLabs Music).
    var showScoreGenerationControls: Bool = false
    @Binding var scoreDurationSeconds: Double
    @Binding var scoreLyricsModeSelection: ScoreGenerationLyricsMode
    @Binding var scoreCustomLyricsDraft: String
    @State private var pendingDeleteShotId: String?
    @State private var selectedDiagnostics: ArtifactStatusPresentation?
    @State private var diagnosticsSheetShotId: String?
    @State private var soundTagsByShotId: [String: String] = [:]
    @Environment(\.openURL) private var openURL

    private let inFlightStatuses: Set<String> = ["queued", "generating", "running", "processing"]
    private let diagnosticsTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var playRenderClipButtonLabel: some View {
        Label("Play Render", systemImage: "play.circle")
            .font(CinefuseTokens.Typography.caption.weight(.semibold))
    }

    private func renderProgress(for shot: Shot) -> Int? {
        if let p = latestJob(for: shot.id)?.progressPct {
            return max(0, min(100, p))
        }
        switch shot.status {
        case "queued":
            return 5
        case "generating", "running", "processing":
            return 35
        case "ready":
            return 100
        case "failed":
            return 0
        default:
            return nil
        }
    }

    private func latestJob(for shotId: String) -> Job? {
        jobs
            .filter { $0.shotId == shotId }
            .max { lhs, rhs in
                parseTimestamp(lhs.updatedAt) < parseTimestamp(rhs.updatedAt)
            }
    }

    private func parseTimestamp(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    private func diagnosticsLine(for shot: Shot) -> String? {
        guard let job = latestJob(for: shot.id) else { return nil }
        let isStubRuntime = (job.providerAdapter == "stub")
            || ((job.providerEndpoint ?? "").hasPrefix("stub://"))
        if isStubRuntime {
            return "Sound diagnostics: Stub media mode active - disable CINEFUSE_ALLOW_STUB_MEDIA and restart app/gateway."
        }
        if let requestState = shotRequestStateById[shot.id],
           let error = requestState.errorMessage,
           error.localizedCaseInsensitiveContains("retry is only for failed shots") {
            let label = panelMode == .audioSounds ? "Sound diagnostics" : "Render diagnostics"
            return "\(label): Retry conflict - \(error)"
        }
        let progressText = (job.progressPct ?? renderProgress(for: shot)).map { "\($0)%" } ?? "n/a"
        let statusText = job.status.capitalized
        let updatedAt = parseTimestamp(job.updatedAt)
        let age = Date().timeIntervalSince(updatedAt)
        let updatedText = updatedAt == .distantPast
            ? "update unknown"
            : "updated \(diagnosticsTimestampFormatter.localizedString(for: updatedAt, relativeTo: Date()))"
        let providerNotStarted: Bool
        if panelMode == .audioSounds {
            let pe = (job.providerEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fe = (job.falEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rid = (job.requestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            providerNotStarted = pe.isEmpty && fe.isEmpty && (rid.isEmpty || rid == "n/a")
        } else {
            providerNotStarted = (job.requestId == nil || job.requestId == "n/a")
                && (job.falEndpoint == nil || job.falEndpoint == "n/a")
                && (job.falStatusUrl == nil || job.falStatusUrl == "n/a")
        }
        let diagLabel = panelMode == .audioSounds ? "Sound diagnostics" : "Render diagnostics"
        if let rs = shotRequestStateById[shot.id], rs.stage == .timedOut,
           shot.status == "queued", providerNotStarted, !isStubRuntime {
            return "\(diagLabel): Timed out while queued — render queue may have no consumer (Redis + render-worker). Start render-worker or use in-process queue without Redis for local dev."
        }
        if job.status == "queued", age > 30, providerNotStarted {
            return "\(diagLabel): Queued too long (>30s) - worker backlog/offline likely. Check render-worker logs."
        }
        if inFlightStatuses.contains(job.status), age > 20 {
            return "\(diagLabel): \(statusText) \(progressText) - no update in \(Int(age))s"
        }
        return "\(diagLabel): \(statusText) \(progressText) - \(updatedText)"
    }

    private func statusPresentation(for shot: Shot) -> ArtifactStatusPresentation {
        let latest = latestJob(for: shot.id)
        let localRecord = shot.clipUrl.flatMap { localFileRecordsByRemoteURL[$0] }
        return shotArtifactStatusPresentation(
            shot: shot,
            job: latest,
            localRecord: localRecord,
            requestState: shotRequestStateById[shot.id]
        )
    }

    private var promptFieldTitle: String {
        panelMode == .audioSounds
            ? "Ambience, room tone, SFX, score, or a line of dialogue to generate"
            : "Describe the shot action or camera movement"
    }

    private var createButtonTitle: String {
        panelMode == .audioSounds ? "Create Sound" : "Create Shot"
    }

    /// Timeline selection scopes blueprint edits; nil targets defaults for the next Create Sound.
    private var toolbarBlueprintShotId: String? {
        guard let sid = selectedTimelineShotId, shots.contains(where: { $0.id == sid }) else {
            return nil
        }
        return sid
    }

    private func toolbarBlueprintBinding() -> Binding<Set<String>> {
        Binding(
            get: {
                if let id = toolbarBlueprintShotId {
                    return selectedSoundBlueprintIdsByShotId[id] ?? []
                }
                return draftSoundBlueprintIds
            },
            set: { newValue in
                if let id = toolbarBlueprintShotId {
                    var map = selectedSoundBlueprintIdsByShotId
                    if newValue.isEmpty {
                        map.removeValue(forKey: id)
                    } else {
                        map[id] = newValue
                    }
                    selectedSoundBlueprintIdsByShotId = map
                } else {
                    draftSoundBlueprintIds = newValue
                }
            }
        )
    }

    private func blueprintPickerSummary(selection: Set<String>) -> String {
        let n = selection.count
        if n == 0 {
            return "Choose blueprints…"
        }
        return n == 1 ? "1 blueprint selected" : "\(n) blueprints selected"
    }

    private var toolbarBlueprintSelection: Set<String> {
        if let id = toolbarBlueprintShotId {
            return selectedSoundBlueprintIdsByShotId[id] ?? []
        }
        return draftSoundBlueprintIds
    }

    private func toggleToolbarBlueprint(_ blueprintId: String) {
        var next = toolbarBlueprintSelection
        if next.contains(blueprintId) {
            next.remove(blueprintId)
        } else {
            next.insert(blueprintId)
        }
        toolbarBlueprintBinding().wrappedValue = next
    }

    /// Inline Sound blueprints control on the tier row (audio mode), matching Character Lock width.
    @ViewBuilder
    private func soundBlueprintsInlineMenu() -> some View {
        if soundBlueprints.isEmpty {
            HStack(spacing: CinefuseTokens.Spacing.xs) {
                Text("Sound blueprints")
                Spacer(minLength: 4)
                Text("None")
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.5))
            }
            .font(CinefuseTokens.Typography.body)
            .frame(width: CinefuseTokens.Control.secondaryPickerWidth, alignment: .leading)
            .opacity(0.55)
            .help("Add references on the left Sound blueprints panel, then Save.")
        } else {
            Menu {
                ForEach(soundBlueprints) { blueprint in
                    Button {
                        toggleToolbarBlueprint(blueprint.id)
                    } label: {
                        HStack {
                            Text(blueprint.name)
                            Spacer(minLength: 12)
                            if toolbarBlueprintSelection.contains(blueprint.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: CinefuseTokens.Spacing.xs) {
                    Text("Sound blueprints")
                    Spacer(minLength: 4)
                    Text(blueprintPickerSummary(selection: toolbarBlueprintSelection))
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }
            }
            .frame(width: CinefuseTokens.Control.secondaryPickerWidth, alignment: .leading)
        }
    }

    /// Quote Cost to the left of Create Shot / Create Sound on one row.
    @ViewBuilder
    private func quoteAndCreateButtons() -> some View {
        let quote = Button {
            onQuote()
        } label: {
            Label("Quote Cost", systemImage: "tag")
        }
        .tooltip("Estimate sparks before generation", enabled: showTooltips)
        .buttonStyle(SecondaryActionButtonStyle())

        let create = Button {
            onCreateShot()
        } label: {
            Label(createButtonTitle, systemImage: "plus.rectangle.on.rectangle")
        }
        .tooltip(
            panelMode == .audioSounds ? "Create sound draft in timeline" : "Create shot draft in timeline",
            enabled: showTooltips
        )
        .buttonStyle(PrimaryActionButtonStyle())

        HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
            quote
            create
        }
    }

    /// Above Quote / Create Sound: duration and lyrics mode used when Create Sound is pressed (stored on the draft shot).
    private var scoreGenerationSoundCard: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            HStack(spacing: CinefuseTokens.Spacing.s) {
                Text("Duration")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                Slider(value: $scoreDurationSeconds, in: 3...600, step: 1)
                Text(CinefuseDurationFormatting.minutesSeconds(totalWholeSeconds: Int(scoreDurationSeconds)))
                    .font(CinefuseTokens.Typography.caption.monospacedDigit())
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Picker("Lyrics mode", selection: $scoreLyricsModeSelection) {
                ForEach(ScoreGenerationLyricsMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
#if os(iOS)
            .pickerStyle(.menu)
#else
            .pickerStyle(.segmented)
#endif
            if scoreLyricsModeSelection == .custom {
                TextField(
                    "Custom lyrics",
                    text: $scoreCustomLyricsDraft,
                    axis: .vertical
                )
                .lineLimit(5...14)
                .textFieldStyle(.roundedBorder)
                .font(CinefuseTokens.Typography.body)
            }
        }
        .padding(CinefuseTokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium, style: .continuous)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(0.88))
        )
    }

    var body: some View {
        SectionCard(
            title: panelMode == .audioSounds ? "Sounds" : "Shots",
            subtitle: panelMode == .audioSounds
                ? (showScoreGenerationControls
                    ? "Duration and lyrics mode apply when you tap Create Sound. Then prompt, tier, Sound blueprints, Quote."
                    : "Tier row includes Sound blueprints (menu). Add reference files on the left panel only. Timeline selection scopes which sound’s blueprint set you edit.")
                : "1: Draft shot 2: Quote cost 3: Generate 4: Review",
            isCollapsed: $isCollapsed
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                if panelMode == .audioSounds && showScoreGenerationControls {
                    scoreGenerationSoundCard
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                        TextField(promptFieldTitle, text: $shotPromptDraft)
                            .textFieldStyle(.roundedBorder)
                        Picker("Tier", selection: $shotModelTierDraft) {
                            Text("Budget").tag("budget")
                            Text("Standard").tag("standard")
                            Text("Premium").tag("premium")
                        }
                        .pickerStyle(.menu)
                        .frame(width: CinefuseTokens.Control.primaryPickerWidth)
                        if panelMode == .videoClips {
                            Picker("Character Lock", selection: $selectedCharacterLockId) {
                                Text("No lock").tag("")
                                ForEach(characterOptions) { character in
                                    Text(character.name).tag(character.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: CinefuseTokens.Control.secondaryPickerWidth)
                        }
                        if panelMode == .audioSounds {
                            soundBlueprintsInlineMenu()
                        }
                        quoteAndCreateButtons()
                    }
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                        TextField(promptFieldTitle, text: $shotPromptDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                            Picker("Tier", selection: $shotModelTierDraft) {
                                Text("Budget").tag("budget")
                                Text("Standard").tag("standard")
                                Text("Premium").tag("premium")
                            }
                            .pickerStyle(.menu)
                            .frame(width: CinefuseTokens.Control.primaryPickerWidth)
                            if panelMode == .videoClips {
                                Picker("Character Lock", selection: $selectedCharacterLockId) {
                                    Text("No lock").tag("")
                                    ForEach(characterOptions) { character in
                                        Text(character.name).tag(character.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: CinefuseTokens.Control.secondaryPickerWidth)
                            }
                            if panelMode == .audioSounds {
                                soundBlueprintsInlineMenu()
                            }
                        }
                        quoteAndCreateButtons()
                    }
                }

                if panelMode == .audioSounds {
                    Text(
                        toolbarBlueprintShotId == nil
                            ? "No timeline clip selected — blueprint choices apply to the next sound you create."
                            : "Editing the highlighted timeline sound. Generate uses these blueprint associations."
                    )
                    .font(CinefuseTokens.Typography.micro)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if panelMode == .audioSounds {
                    TextField("Tags (comma-separated)", text: $soundTagsDraft)
                        .textFieldStyle(.roundedBorder)
                }

                if let quotedShotCost {
                    let durationText = quotedShotCost.estimatedDurationSec.map { "~\($0)s" } ?? "~5s"
                    Text("Estimated: \(quotedShotCost.sparksCost) Sparks · \(quotedShotCost.modelId) · \(durationText)")
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }

                if shots.isEmpty {
                    EmptyStateCard(
                        title: panelMode == .audioSounds ? "No sounds drafted" : "No shots drafted",
                        message: panelMode == .audioSounds
                            ? "Create your first sound above, then quote and generate."
                            : "Create your first shot above, then quote and generate."
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ForEach(shots) { shot in
                        let presentation = statusPresentation(for: shot)
                        let backgroundThumbnailURL = panelMode == .audioSounds
                            ? nil
                            : localThumbnailURLByShotId[shot.id]
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                HStack(spacing: CinefuseTokens.Spacing.xs) {
                                    GenerationStatusDot(status: presentation)
                                        .tooltip(presentation.summary, enabled: showTooltips)
                                        .contextMenu {
                                            Button("Copy Diagnostics") {
                                                copyTextToClipboard(presentation.details)
                                            }
                                        }
                                        .onTapGesture {
                                            diagnosticsSheetShotId = shot.id
                                            selectedDiagnostics = presentation
                                        }
                                    if shot.status.lowercased() != "ready" {
                                        StatusBadge(status: shot.status)
                                    }
                                    Spacer()
                                }
                                Text(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                    .font(CinefuseTokens.Typography.body)
                                    .lineLimit(2)
                                    .layoutPriority(1)
                                    .textSelection(.enabled)
                                    .contextMenu {
                                        Button("Copy prompt") {
                                            copyTextToClipboard(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                        }
                                    }
                                Text(shot.modelTier.capitalized)
                                    .font(CinefuseTokens.Typography.caption)
                                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                if panelMode == .audioSounds {
                                    HStack(spacing: CinefuseTokens.Spacing.s) {
                                        Text("Origin (automatic)")
                                            .font(CinefuseTokens.Typography.caption)
                                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                        Text(soundSourceLabel(shot))
                                            .font(CinefuseTokens.Typography.body.weight(.medium))
                                            .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
                                            .textSelection(.enabled)
                                        Spacer(minLength: CinefuseTokens.Spacing.s)
                                        TextField(
                                            "Tags",
                                            text: Binding(
                                                get: { soundTagsByShotId[shot.id] ?? soundTagsDraft },
                                                set: { soundTagsByShotId[shot.id] = $0 }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)
                                    }
                                }
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
                                if inFlightStatuses.contains(shot.status) {
                                    GenerationActivityProgressRow(
                                        determinatePercent: latestJob(for: shot.id)?
                                            .progressPct
                                            .map { max(0, min(100, $0)) },
                                        waitingLabel: panelMode == .audioSounds
                                            ? "Generating sound…"
                                            : "Rendering…",
                                        determinateLabel: { p in
                                            panelMode == .audioSounds
                                                ? "Generating sound \(p)%"
                                                : "Rendering \(p)%"
                                        }
                                    )
                                }
                                if let diagnostics = diagnosticsLine(for: shot) {
                                    let diagnosticsText = diagnostics
                                    Text(verbatim: diagnosticsText)
                                        .font(CinefuseTokens.Typography.micro)
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                }
                            }
                            .modifier(ConditionalReadableVideoLabelBackdrop(useFrostedPlate: panelMode != .audioSounds))
                            if panelMode == .audioSounds {
                                HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                                    Button {
                                        onGenerateShot(shot.id)
                                    } label: {
                                        Label("Generate sound", systemImage: "waveform")
                                            .font(CinefuseTokens.Typography.caption.weight(.semibold))
                                    }
                                    .lineLimit(1)
                                    .tooltip("Generate audio for this sound", enabled: showTooltips)
                                    .buttonStyle(SecondaryActionButtonStyle())
                                    .disabled(inFlightStatuses.contains(shot.status) || shot.status == "ready")
                                    if let clipUrl = shot.clipUrl, !clipUrl.isEmpty {
                                        let playURL = shot.playbackURL(localRecords: localFileRecordsByRemoteURL)
                                        Button {
                                            onPreviewShot(shot.id)
                                            if let playURL {
                                                openURL(playURL)
                                            }
                                        } label: {
                                            Label("Play", systemImage: "play.circle")
                                                .font(CinefuseTokens.Typography.caption.weight(.semibold))
                                        }
                                        .lineLimit(1)
                                        .disabled(playURL == nil)
                                        .tooltip(
                                            playURL == nil
                                                ? "Gateway file URLs need a local copy before playback. Wait for sync or open Diagnostics."
                                                : "Open rendered output",
                                            enabled: showTooltips
                                        )
                                        .buttonStyle(SecondaryActionButtonStyle())
                                    }
                                    Button {
                                        onRetryShot(shot.id)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 18, height: 18)
                                    .tooltip("Retry failed or restart queued shot", enabled: showTooltips)
                                    .disabled(!(shot.status == "failed" || shot.status == "queued"))
                                    Button(role: .destructive) {
                                        pendingDeleteShotId = shot.id
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(CinefuseTokens.ColorRole.danger)
                                    .tooltip("Delete sound", enabled: showTooltips)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Button {
                                    onGenerateShot(shot.id)
                                } label: {
                                    Label(
                                        "Generate",
                                        systemImage: "video.badge.plus"
                                    )
                                        .font(CinefuseTokens.Typography.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .tooltip("Generate final clip for this shot", enabled: showTooltips)
                                .buttonStyle(SecondaryActionButtonStyle())
                                .disabled(inFlightStatuses.contains(shot.status) || shot.status == "ready")
                                if let clipUrl = shot.clipUrl, !clipUrl.isEmpty {
                                    let playURL = shot.playbackURL(localRecords: localFileRecordsByRemoteURL)
                                    Button {
                                        onPreviewShot(shot.id)
                                        if let playURL {
                                            openURL(playURL)
                                        }
                                    } label: {
                                        playRenderClipButtonLabel
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .disabled(playURL == nil)
                                    .tooltip(
                                        playURL == nil
                                            ? "Gateway file URLs need a local copy before playback. Wait for sync or open Diagnostics."
                                            : "Open rendered clip playback",
                                        enabled: showTooltips
                                    )
                                    .buttonStyle(SecondaryActionButtonStyle())
                                }
                                HStack(spacing: CinefuseTokens.Spacing.xs) {
                                    Button {
                                        onRetryShot(shot.id)
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 18, height: 18)
                                    .tooltip("Retry failed or restart queued shot", enabled: showTooltips)
                                    .disabled(!(shot.status == "failed" || shot.status == "queued"))

                                    Button(role: .destructive) {
                                        pendingDeleteShotId = shot.id
                                    } label: {
                                        Image(systemName: "delete.left")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(CinefuseTokens.ColorRole.danger)
                                    .tooltip("Delete shot", enabled: showTooltips)
                                }
                            }
                        }
                        .padding(CinefuseTokens.Spacing.s)
                        .background(
                            MediaCardBackground(imageURL: backgroundThumbnailURL)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
                        .contentShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .padding(CinefuseTokens.Spacing.s)
        .animation(CinefuseTokens.Motion.standard, value: shots.map(\.id))
        .onChange(of: shots.map(\.id)) { _, ids in
            let allowed = Set(ids)
            soundTagsByShotId = soundTagsByShotId.filter { allowed.contains($0.key) }
            selectedSoundBlueprintIdsByShotId = selectedSoundBlueprintIdsByShotId.filter { allowed.contains($0.key) }
        }
        .confirmationDialog("Delete this shot?", isPresented: Binding(
            get: { pendingDeleteShotId != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteShotId = nil
                }
            }
        )) {
            Button("Delete Shot", role: .destructive) {
                guard let shotId = pendingDeleteShotId else { return }
                onDeleteShot(shotId)
                pendingDeleteShotId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteShotId = nil
            }
        } message: {
            Text("This removes the shot and related render jobs from the project.")
        }
        .sheet(item: $selectedDiagnostics, onDismiss: {
            diagnosticsSheetShotId = nil
        }) { details in
            StatusDetailsSheet(details: details, onRefresh: {
                await onRefreshStatusDetails()
                await MainActor.run {
                    if let id = diagnosticsSheetShotId, let shot = shots.first(where: { $0.id == id }) {
                        selectedDiagnostics = statusPresentation(for: shot)
                    }
                }
            })
        }
    }
}

struct JobsPanel: View {
    let jobs: [Job]
    let shots: [Shot]
    let localFileRecordsByRemoteURL: [String: LocalFileRecord]
    let localThumbnailURLByShotId: [String: URL]
    let localThumbnailURLByJobId: [String: URL]
    let jobRequestStateById: [String: RenderRequestState]
    @Binding var jobKindDraft: String
    let onCreateJob: () -> Void
    let onRetryJob: (String) -> Void
    let onDeleteJob: (String) -> Void
    let showTooltips: Bool
    @Binding var isCollapsed: Bool
    let onRefreshStatusDetails: () async -> Void
    @Environment(\.editorMobileInspectorSheet) private var editorMobileInspectorSheet
    @AppStorage("cinefuse.editor.jobs.showCompleted") private var showCompletedJobs = false
    @State private var pendingDeleteJobId: String?
    @State private var selectedDiagnostics: ArtifactStatusPresentation?
    @State private var diagnosticsSheetJobId: String?

    private let completedJobStatuses: Set<String> = ["done", "ready", "completed", "success"]
    private let terminalJobStatusesForProgress: Set<String> = [
        "done", "ready", "completed", "success", "failed", "timedout", "timed_out"
    ]

    private var visibleJobs: [Job] {
        if showCompletedJobs {
            return jobs
        }
        return jobs.filter { job in
            !completedJobStatuses.contains(job.status.lowercased())
        }
    }

    /// Shot-generate audio/video artifacts often live on `Shot.clipUrl` while `Job.outputUrl` is empty; sync keys `localFileRecordsByRemoteURL` by the same URL as the shot sync path.
    private func artifactRemoteURL(for job: Job) -> String? {
        if let u = job.outputUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u
        }
        guard let shotId = job.shotId else { return nil }
        guard let shot = shots.first(where: { $0.id == shotId }) else { return nil }
        let c = shot.clipUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return c.isEmpty ? nil : c
    }

    private func statusPresentation(for job: Job) -> ArtifactStatusPresentation {
        let urlKey = artifactRemoteURL(for: job)
        let localRecord = urlKey.flatMap { localFileRecordsByRemoteURL[$0] }
        return artifactStatusPresentation(
            job: job,
            localRecord: localRecord,
            requestState: jobRequestStateById[job.id],
            remoteURLDisplay: urlKey
        )
    }

    var body: some View {
        SectionCard(
            title: "Jobs - Track render",
            isCollapsed: $isCollapsed
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
                        HStack(spacing: CinefuseTokens.Spacing.xs) {
                            Text("Completed")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            Toggle("", isOn: $showCompletedJobs)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .tooltip("Display completed jobs in the list", enabled: showTooltips)
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
                        HStack(spacing: CinefuseTokens.Spacing.xs) {
                            Text("Completed")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            Toggle("", isOn: $showCompletedJobs)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .tooltip("Display completed jobs in the list", enabled: showTooltips)
                    }
                }

                if visibleJobs.isEmpty {
                    EmptyStateCard(
                        title: showCompletedJobs ? "No jobs yet" : "No active jobs",
                        message: showCompletedJobs
                            ? "Jobs appear when you queue rendering, audio, stitch, or export tasks."
                            : "Completed jobs are hidden. Enable Show completed to review history."
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    let gridColumns = [
                        GridItem(.adaptive(minimum: 300, maximum: 420), spacing: CinefuseTokens.Spacing.s, alignment: .top)
                    ]
                    ScrollView {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                            ForEach(visibleJobs) { job in
                                let presentation = statusPresentation(for: job)
                                let backgroundThumbnailURL = localThumbnailURLByJobId[job.id]
                                    ?? job.shotId.flatMap { localThumbnailURLByShotId[$0] }
                                VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                        HStack(spacing: CinefuseTokens.Spacing.s) {
                                            GenerationStatusDot(status: presentation)
                                                .tooltip(presentation.summary, enabled: showTooltips)
                                                .onTapGesture {
                                                    diagnosticsSheetJobId = job.id
                                                    selectedDiagnostics = presentation
                                                }
                                            Text(job.kind.capitalized)
                                                .font(CinefuseTokens.Typography.body)
                                            if job.status.lowercased() != "ready" {
                                                StatusBadge(status: job.status)
                                                    .contextMenu {
                                                        Button("Copy Status") {
                                                            copyTextToClipboard(job.status)
                                                        }
                                                        Button("Copy Diagnostics") {
                                                            copyTextToClipboard(presentation.details)
                                                        }
                                                    }
                                            }
                                            Spacer()
                                            Text("Cost to us: \(job.costToUsCents)c")
                                                .font(CinefuseTokens.Typography.caption)
                                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                        }
                                        if let prompt = job.promptText?.trimmingCharacters(in: .whitespacesAndNewlines),
                                           !prompt.isEmpty {
                                            Text(prompt)
                                                .font(CinefuseTokens.Typography.caption)
                                                .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
                                                .lineLimit(4)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                                .contextMenu {
                                                    Button("Copy prompt") {
                                                        copyTextToClipboard(prompt)
                                                    }
                                                }
                                        }
                                        if !terminalJobStatusesForProgress.contains(job.status.lowercased()) {
                                            GenerationActivityProgressRow(
                                                determinatePercent: job.progressPct.map {
                                                    max(0, min(100, $0))
                                                },
                                                waitingLabel: "Working…",
                                                determinateLabel: { "\($0)%" }
                                            )
                                        }
                                    }
                                    .cinefuseReadableOnMediaBackground()
                                    HStack(spacing: CinefuseTokens.Spacing.xs) {
                                        Button {
                                            onRetryJob(job.id)
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        .buttonStyle(SecondaryActionButtonStyle())
                                        .tooltip("Retry failed or restart queued job", enabled: showTooltips)
                                        .disabled(!(job.status == "failed" || job.status == "queued"))

                                        Button(role: .destructive) {
                                            pendingDeleteJobId = job.id
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(DestructiveActionButtonStyle())
                                        .tooltip("Delete job", enabled: showTooltips)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(CinefuseTokens.Spacing.s)
                                .background(
                                    MediaCardBackground(imageURL: backgroundThumbnailURL)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(CinefuseTokens.Motion.standard, value: visibleJobs.map(\.id))
                    }
                    .scrollDisabled(editorMobileInspectorSheet)
                    .frame(
                        maxHeight: editorMobileInspectorSheet ? nil : .infinity,
                        alignment: .top
                    )
                }
            }
        }
        .confirmationDialog("Delete this job?", isPresented: Binding(
            get: { pendingDeleteJobId != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteJobId = nil
                }
            }
        )) {
            Button("Delete Job", role: .destructive) {
                guard let jobId = pendingDeleteJobId else { return }
                onDeleteJob(jobId)
                pendingDeleteJobId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteJobId = nil
            }
        } message: {
            Text("This removes the job from the render track.")
        }
        .sheet(item: $selectedDiagnostics, onDismiss: {
            diagnosticsSheetJobId = nil
        }) { details in
            StatusDetailsSheet(details: details, onRefresh: {
                await onRefreshStatusDetails()
                await MainActor.run {
                    if let id = diagnosticsSheetJobId, let job = jobs.first(where: { $0.id == id }) {
                        selectedDiagnostics = statusPresentation(for: job)
                    }
                }
            })
        }
    }
}

/// Frosted plate behind labels so primary/caption text stays readable on thumbnail or video stills.
private struct ReadableVideoLabelBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(CinefuseTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle.opacity(0.45), lineWidth: 1)
                    )
            }
    }
}

private struct ConditionalReadableVideoLabelBackdrop: ViewModifier {
    let useFrostedPlate: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useFrostedPlate {
            content.modifier(ReadableVideoLabelBackdrop())
        } else {
            content
        }
    }
}

private extension View {
    func cinefuseReadableOnMediaBackground() -> some View {
        modifier(ReadableVideoLabelBackdrop())
    }
}

private struct MediaCardBackground: View {
    let imageURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .overlay(
                                LinearGradient(
                                    colors: [.black.opacity(0.48), .black.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
            }
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium))
    }
}

struct ArtifactStatusPresentation: Identifiable {
    enum Level {
        case success
        case warning
        case error
    }

    let id = UUID()
    let level: Level
    let summary: String
    let details: String
}

struct RenderRequestState {
    enum Stage: String {
        case requestSent
        case responseReceived
        case waiting
        case running
        case done
        case failed
        case timedOut

        var isTimeoutCandidate: Bool {
            switch self {
            case .requestSent, .responseReceived, .waiting, .running:
                return true
            case .done, .failed, .timedOut:
                return false
            }
        }
    }

    var stage: Stage = .requestSent
    var requestSentAt: Date?
    var responseReceivedAt: Date?
    var lastEventAt: Date?
    var lastMeaningfulTransitionAt: Date?
    var lastKnownStatus: String?
    var errorMessage: String?
    var source: String?
}

private let pipelineJobInFlightStatuses: Set<String> = ["queued", "generating", "running", "processing"]

private func parseJobUpdatedDate(_ job: Job) -> Date? {
    guard let value = job.updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return ISO8601DateFormatter().date(from: value)
}

private func providerPipelineNotStarted(job: Job) -> Bool {
    if job.kind == "audio" {
        let pe = (job.providerEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fe = (job.falEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rid = (job.requestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return pe.isEmpty && fe.isEmpty && (rid.isEmpty || rid == "n/a")
    }
    return (job.requestId == nil || job.requestId == "n/a")
        && (job.falEndpoint == nil || job.falEndpoint == "n/a")
        && (job.falStatusUrl == nil || job.falStatusUrl == "n/a")
}

private func featureErrorDebugLines(_ fe: JobFeatureError?) -> [String] {
    guard let fe else { return [] }
    var lines: [String] = []
    if let p = fe.provider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
        lines.append("Feature error — provider: \(p)")
    }
    if let r = fe.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
        lines.append("Feature error — reason: \(r)")
    }
    if let d = fe.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
        lines.append("Feature error — detail: \(d)")
    }
    return lines
}

/// Extra lines for status popup / copy-diagnostics when jobs are queued, stalled, or failed.
private func jobPipelineDebugLines(job: Job, shotStatus: String?) -> [String] {
    var lines: [String] = []
    let statusLower = job.status.lowercased()
    if let u = parseJobUpdatedDate(job) {
        let age = Int(Date().timeIntervalSince(u))
        lines.append("Job server clock: updated \(age)s ago (updatedAt)")
    } else {
        let shotReady = shotStatus?.lowercased() == "ready"
        let jobTerminal = statusLower == "done" || statusLower == "failed"
        if shotReady || jobTerminal {
            lines.append("Job server clock: updatedAt omitted in snapshot (common once generation finishes).")
        } else {
            lines.append("Job server clock: updatedAt missing")
        }
    }
    if let mid = job.modelId?.trimmingCharacters(in: .whitespacesAndNewlines), !mid.isEmpty {
        lines.append("Model id: \(mid)")
    }
    lines.append(contentsOf: featureErrorDebugLines(job.featureError))
    let stub = (job.providerAdapter == "stub") || ((job.providerEndpoint ?? "").hasPrefix("stub://"))
    if stub {
        lines.append("Hint: stub media mode — disable CINEFUSE_ALLOW_STUB_MEDIA for a real provider.")
    }
    let noProvider = providerPipelineNotStarted(job: job)
    if statusLower == "queued", noProvider {
        lines.append(
            "Queue: no provider endpoints yet — if this persists, run render-worker (Redis queue) or gateway without Redis for in-process dequeue."
        )
    }
    if pipelineJobInFlightStatuses.contains(statusLower), let u = parseJobUpdatedDate(job) {
        let age = Int(Date().timeIntervalSince(u))
        if age > 20 {
            lines.append(
                "Stall check: job status=\(job.status) but updatedAt is \(age)s old — verify SSE/polling, gateway, and worker logs."
            )
        }
    }
    if let ss = shotStatus?.lowercased(), ss == "queued", noProvider, statusLower == "queued" {
        lines.append("Shot and job both queued with no provider activity — upstream handoff may be blocked.")
    }
    return lines
}

/// Prefer gateway-reported job errors over locally inferred client copy (snapshot may set a generic shot failure string first).
private func primaryArtifactFailureMessage(
    job: Job?,
    requestState: RenderRequestState?,
    localRecord: LocalFileRecord?,
    fallback: String
) -> String {
    func trimmedNonEmpty(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
    return trimmedNonEmpty(job?.errorMessage)
        ?? trimmedNonEmpty(job?.featureError?.detail)
        ?? trimmedNonEmpty(job?.featureError?.reason)
        ?? trimmedNonEmpty(requestState?.errorMessage)
        ?? trimmedNonEmpty(localRecord?.errorMessage)
        ?? fallback
}

private func requestTimelineLines(_ requestState: RenderRequestState?, job: Job? = nil) -> [String] {
    guard let requestState else {
        return ["Request: unavailable"]
    }

    var lines = ["Request stage: \(requestState.stage.rawValue)"]
    if let sent = requestState.requestSentAt {
        lines.append("Time sent: \(sent.formatted(date: .abbreviated, time: .standard))")
    } else {
        lines.append("Time sent: unknown")
    }
    if let received = requestState.responseReceivedAt {
        lines.append("Response received: \(received.formatted(date: .abbreviated, time: .standard))")
    } else {
        lines.append("Response received: waiting")
    }
    if let lastEvent = requestState.lastEventAt {
        lines.append("Last event: \(lastEvent.formatted(date: .abbreviated, time: .standard))")
    } else {
        lines.append("Last event: none yet")
    }
    if let transition = requestState.lastMeaningfulTransitionAt {
        lines.append("Last lifecycle transition: \(transition.formatted(date: .abbreviated, time: .standard))")
    } else {
        lines.append("Last lifecycle transition: none yet")
    }

    if let sent = requestState.requestSentAt {
        let durationSeconds: Int
        if requestState.stage == .timedOut {
            durationSeconds = max(0, Int(Date().timeIntervalSince(sent)))
        } else if let terminal = requestState.lastMeaningfulTransitionAt, !requestState.stage.isTimeoutCandidate {
            durationSeconds = max(0, Int(terminal.timeIntervalSince(sent)))
        } else if let received = requestState.responseReceivedAt {
            durationSeconds = max(0, Int(received.timeIntervalSince(sent)))
        } else {
            durationSeconds = max(0, Int(Date().timeIntervalSince(sent)))
        }
        lines.append("Duration waiting: \(durationSeconds)s")
    } else {
        lines.append("Duration waiting: unknown")
    }
    if let status = requestState.lastKnownStatus {
        lines.append("API status: \(status)")
    } else {
        lines.append("API status: unknown")
    }
    if let source = requestState.source {
        lines.append("Lifecycle source: \(source)")
    }
    let trimmedJobErr = job?.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    let jobErr = (trimmedJobErr?.isEmpty == false) ? trimmedJobErr : nil
    let trimmedReqErr = requestState.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    let reqErr = (trimmedReqErr?.isEmpty == false) ? trimmedReqErr : nil
    if let error = jobErr ?? reqErr {
        let label = requestState.stage == .timedOut ? "Timeout reason" : "Request error"
        lines.append("\(label): \(error)")
    }
    return lines
}

private func copyTextToClipboard(_ value: String) {
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
#elseif canImport(UIKit)
    UIPasteboard.general.string = value
#endif
}

#if canImport(AVFoundation)
private func fileHeaderHexPrefix(path: String, maxBytes: Int) -> String? {
    guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? fh.close() }
    guard let data = try? fh.read(upToCount: maxBytes), !data.isEmpty else { return nil }
    return data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func mediaPlayableDurationSecondsIfAvailable(fileURL: URL) -> Double? {
    guard let player = try? AVAudioPlayer(contentsOf: fileURL) else { return nil }
    let d = player.duration
    return d > 0.05 ? d : nil
}

/// Lines for status sheets / copy diagnostics when debugging playback (extension vs bytes, duration, magic header).
private func playbackMediaFileDiagnosticLines(
    remoteURLString: String?,
    localPath: String?,
    artifactKind: String
) -> [String] {
    var lines: [String] = ["--- Artifact file (\(artifactKind)) ---"]
    if let raw = remoteURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
        if let u = URL(string: raw) {
            let ext = u.pathExtension.lowercased()
            lines.append("Remote path extension: \(ext.isEmpty ? "(none — API path may omit extension)" : ext)")
            lines.append("Remote last path component: \(u.lastPathComponent)")
            if !ext.isEmpty, let ut = UTType(filenameExtension: ext) {
                lines.append("Remote UTType (from path extension): \(ut.identifier)")
            }
        } else {
            lines.append("Remote URL: not parseable as URL")
        }
    }
    guard let lp = localPath?.trimmingCharacters(in: .whitespacesAndNewlines), !lp.isEmpty else {
        lines.append("Local file: not on disk yet (sync pending or failed)")
        return lines
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: lp, isDirectory: &isDir), !isDir.boolValue else {
        lines.append("Local path: missing or not a file")
        return lines
    }
    let fileURL = URL(fileURLWithPath: lp)
    let localExt = fileURL.pathExtension.lowercased()
    lines.append("Local file name: \(fileURL.lastPathComponent)")
    lines.append("Local extension: \(localExt.isEmpty ? "(none)" : localExt)")
    if !localExt.isEmpty {
        if let ut = UTType(filenameExtension: localExt) {
            lines.append("Local UTType (from extension): \(ut.identifier)")
        }
    }
    if let attrs = try? FileManager.default.attributesOfItem(atPath: lp) {
        if let size = attrs[.size] as? Int64 {
            let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            lines.append("Local size: \(formatted) (\(size) bytes)")
        }
        if let mod = attrs[.modificationDate] as? Date {
            lines.append("Local modified: \(mod.formatted(date: .abbreviated, time: .shortened))")
        }
    }
    if let hex = fileHeaderHexPrefix(path: lp, maxBytes: 12) {
        lines.append("Local header (hex, first bytes): \(hex)")
        if hex.hasPrefix("49 44 33") {
            lines.append("Header hint: ID3 — typical of MP3")
        }
        if hex.count >= 8 {
            let parts = hex.split(separator: " ")
            if parts.count >= 2, parts[0] == "FF", parts[1].hasPrefix("F") || parts[1].hasPrefix("E") || parts[1].hasPrefix("FB") {
                lines.append("Header hint: MPEG audio sync — likely MP3 frame")
            }
        }
        if hex.contains("66 74 79 70") {
            lines.append("Header hint: ftyp — ISO base media (often MP4/M4A); audio-only MP4 is common")
        }
    }
    if let dur = mediaPlayableDurationSecondsIfAvailable(fileURL: fileURL) {
        lines.append(String(format: "Playable duration (AVFoundation): %.2f s", dur))
    } else {
        lines.append("Playable duration: unavailable (wrong extension vs bytes, corrupt file, or unsupported format)")
    }
    return lines
}
#else
private func playbackMediaFileDiagnosticLines(
    remoteURLString: String?,
    localPath: String?,
    artifactKind: String
) -> [String] {
    ["--- Artifact file (\(artifactKind)) ---", "Build without AVFoundation — file details omitted"]
}
#endif

private func artifactStatusPresentation(
    job: Job,
    localRecord: LocalFileRecord?,
    requestState: RenderRequestState?,
    remoteURLDisplay: String? = nil
) -> ArtifactStatusPresentation {
    func displayValue(_ value: String?, missing: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return missing
        }
        return trimmed
    }
    func displayCode(_ value: Int?, missing: String) -> String {
        guard let value else { return missing }
        return String(value)
    }

    let remoteURLForDetails = remoteURLDisplay ?? job.outputUrl
    let requestLines = requestTimelineLines(requestState, job: job)
    if job.skippedFeature == true {
        let reason = job.featureError?.detail
            ?? job.featureError?.reason
            ?? "Feature skipped by provider adapter."
        let detailLines = [
            "Job: \(job.kind) / \(job.status)",
            "Provider adapter: \(displayValue(job.providerAdapter ?? job.featureError?.provider, missing: "not reported"))",
            "Feature status: skipped (workflow continues)",
            "Reason: \(reason)",
            "Output file created: \(job.outputCreated == true ? "yes" : (job.outputCreated == false ? "no" : "unknown"))",
            "Remote URL: \(displayValue(remoteURLForDetails, missing: "not produced"))",
            "Local file: \(displayValue(localRecord?.localPath, missing: "not applicable"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: remoteURLForDetails,
            localPath: localRecord?.localPath,
            artifactKind: job.kind
        ) + jobPipelineDebugLines(job: job, shotStatus: nil) + requestLines
        return ArtifactStatusPresentation(
            level: .warning,
            summary: "Audio feature skipped (non-blocking)",
            details: detailLines.joined(separator: "\n")
        )
    }
    let apiEvidence = [
        "Job ID: \(job.id)",
        "Updated at: \(displayValue(job.updatedAt, missing: "unknown"))",
        "Request ID: \(displayValue(job.requestId, missing: "not provided by provider"))",
        "Idempotency key: \(displayValue(job.idempotencyKey, missing: "not set"))",
        "Invoke state: \(displayValue(job.invokeState, missing: "not reported"))",
        "Provider adapter: \(displayValue(job.providerAdapter, missing: "not reported"))",
        "Provider endpoint: \(displayValue(job.providerEndpoint ?? job.falEndpoint, missing: "provider not started yet"))",
        "Provider status URL: \(displayValue(job.falStatusUrl, missing: "not available"))",
        "Provider status code: \(displayCode(job.providerStatusCode, missing: "not available"))",
        "Output file created: \(job.outputCreated == true ? "yes" : (job.outputCreated == false ? "no" : "unknown"))",
        "Provider response: \(displayValue(job.providerResponseSnippet, missing: "no provider response captured"))"
    ]
    let jobInvokeDone = (job.invokeState ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() == "done"
    if (requestState?.stage == .timedOut || requestState?.stage == .failed),
       job.status != "done", !jobInvokeDone {
        let details = [
            "Job: \(job.kind) / \(job.status)",
            "Model: \(job.modelId ?? "unknown")",
            "Prompt: \(displayValue(job.promptText, missing: "not captured"))",
            "Remote URL: \(displayValue(remoteURLForDetails, missing: "not produced"))",
            "Local file: \(displayValue(localRecord?.localPath, missing: "not available"))",
            "Error: \(primaryArtifactFailureMessage(job: job, requestState: requestState, localRecord: localRecord, fallback: "request timed out or failed"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: remoteURLForDetails,
            localPath: localRecord?.localPath,
            artifactKind: job.kind
        ) + apiEvidence + jobPipelineDebugLines(job: job, shotStatus: nil) + requestLines
        return ArtifactStatusPresentation(
            level: .error,
            summary: "Request timed out or failed",
            details: details.joined(separator: "\n")
        )
    }
    if job.status == "failed" || localRecord?.status == .downloadFailed || localRecord?.status == .writeFailed {
        let details = [
            "Job: \(job.kind) / \(job.status)",
            "Model: \(job.modelId ?? "unknown")",
            "Prompt: \(displayValue(job.promptText, missing: "not captured"))",
            "Remote URL: \(displayValue(remoteURLForDetails, missing: "not produced"))",
            "Local file: \(displayValue(localRecord?.localPath, missing: "not available"))",
            "Error: \(primaryArtifactFailureMessage(job: job, requestState: requestState, localRecord: localRecord, fallback: "unknown"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: remoteURLForDetails,
            localPath: localRecord?.localPath,
            artifactKind: job.kind
        ) + apiEvidence + jobPipelineDebugLines(job: job, shotStatus: nil) + requestLines
        let detailText = details.joined(separator: "\n")
        return ArtifactStatusPresentation(
            level: .error,
            summary: "File generation failed or file sync error",
            details: detailText
        )
    }

    if localRecord?.status == .synced || localRecord?.status == .alreadyPresent {
        let details = [
            "Job: \(job.kind) / \(job.status)",
            "Model: \(job.modelId ?? "unknown")",
            "Prompt: \(displayValue(job.promptText, missing: "not captured"))",
            "Remote URL: \(displayValue(remoteURLForDetails, missing: "not produced"))",
            "Local file: \(displayValue(localRecord?.localPath, missing: "not available"))",
            "File sync: \(displayValue(localRecord?.status.rawValue, missing: "unknown"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: remoteURLForDetails,
            localPath: localRecord?.localPath,
            artifactKind: job.kind
        ) + apiEvidence + requestLines
        let detailText = details.joined(separator: "\n")
        return ArtifactStatusPresentation(
            level: .success,
            summary: "Local file created in Documents/Cinefuse Generated",
            details: detailText
        )
    }

    let waitingDetails = [
        "Job: \(job.kind) / \(job.status)",
        "Progress: \(job.progressPct.map { "\($0)%" } ?? "unknown")",
        "Prompt: \(displayValue(job.promptText, missing: "not captured"))",
        "Remote URL: \(displayValue(remoteURLForDetails, missing: "pending"))",
        "Local file: pending"
    ] + playbackMediaFileDiagnosticLines(
        remoteURLString: remoteURLForDetails,
        localPath: localRecord?.localPath,
        artifactKind: job.kind
    ) + apiEvidence + jobPipelineDebugLines(job: job, shotStatus: nil) + requestLines
    let waitingSummary: String
    if requestState?.stage == .responseReceived {
        waitingSummary = "API called and accepted; waiting for worker updates"
    } else if requestState?.stage == .running {
        waitingSummary = "Render running; waiting for completion"
    } else {
        waitingSummary = "Generation or local file sync is still in progress"
    }
    let waitingDetailText = waitingDetails.joined(separator: "\n")
    if let error = requestState?.errorMessage,
       error.localizedCaseInsensitiveContains("already in progress") {
        return ArtifactStatusPresentation(
            level: .warning,
            summary: "Shot already generating; wait for current render",
            details: waitingDetailText
        )
    }
    return ArtifactStatusPresentation(
        level: .warning,
        summary: waitingSummary,
        details: waitingDetailText
    )
}

private func shotArtifactStatusPresentation(
    shot: Shot,
    job: Job?,
    localRecord: LocalFileRecord?,
    requestState: RenderRequestState?
) -> ArtifactStatusPresentation {
    func displayValue(_ value: String?, missing: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return missing
        }
        return trimmed
    }
    func displayCode(_ value: Int?, missing: String) -> String {
        guard let value else { return missing }
        return String(value)
    }

    let requestLines = requestTimelineLines(requestState, job: job)
    let artifactNoun = job?.kind == "audio" ? "Sound" : "Shot"
    let artifactKindTag = job?.kind ?? (artifactNoun == "Sound" ? "audio" : "clip")
    let isStubFailure = (job?.providerAdapter == "stub")
        || ((job?.providerEndpoint ?? "").hasPrefix("stub://"))
    let stubGuidance = isStubFailure
        ? "Stub media mode is active in runtime. Disable CINEFUSE_ALLOW_STUB_MEDIA and restart app/gateway."
        : nil
    if let retryConflict = requestState?.errorMessage,
       retryConflict.localizedCaseInsensitiveContains("retry is only for failed shots") {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Request ID: \(job?.requestId ?? "n/a")",
            "Idempotency key: \(job?.idempotencyKey ?? "n/a")",
            "Error: \(retryConflict)"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + requestLines
        return ArtifactStatusPresentation(
            level: .warning,
            summary: "Retry skipped because backend status changed",
            details: details.joined(separator: "\n")
        )
    }
    let shotJobInvokeDone = (job?.invokeState ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() == "done"
    let shotJobCompleted = job?.status == "done" || shotJobInvokeDone || shot.status == "ready"
    if (requestState?.stage == .timedOut || requestState?.stage == .failed), !shotJobCompleted {
        let providerNeverReached: Bool
        if job?.kind == "audio" {
            let pe = (job?.providerEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fe = (job?.falEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rid = (job?.requestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            providerNeverReached = pe.isEmpty && fe.isEmpty && (rid.isEmpty || rid == "n/a")
        } else {
            providerNeverReached = (job?.requestId == nil || job?.requestId == "n/a")
                && (job?.falEndpoint == nil || job?.falEndpoint == "n/a")
                && (job?.falStatusUrl == nil || job?.falStatusUrl == "n/a")
        }
        let queueStuckHint: [String] =
            requestState?.stage == .timedOut && !isStubFailure && shot.status == "queued" && providerNeverReached
            ? [
                "Hint: Timed out while still queued with no provider activity. If the gateway uses Redis for the render queue, start render-worker or unset Redis so the gateway processes jobs in-process."
            ]
            : []
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Job ID: \(displayValue(job?.id, missing: "unknown"))",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Invoke state: \(displayValue(job?.invokeState, missing: "not reported"))",
            "Output file created: \(job?.outputCreated == true ? "yes" : (job?.outputCreated == false ? "no" : "unknown"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "provider not started yet"))",
            "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
            "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))",
            "Error: \(primaryArtifactFailureMessage(job: job, requestState: requestState, localRecord: localRecord, fallback: "request timed out or failed"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + (stubGuidance.map { ["Hint: \($0)"] } ?? []) + queueStuckHint
            + (job.map { jobPipelineDebugLines(job: $0, shotStatus: shot.status) } ?? []) + requestLines
        return ArtifactStatusPresentation(
            level: .error,
            summary: "\(artifactNoun) request timed out or failed",
            details: details.joined(separator: "\n")
        )
    }
    if shot.status == "failed" {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Job ID: \(displayValue(job?.id, missing: "unknown"))",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Invoke state: \(displayValue(job?.invokeState, missing: "not reported"))",
            "Output file created: \(job?.outputCreated == true ? "yes" : (job?.outputCreated == false ? "no" : "unknown"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "provider not started yet"))",
            "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
            "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))",
            "Error: \(primaryArtifactFailureMessage(job: job, requestState: requestState, localRecord: localRecord, fallback: "unknown"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + (stubGuidance.map { ["Hint: \($0)"] } ?? [])
            + (job.map { jobPipelineDebugLines(job: $0, shotStatus: shot.status) } ?? []) + requestLines
        return ArtifactStatusPresentation(level: .error, summary: "\(artifactNoun) generation failed", details: details.joined(separator: "\n"))
    }

    if localRecord?.status == .synced || localRecord?.status == .alreadyPresent {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Remote URL: \(displayValue(shot.clipUrl, missing: "not produced"))",
            "Local file: \(displayValue(localRecord?.localPath, missing: "not available"))",
            "Model: \(job?.modelId ?? "unknown")",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "provider not started yet"))",
            "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
            "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + requestLines
        return ArtifactStatusPresentation(level: .success, summary: "\(artifactNoun) file is available locally", details: details.joined(separator: "\n"))
    }

    if localRecord?.status == .downloadFailed || localRecord?.status == .writeFailed {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Remote URL: \(displayValue(shot.clipUrl, missing: "not produced"))",
            "Local file: unavailable",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "provider not started yet"))",
            "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
            "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))",
            "Error: \(localRecord?.errorMessage ?? "file sync failed")"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + requestLines
        return ArtifactStatusPresentation(level: .error, summary: "\(artifactNoun) rendered but local file sync failed", details: details.joined(separator: "\n"))
    }

    /// Shot is ready on the server but local file row may still be syncing — do not fall through to "still in progress".
    if shot.status.lowercased() == "ready" {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Progress: \(job?.progressPct.map { "\($0)%" } ?? "100%")",
            "Remote URL: \(displayValue(shot.clipUrl, missing: "not linked yet"))",
            "Local file: \(localRecord.flatMap { displayValue($0.localPath, missing: $0.status.rawValue) } ?? "syncing or pending")",
            "Job ID: \(displayValue(job?.id, missing: "unknown"))",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "not reported"))",
            "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
            "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + (job.map { jobPipelineDebugLines(job: $0, shotStatus: shot.status) } ?? []) + requestLines
        return ArtifactStatusPresentation(
            level: .success,
            summary: "\(artifactNoun) is ready",
            details: details.joined(separator: "\n")
        )
    }

    if shotJobCompleted, shot.status != "ready", shot.status != "failed" {
        let details = [
            "\(artifactNoun): \(shot.id)",
            "Status: \(shot.status) (timeline row may lag after job completes)",
            "Prompt: \(shot.prompt)",
            "Model tier: \(shot.modelTier)",
            "Job: \(job?.status ?? "unknown") / invoke: \(displayValue(job?.invokeState, missing: "unknown"))",
            "Remote URL: \(displayValue(shot.clipUrl, missing: "not produced"))",
            "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
            "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
            "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
            "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "unknown"))"
        ] + playbackMediaFileDiagnosticLines(
            remoteURLString: shot.clipUrl,
            localPath: localRecord?.localPath,
            artifactKind: artifactKindTag
        ) + requestLines
        return ArtifactStatusPresentation(
            level: .warning,
            summary: "\(artifactNoun) finished on server — refreshing timeline",
            details: details.joined(separator: "\n")
        )
    }

    let details = [
        "\(artifactNoun): \(shot.id)",
        "Status: \(shot.status)",
        "Prompt: \(shot.prompt)",
        "Model tier: \(shot.modelTier)",
        "Progress: \(job?.progressPct.map { "\($0)%" } ?? "unknown")",
        "Request ID: \(displayValue(job?.requestId, missing: "not provided by provider"))",
        "Idempotency key: \(displayValue(job?.idempotencyKey, missing: "not set"))",
        "Provider adapter: \(displayValue(job?.providerAdapter, missing: "not reported"))",
        "Provider endpoint: \(displayValue(job?.providerEndpoint ?? job?.falEndpoint, missing: "provider not started yet"))",
        "Provider status URL: \(displayValue(job?.falStatusUrl, missing: "not available"))",
        "Provider status code: \(displayCode(job?.providerStatusCode, missing: "not available"))"
    ] + playbackMediaFileDiagnosticLines(
        remoteURLString: shot.clipUrl,
        localPath: localRecord?.localPath,
        artifactKind: artifactKindTag
    ) + (job.map { jobPipelineDebugLines(job: $0, shotStatus: shot.status) } ?? []) + requestLines
    let providerNotStarted: Bool
    if job?.kind == "audio" {
        let pe = (job?.providerEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fe = (job?.falEndpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rid = (job?.requestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        providerNotStarted = pe.isEmpty && fe.isEmpty && (rid.isEmpty || rid == "n/a")
    } else {
        providerNotStarted = (job?.requestId == nil || job?.requestId == "n/a")
            && (job?.falEndpoint == nil || job?.falEndpoint == "n/a")
            && (job?.falStatusUrl == nil || job?.falStatusUrl == "n/a")
    }
    let queuedTooLongLikely = shot.status == "queued" && providerNotStarted
    let summary = requestState?.stage == .responseReceived
        ? "\(artifactNoun) API call accepted; waiting for worker"
        : queuedTooLongLikely
        ? "Queued: worker backlog/offline likely"
        : "\(artifactNoun) generation still in progress"
    let queuedGuidance = queuedTooLongLikely
        ? [
            job?.kind == "audio"
                ? "Provider call has not started yet. If Redis backs the render queue, start render-worker or run the gateway without Redis for in-process processing."
                : "Provider call has not started yet; render-worker may be delayed or offline."
        ]
        : []
    return ArtifactStatusPresentation(
        level: .warning,
        summary: summary,
        details: (details + queuedGuidance).joined(separator: "\n")
    )
}

struct GenerationStatusDot: View {
    let status: ArtifactStatusPresentation

    private var color: Color {
        switch status.level {
        case .success:
            return .green
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
            )
    }
}

struct StatusDetailsSheet: View {
    let details: ArtifactStatusPresentation
    let onRefresh: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(details: ArtifactStatusPresentation, onRefresh: (() async -> Void)? = nil) {
        self.details = details
        self.onRefresh = onRefresh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            HStack {
                Text(details.summary)
                    .font(CinefuseTokens.Typography.sectionTitle)
                Spacer()
                if let onRefresh {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .help("Refresh status from server")
                }
                Button("Copy Diagnostics") {
                    copyTextToClipboard(details.details)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
            ScrollView {
                Text(details.details)
                    .font(CinefuseTokens.Typography.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(CinefuseTokens.Spacing.m)
        .frame(minWidth: 520, minHeight: 320)
        .onAppear {
            DiagnosticsLogger.renderPipelineSheet(summary: details.summary, details: details.details)
        }
    }
}

struct DebugGenerationWindow: View {
    let logLines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            HStack {
                Text("Debug Generation Window")
                    .font(CinefuseTokens.Typography.sectionTitle)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            if logLines.isEmpty {
                EmptyStateCard(
                    title: "No diagnostics captured yet",
                    message: "Generate a shot or export to see prompts, statuses, and file-sync events."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(CinefuseTokens.Typography.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(CinefuseTokens.Spacing.m)
        .frame(minWidth: 680, minHeight: 420)
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
                            let presentation = ArtifactStatusPresentation(
                                level: shot.status == "ready" ? .success : (shot.status == "failed" ? .error : .warning),
                                summary: shot.status.capitalized,
                                details: "Timeline shot status: \(shot.status)"
                            )
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
                                HStack {
                                    GenerationStatusDot(status: presentation)
                                    Text(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                        .font(CinefuseTokens.Typography.body)
                                        .textSelection(.enabled)
                                        .contextMenu {
                                            Button("Copy prompt") {
                                                copyTextToClipboard(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                            }
                                        }
                                    Spacer()
                                    if shot.status.lowercased() != "ready" {
                                        StatusBadge(status: shot.status)
                                    }
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
                    themePalette: themeMode.palette,
                    laneVolumes: .constant([:]),
                    masterVolume: .constant(1)
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

    private var previewURL: URL? {
        if let thumb = shot.thumbnailUrl, let thumbURL = URL(string: thumb) {
            return thumbURL
        }
        if let clip = shot.clipUrl, let clipURL = URL(string: clip) {
            return clipURL
        }
        return nil
    }

    var body: some View {
        HStack(spacing: CinefuseTokens.Spacing.s) {
            if let previewURL {
                AsyncImage(url: previewURL) { phase in
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
    @Binding var laneVolumes: [Int: Float]
    @Binding var masterVolume: Float

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
                        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                            Text("Lane vol")
                                .font(CinefuseTokens.Typography.micro)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                            Slider(
                                value: Binding(
                                    get: { Double(laneVolumes[track.laneIndex] ?? 1) },
                                    set: { laneVolumes[track.laneIndex] = Float($0) }
                                ),
                                in: 0...1.5
                            )
                            .frame(width: 120)
                        }
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
                        if track.status.lowercased() != "ready" {
                            StatusBadge(status: track.status)
                        }
                    }
                    .padding(CinefuseTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                            .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(laneMode == .locked ? 0.92 : 0.76))
                    )
                }
            }
            if !audioTracks.isEmpty {
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    Text("Master")
                        .font(CinefuseTokens.Typography.caption)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    Slider(value: Binding(
                        get: { Double(masterVolume) },
                        set: { masterVolume = Float($0) }
                    ), in: 0...1.5)
                    .frame(maxWidth: 280)
                    Text("\(Int(masterVolume * 100))%")
                        .font(CinefuseTokens.Typography.micro)
                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                }
                .padding(.top, CinefuseTokens.Spacing.xs)
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
