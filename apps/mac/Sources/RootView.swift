import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
    @State private var titleDraft = "Untitled project"
    private let api = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project gallery")
                    .font(.title2.bold())
                Spacer()
                Text("Sparks: \(model.balance)")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                TextField("Project title", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)

                Button("Create project") {
                    Task { await createProject() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            List(model.projects) { project in
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.headline)
                    Text("Phase: \(project.currentPhase) • Tone: \(project.tone)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        model.isLoading = true
        model.errorMessage = nil

        do {
            async let projects = api.listProjects(token: model.bearerToken)
            async let balance = api.getBalance(token: model.bearerToken)
            model.projects = try await projects
            model.balance = try await balance
        } catch {
            model.errorMessage = error.localizedDescription
        }

        model.isLoading = false
    }

    private func createProject() async {
        model.errorMessage = nil
        do {
            _ = try await api.createProject(token: model.bearerToken, title: titleDraft)
            await refresh()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
