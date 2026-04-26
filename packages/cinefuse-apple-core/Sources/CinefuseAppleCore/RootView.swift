import SwiftUI
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

struct LoginScreen: View {
    @Environment(AppModel.self) private var model
    @State private var draftUserId = "demo-user"

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
            Text("Welcome to Cinefuse")
                .font(CinefuseTokens.Typography.screenTitle)

            Text("Sign in with your Pubfuse user ID to create projects, quote shot costs, and generate clips.")
                .font(CinefuseTokens.Typography.body)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)

            TextField("User ID", text: $draftUserId)
                .textFieldStyle(.roundedBorder)

            Button("Continue") {
                model.userId = draftUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                model.isAuthenticated = !model.userId.isEmpty
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(CinefuseTokens.Spacing.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
    @State private var timelineThemeMode: TimelineThemeMode = .system
    @State private var jobKindDraft = "clip"
    @State private var isLoadingProjectDetails = false
    @State private var isRefreshingProjectDetails = false
    @State private var hasLiveEventsConnection = false

    private let api = APIClient()
    private let inFlightStatuses: Set<String> = ["queued", "generating", "running"]

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return model.projects.first(where: { $0.id == selectedProjectId })
    }

    private var hasInFlightWork: Bool {
        shots.contains(where: { inFlightStatuses.contains($0.status) })
            || jobs.contains(where: { inFlightStatuses.contains($0.status) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
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
                    timelineThemeMode: $timelineThemeMode,
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
                    onExportFinal: { Task { await exportFinalTimeline() } }
                )
            }
            .onChange(of: selectedProjectId) { _, _ in
                Task { await loadSelectedProjectDetails(showLoadingIndicator: true) }
            }
        }
        .padding(CinefuseTokens.Spacing.l)
        .sheet(isPresented: $isCreateProjectSheetPresented) {
            createProjectSheet
        }
        .task {
            await refresh(selectProjectId: selectedProjectId)
        }
        .preferredColorScheme(timelineThemeMode.colorScheme)
        .task(id: selectedProjectId) {
            await monitorInFlightJobs()
        }
        .task(id: selectedProjectId) {
            await observeProjectEvents()
        }
    }

    private var header: some View {
        HStack(spacing: CinefuseTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text("Project Gallery")
                    .font(CinefuseTokens.Typography.screenTitle)
                Text("Pick a project to draft shots, quote costs, and generate clips.")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            Spacer()
            PubfuseLogoBadge()
            Button("New Project") {
                openCreateProjectSheet()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .keyboardShortcut("n", modifiers: [.command])
            Text("Sparks: \(model.balance)")
                .font(CinefuseTokens.Typography.label)
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

    private func exportFinalTimeline() async {
        guard let selectedProjectId else { return }
        do {
            _ = try await api.exportFinal(token: model.bearerToken, projectId: selectedProjectId)
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
    let onExportFinal: () -> Void

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.m) {
                        header(project: project)
                        if isLoadingProjectDetails {
                            ProgressView("Refreshing shot and job status...")
                                .font(CinefuseTokens.Typography.caption)
                        }
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
                            onTrainCharacter: onTrainCharacter
                        )
                        ShotsPanel(
                            shots: shots,
                            characterOptions: characters,
                            shotPromptDraft: $shotPromptDraft,
                            shotModelTierDraft: $shotModelTierDraft,
                            selectedCharacterLockId: $selectedCharacterLockId,
                            quotedShotCost: quotedShotCost,
                            onQuote: onQuote,
                            onCreateShot: onCreateShot,
                            onGenerateShot: onGenerateShot
                        )
                        TimelinePanel(
                            shots: shots,
                            audioTracks: audioTracks,
                            audioTrackTitleDraft: $audioTrackTitleDraft,
                            themeMode: $timelineThemeMode,
                            onMoveShot: onReorderShots,
                            onGenerateDialogue: onGenerateDialogue,
                            onGenerateScore: onGenerateScore,
                            onExport: onExportFinal
                        )
                        JobsPanel(
                            jobs: jobs,
                            jobKindDraft: $jobKindDraft,
                            onCreateJob: onCreateJob
                        )
                    }
                    .padding(.top, CinefuseTokens.Spacing.xs)
                }
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "film.stack",
                    description: Text("Choose a project from the sidebar or create one to get started.")
                )
            }
        }
    }

    private func header(project: Project) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                Text(project.title)
                    .font(CinefuseTokens.Typography.sectionTitle)
                Text("Project ID: \(project.id)")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            Spacer()
            Button("Close") { onCloseProject() }
                .buttonStyle(SecondaryActionButtonStyle())
            Button("Delete", role: .destructive) { onDeleteProject() }
                .buttonStyle(DestructiveActionButtonStyle())
        }
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
            subtitle: "Generate and revise scene beats before creating detailed shots."
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

    var body: some View {
        SectionCard(
            title: "Characters",
            subtitle: "Create hero or supporting characters, then train and lock them to shots."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    TextField("Character name", text: $newCharacterName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $newCharacterDescription)
                        .textFieldStyle(.roundedBorder)
                    Button("Add Character", action: onCreateCharacter)
                        .buttonStyle(PrimaryActionButtonStyle())
                }

                if characters.isEmpty {
                    EmptyStateCard(
                        title: "No characters created",
                        message: "Add a character and train it before locking to key shots."
                    )
                } else {
                    ForEach(characters) { character in
                        HStack {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                Text(character.name)
                                    .font(CinefuseTokens.Typography.cardTitle)
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
                            Spacer()
                            StatusBadge(status: character.status)
                            if character.status != "trained" {
                                Button("Train") {
                                    onTrainCharacter(character.id)
                                }
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

    private let inFlightStatuses: Set<String> = ["queued", "generating", "running"]

    var body: some View {
        SectionCard(
            title: "Shots",
            subtitle: "Step 1: Draft a shot. Step 2: Quote cost. Step 3: Generate clip. Step 4: Review output status."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                    TextField("Describe the shot action or camera movement", text: $shotPromptDraft)
                        .textFieldStyle(.roundedBorder)
                    Picker("Tier", selection: $shotModelTierDraft) {
                        Text("Budget").tag("budget")
                        Text("Standard").tag("standard")
                        Text("Premium").tag("premium")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    Picker("Character Lock", selection: $selectedCharacterLockId) {
                        Text("No lock").tag("")
                        ForEach(characterOptions) { character in
                            Text(character.name).tag(character.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                    Button("Quote Cost", action: onQuote)
                        .buttonStyle(SecondaryActionButtonStyle())
                    Button("Create Shot", action: onCreateShot)
                        .buttonStyle(PrimaryActionButtonStyle())
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
                        HStack(spacing: CinefuseTokens.Spacing.s) {
                            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
                                Text(shot.prompt.isEmpty ? "Untitled shot" : shot.prompt)
                                    .font(CinefuseTokens.Typography.body)
                                HStack(spacing: CinefuseTokens.Spacing.xs) {
                                    Text(shot.modelTier.capitalized)
                                        .font(CinefuseTokens.Typography.caption)
                                        .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                    StatusBadge(status: shot.status)
                                    if let lock = shot.characterLocks?.first, !lock.isEmpty {
                                        Text("Character lock")
                                            .font(CinefuseTokens.Typography.caption)
                                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                            .help(lock)
                                    }
                                    if let clipUrl = shot.clipUrl {
                                        Text("Output ready")
                                            .font(CinefuseTokens.Typography.caption)
                                            .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                                            .help(clipUrl)
                                    }
                                }
                            }
                            Spacer()
                            Button("Generate Clip") {
                                onGenerateShot(shot.id)
                            }
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
        }
    }
}

struct JobsPanel: View {
    let jobs: [Job]
    @Binding var jobKindDraft: String
    let onCreateJob: () -> Void

    var body: some View {
        SectionCard(
            title: "Jobs",
            subtitle: "Track render and processing work for this project."
        ) {
            VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
                HStack(spacing: CinefuseTokens.Spacing.s) {
                    Picker("Job type", selection: $jobKindDraft) {
                        Text("Clip").tag("clip")
                        Text("Audio").tag("audio")
                        Text("Stitch").tag("stitch")
                        Text("Export").tag("export")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    Button("Create Job", action: onCreateJob)
                        .buttonStyle(PrimaryActionButtonStyle())
                }

                if jobs.isEmpty {
                    EmptyStateCard(
                        title: "No jobs yet",
                        message: "Jobs appear when you queue rendering, audio, stitch, or export tasks."
                    )
                } else {
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
        }
    }
}

enum TimelineThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
                    .frame(width: 140)
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

                AudioLaneView(audioTracks: audioTracks)
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

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
            Text("Audio Lanes")
                .font(CinefuseTokens.Typography.cardTitle)
            if audioTracks.isEmpty {
                Text("No audio tracks generated yet.")
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            } else {
                ForEach(audioTracks) { track in
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
                            Text("Lane \(track.laneIndex + 1) • \(track.durationMs)ms")
                                .font(CinefuseTokens.Typography.caption)
                                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                        }
                        Spacer()
                        if let sourceUrl = track.sourceUrl, let url = URL(string: sourceUrl) {
                            Link("Play", destination: url)
                                .font(CinefuseTokens.Typography.caption)
                        }
                        StatusBadge(status: track.status)
                    }
                    .padding(CinefuseTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                            .fill(CinefuseTokens.ColorRole.surfaceSecondary)
                    )
                }
            }
        }
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
