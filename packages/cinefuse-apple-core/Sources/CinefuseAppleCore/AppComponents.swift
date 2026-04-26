import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(configuration.isPressed ? 0.6 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                    )
            )
    }
}

struct DestructiveActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .foregroundStyle(CinefuseTokens.ColorRole.danger)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.danger.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.s) {
            Text(title)
                .font(CinefuseTokens.Typography.sectionTitle)
            if let subtitle {
                Text(subtitle)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            content
        }
        .padding(CinefuseTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                .fill(CinefuseTokens.ColorRole.surfacePrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                        .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                )
        )
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        let style = StatusStyle(rawValue: status)
        Text(style.label)
            .font(CinefuseTokens.Typography.caption.weight(.semibold))
            .foregroundStyle(style.tint)
            .padding(.horizontal, CinefuseTokens.Spacing.xs)
            .padding(.vertical, CinefuseTokens.Spacing.xxs)
            .background(
                Capsule()
                    .fill(style.tint.opacity(0.15))
            )
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xs) {
            Text(title)
                .font(CinefuseTokens.Typography.cardTitle)
            Text(message)
                .font(CinefuseTokens.Typography.caption)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinefuseTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(CinefuseTokens.ColorRole.surfaceSecondary)
        )
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: CinefuseTokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(CinefuseTokens.Typography.caption)
        }
        .foregroundStyle(CinefuseTokens.ColorRole.danger)
        .padding(CinefuseTokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                .fill(CinefuseTokens.ColorRole.danger.opacity(0.08))
        )
    }
}
