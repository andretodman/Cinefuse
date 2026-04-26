import SwiftUI
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

public struct CinefuseRootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        if model.isAuthenticated {
            ProjectGalleryView()
        } else {
            LoginView()
        }
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var draftUserId = "demo-user"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cinefuse")
                .font(.largeTitle.bold())

            Text("Sign in with your Pubfuse identity (M0 stub token flow).")
                .foregroundStyle(.secondary)

            TextField("User ID", text: $draftUserId)
                .textFieldStyle(.roundedBorder)

            Button("Sign in") {
                model.userId = draftUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                model.isAuthenticated = !model.userId.isEmpty
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct ProjectGalleryView: View {
    @Environment(AppModel.self) private var model
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
    private let api = APIClient()

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return model.projects.first(where: { $0.id == selectedProjectId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project gallery")
                    .font(.title2.bold())
                Spacer()
                Button("New project") {
                    openCreateProjectSheet()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: [.command])
                Text("Sparks: \(model.balance)")
                    .font(.headline)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            NavigationSplitView {
                List(selection: $selectedProjectId) {
                    ForEach(model.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                                .font(.headline)
                            Text("Phase: \(project.currentPhase) • Tone: \(project.tone)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(project.id)
                    }
                }
            } detail: {
                if let selectedProject {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(selectedProject.title)
                                .font(.title3.bold())
                            Spacer()
                            Button("Close project") {
                                closeProject()
                            }
                            .buttonStyle(.bordered)
                            Button("Delete project", role: .destructive) {
                                Task { await deleteSelectedProject() }
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Project ID: \(selectedProject.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isLoadingProjectDetails {
                            ProgressView("Loading shots and jobs...")
                                .controlSize(.small)
                        }

                        GroupBox("Shots") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TextField("Shot prompt", text: $shotPromptDraft)
                                        .textFieldStyle(.roundedBorder)
                                    Picker("Tier", selection: $shotModelTierDraft) {
                                        Text("budget").tag("budget")
                                        Text("standard").tag("standard")
                                        Text("premium").tag("premium")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 120)
                                    Button("Quote") {
                                        Task { await quoteShot() }
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Create shot") {
                                        Task { await createShot() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                if let quotedShotCost {
                                    let durationText = quotedShotCost.estimatedDurationSec.map { "~\($0)s" } ?? "~5s"
                                    Text("This shot will cost \(quotedShotCost.sparksCost) Sparks (\(quotedShotCost.modelId), \(durationText))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if shots.isEmpty {
                                    Text("No shots yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(shots) { shot in
                                        HStack {
                                            Text("• \(shot.modelTier) • \(shot.status) • \(shot.prompt)")
                                                .font(.caption)
                                            Spacer()
                                            Button("Generate clip") {
                                                Task { await generateShot(shotId: shot.id) }
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(shot.status == "ready")
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Jobs") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Picker("Kind", selection: $jobKindDraft) {
                                        Text("clip").tag("clip")
                                        Text("audio").tag("audio")
                                        Text("stitch").tag("stitch")
                                        Text("export").tag("export")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 140)

                                    Button("Create job") {
                                        Task { await createJob() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                if jobs.isEmpty {
                                    Text("No jobs yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(jobs) { job in
                                        Text("• \(job.kind) • \(job.status) • cost: \(job.costToUsCents)c")
                                            .font(.caption)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer()
                    }
                    .padding(.top, 8)
                } else {
                    ContentUnavailableView(
                        "Select a Project",
                        systemImage: "film.stack",
                        description: Text("Create a project or pick one from the list to continue.")
                    )
                }
            }
            .onChange(of: selectedProjectId) { _, _ in
                Task { await loadSelectedProjectDetails() }
            }
        }
        .padding(24)
        .sheet(isPresented: $isCreateProjectSheetPresented) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New project")
                    .font(.title3.bold())
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
                    Button("Create project") {
                        Task { await createProject() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
            .onAppear {
                forceAppFocusForTextEntry()
            }
            .task {
                titleDraft = ""
                forceFieldFocusSoon()
            }
        }
        .onChange(of: isCreateProjectSheetPresented) { _, isPresented in
            if isPresented {
                forceAppFocusForTextEntry()
                forceFieldFocusSoon()
            }
        }
        .task {
            await refresh(selectProjectId: selectedProjectId)
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
            await loadSelectedProjectDetails()
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

    private func loadSelectedProjectDetails() async {
        guard let selectedProjectId else {
            shots = []
            jobs = []
            return
        }
        isLoadingProjectDetails = true
        defer { isLoadingProjectDetails = false }
        do {
            async let projectShots = api.listShots(token: model.bearerToken, projectId: selectedProjectId)
            async let projectJobs = api.listJobs(token: model.bearerToken, projectId: selectedProjectId)
            shots = try await projectShots
            jobs = try await projectJobs
            model.errorMessage = nil
        } catch {
            model.errorMessage = error.localizedDescription
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
            await loadSelectedProjectDetails()
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
            await refresh(selectProjectId: selectedProjectId)
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
            await loadSelectedProjectDetails()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
