import SwiftUI

/// Horizontal looping highlight for generation waits where the API has not reported a numeric percent yet.
struct AnimatedIndeterminateProgressBar: View {
    private let trackOpacity: Double
    private let fillOpacity: Double
    private let height: CGFloat

    init(
        trackOpacity: Double = 0.22,
        fillOpacity: Double = 0.92,
        height: CGFloat = 5
    ) {
        self.trackOpacity = trackOpacity
        self.fillOpacity = fillOpacity
        self.height = height
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: false)) { timeline in
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let segment = max(min(width * 0.46, width), 40)
                let period = width + segment * 1.2
                let t = timeline.date.timeIntervalSinceReferenceDate
                let speed = 78.0
                let offset = CGFloat(fmod(t * speed, Double(period))) - segment

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CinefuseTokens.ColorRole.borderSubtle.opacity(trackOpacity + 0.35))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    CinefuseTokens.ColorRole.accent.opacity(0.2),
                                    CinefuseTokens.ColorRole.accent.opacity(fillOpacity),
                                    CinefuseTokens.ColorRole.accent.opacity(0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: segment)
                        .offset(x: offset)
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
        }
        .accessibilityLabel("In progress")
    }
}

/// Shared row: determinate bar when the gateway reports a percent; animated strip otherwise.
struct GenerationActivityProgressRow: View {
    let determinatePercent: Int?
    let waitingLabel: String
    let determinateLabel: (Int) -> String

    var body: some View {
        HStack(spacing: CinefuseTokens.Spacing.xs) {
            if let p = determinatePercent {
                ProgressView(value: Double(p), total: 100)
                    .controlSize(.mini)
                    .tint(CinefuseTokens.ColorRole.accent)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.28), value: p)
                Text(determinateLabel(p))
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            } else {
                AnimatedIndeterminateProgressBar()
                    .frame(maxWidth: .infinity)
                Text(waitingLabel)
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
            }
        }
    }
}
