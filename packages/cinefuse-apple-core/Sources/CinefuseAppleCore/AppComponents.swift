import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .lineLimit(1)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .frame(minWidth: CinefuseTokens.Control.minButtonWidth, minHeight: CinefuseTokens.Control.minButtonHeight)
            .foregroundStyle(CinefuseTokens.ColorRole.labelOnAccent)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(CinefuseTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .lineLimit(1)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .frame(minWidth: CinefuseTokens.Control.minButtonWidth, minHeight: CinefuseTokens.Control.minButtonHeight)
            .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(configuration.isPressed ? 0.6 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(CinefuseTokens.Motion.quick, value: configuration.isPressed)
    }
}

/// Stacked inspector / sheet actions: full-width friendly, up to two lines, avoids clipped “Generate…” labels on narrow widths.
struct PanelSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.88)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: CinefuseTokens.Control.minButtonHeight)
            .foregroundStyle(CinefuseTokens.ColorRole.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(configuration.isPressed ? 0.6 : 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                            .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(CinefuseTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct DestructiveActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CinefuseTokens.Typography.label)
            .lineLimit(1)
            .padding(.horizontal, CinefuseTokens.Spacing.m)
            .padding(.vertical, CinefuseTokens.Spacing.xs)
            .frame(minWidth: CinefuseTokens.Control.minButtonWidth, minHeight: CinefuseTokens.Control.minButtonHeight)
            .foregroundStyle(CinefuseTokens.ColorRole.danger)
            .background(
                RoundedRectangle(cornerRadius: CinefuseTokens.Radius.medium)
                    .fill(CinefuseTokens.ColorRole.danger.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(CinefuseTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let isCollapsed: Binding<Bool>?
    let titleFont: Font
    /// Vertical rhythm between title row, optional subtitle, and content.
    let stackSpacing: CGFloat
    let contentPadding: CGFloat
    /// Shown to the **left** of the collapse chevron (e.g. timeline density controls).
    let headerAccessory: AnyView?
    /// When true, expanded content uses the full vertical space offered by the parent (splitter-resized stacks).
    let fillAvailableHeight: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        isCollapsed: Binding<Bool>? = nil,
        titleFont: Font = CinefuseTokens.Typography.sectionTitle,
        stackSpacing: CGFloat = CinefuseTokens.Spacing.s,
        contentPadding: CGFloat = CinefuseTokens.Spacing.m,
        headerAccessory: AnyView? = nil,
        fillAvailableHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isCollapsed = isCollapsed
        self.titleFont = titleFont
        self.stackSpacing = stackSpacing
        self.contentPadding = contentPadding
        self.headerAccessory = headerAccessory
        self.fillAvailableHeight = fillAvailableHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            HStack(alignment: .center, spacing: CinefuseTokens.Spacing.s) {
                Text(title)
                    .font(titleFont)
                Spacer(minLength: CinefuseTokens.Spacing.s)
                if let headerAccessory {
                    headerAccessory
                }
                if let isCollapsed {
                    Button {
                        withAnimation(CinefuseTokens.Motion.panel) {
                            isCollapsed.wrappedValue.toggle()
                        }
                    } label: {
                        Image(systemName: isCollapsed.wrappedValue ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                            .font(.system(size: CinefuseTokens.Control.iconSymbolSize, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed.wrappedValue ? "Expand panel" : "Collapse panel")
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(CinefuseTokens.Typography.caption)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
            if !(isCollapsed?.wrappedValue ?? false) {
                content
                    .frame(maxWidth: .infinity, maxHeight: fillAvailableHeight ? .infinity : nil, alignment: .topLeading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .padding(contentPadding)
        .background(
            RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                .fill(CinefuseTokens.ColorRole.surfacePrimary.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.large)
                        .stroke(CinefuseTokens.ColorRole.borderSubtle, lineWidth: 1)
                )
                .shadow(color: CinefuseTokens.ColorRole.shadow, radius: 8, x: 0, y: 4)
        )
        .animation(CinefuseTokens.Motion.panel, value: isCollapsed?.wrappedValue ?? false)
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
                    .fill(style.tint.opacity(0.2))
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

struct PubfuseLogoBadge: View {
    var body: some View {
        PubfuseLogoImage()
            .frame(width: CinefuseTokens.Control.logoWidth, height: CinefuseTokens.Control.logoHeight)
    }
}

struct IconCommandButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var isDestructive = false
    var tooltipEnabled = true
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: CinefuseTokens.Control.iconSymbolSize, weight: .semibold))
                .frame(width: CinefuseTokens.Control.minIconButtonSize, height: CinefuseTokens.Control.minIconButtonSize)
                .foregroundStyle(isDestructive ? CinefuseTokens.ColorRole.danger : CinefuseTokens.ColorRole.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: CinefuseTokens.Radius.small)
                        .fill(CinefuseTokens.ColorRole.surfaceSecondary.opacity(isHovering ? 0.8 : 1))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(CinefuseTokens.Motion.quick, value: isHovering)
#if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
#endif
        .accessibilityLabel(label)
        .tooltip(label, enabled: tooltipEnabled)
    }
}

extension View {
    @ViewBuilder
    func tooltip(_ value: String, enabled: Bool) -> some View {
        if enabled {
            self.help(value)
        } else {
            self
        }
    }
}

private struct PubfuseLogoImage: View {
    private let candidates = [
        "/Users/atodman/Documents/GitHub/PubfuseRewrite/PubfuseRestApi/web/public/images/pubfuse_v1.3.png",
        "/Users/atodman/Documents/GitHub/PubfuseRewrite/PubfuseRestApi/web/public/images/pubfuse_v1.1_128x128.png"
    ]

    var body: some View {
        Group {
#if canImport(UIKit)
            if let image = candidates.compactMap({ UIImage(contentsOfFile: $0) }).first {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(CinefuseTokens.ColorRole.accent)
            }
#elseif canImport(AppKit)
            if let image = candidates.compactMap({ NSImage(contentsOfFile: $0) }).first {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(CinefuseTokens.ColorRole.accent)
            }
#else
            Image(systemName: "bolt.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(CinefuseTokens.ColorRole.accent)
#endif
        }
    }
}
