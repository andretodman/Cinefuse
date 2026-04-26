import SwiftUI
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
    @State private var shots: [Shot] = []
    @State private var jobs: [Job] = []
    @State private var shotPromptDraft = "Establishing shot of the location"
    @State private var shotModelTierDraft = "standard"
    @State private var quotedShotCost: ShotQuote?
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
                    shots: shots,
                    jobs: jobs,
                    shotPromptDraft: $shotPromptDraft,
                    shotModelTierDraft: $shotModelTierDraft,
                    quotedShotCost: quotedShotCost,
                    jobKindDraft: $jobKindDraft,
                    onCloseProject: closeProject,
                    onDeleteProject: { Task { await deleteSelectedProject() } },
                    onQuote: { Task { await quoteShot() } },
                    onCreateShot: { Task { await createShot() } },
                    onGenerateShot: { shotId in Task { await generateShot(shotId: shotId) } },
                    onCreateJob: { Task { await createJob() } }
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
        quotedShotCost = nil
        shots = []
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
            shots = []
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
            async let projectShots = api.listShots(token: model.bearerToken, projectId: selectedProjectId)
            async let projectJobs = api.listJobs(token: model.bearerToken, projectId: selectedProjectId)
            let latestShots = try await projectShots
            let latestJobs = try await projectJobs
            var transaction = Transaction()
            if !showLoadingIndicator {
                transaction.animation = nil
            }
            withTransaction(transaction) {
                shots = latestShots
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
                modelTier: shotModelTierDraft
            )
            quotedShotCost = nil
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
    let shots: [Shot]
    let jobs: [Job]
    @Binding var shotPromptDraft: String
    @Binding var shotModelTierDraft: String
    let quotedShotCost: ShotQuote?
    @Binding var jobKindDraft: String

    let onCloseProject: () -> Void
    let onDeleteProject: () -> Void
    let onQuote: () -> Void
    let onCreateShot: () -> Void
    let onGenerateShot: (String) -> Void
    let onCreateJob: () -> Void

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
                        ShotsPanel(
                            shots: shots,
                            shotPromptDraft: $shotPromptDraft,
                            shotModelTierDraft: $shotModelTierDraft,
                            quotedShotCost: quotedShotCost,
                            onQuote: onQuote,
                            onCreateShot: onCreateShot,
                            onGenerateShot: onGenerateShot
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

struct ShotsPanel: View {
    let shots: [Shot]
    @Binding var shotPromptDraft: String
    @Binding var shotModelTierDraft: String
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
