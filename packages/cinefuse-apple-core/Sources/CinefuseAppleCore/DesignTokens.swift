import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum CinefuseTokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Control {
        static let minButtonHeight: CGFloat = 34
        static let minButtonWidth: CGFloat = 88
        static let minIconButtonSize: CGFloat = 32
        static let iconSymbolSize: CGFloat = 13
        static let minCenterPreviewWidth: CGFloat = 320
        static let minSidePanelWidth: CGFloat = 340
        static let maxSidePanelWidth: CGFloat = 640
        static let minBottomPanelHeight: CGFloat = 210
        static let minTopWorkspaceHeight: CGFloat = 320
        static let splitterThickness: CGFloat = 6
        static let splitterHitArea: CGFloat = 24
        static let layoutHandleReserve: CGFloat = 16
        static let timelineCardWidth: CGFloat = 220
        static let timelineCardHeight: CGFloat = 112
        static let primaryPickerWidth: CGFloat = 130
        static let secondaryPickerWidth: CGFloat = 170
        static let jobPickerWidth: CGFloat = 140
        static let headerDividerHeight: CGFloat = 18
        static let logoWidth: CGFloat = 92
        static let logoHeight: CGFloat = 24
        static let settingsPanelWidth: CGFloat = 420
        /// Wider layout when the iPad build runs on macOS (“Designed for iPad”).
        static let settingsPanelWidthIOSMac: CGFloat = 560
        static let timelineRulerHeight: CGFloat = 28
        static let timelineNotchMinor: CGFloat = 8
        static let timelineNotchMajor: CGFloat = 14
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.16)
        static let standard = Animation.easeInOut(duration: 0.24)
        static let emphasis = Animation.spring(response: 0.34, dampingFraction: 0.84)
        static let panel = Animation.spring(response: 0.28, dampingFraction: 0.88)
    }

    enum Typography {
        static let screenTitle = Font.title2.weight(.semibold)
        static let sectionTitle = Font.title3.weight(.semibold)
        static let cardTitle = Font.headline.weight(.semibold)
        static let timelineHeader = Font.callout.weight(.semibold)
        static let body = Font.body
        static let label = Font.subheadline.weight(.medium)
        static let caption = Font.caption
        static let micro = Font.caption2.weight(.medium)
        /// Processing % / status beside compact progress controls (timeline, shots, jobs).
        static let nano = Font.system(size: 9, weight: .medium)
    }

    enum ColorRole {
        static let canvas: Color = {
#if canImport(UIKit)
            Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
            Color(nsColor: .windowBackgroundColor)
#else
            Color.gray
#endif
        }()
        static let surfacePrimary: Color = {
#if canImport(UIKit)
            Color(uiColor: .secondarySystemBackground)
#elseif canImport(AppKit)
            Color(nsColor: .controlBackgroundColor)
#else
            Color.gray.opacity(0.2)
#endif
        }()
        static let surfaceSecondary: Color = {
#if canImport(UIKit)
            Color(uiColor: .tertiarySystemBackground)
#elseif canImport(AppKit)
            Color(nsColor: .textBackgroundColor)
#else
            Color.gray.opacity(0.1)
#endif
        }()
        static let borderSubtle = Color.secondary.opacity(0.28)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary.opacity(0.92)
        static let labelOnAccent = Color.white
        static let accent = Color.accentColor
        static let danger = Color.red
        static let warning = Color.orange
        static let success = Color.green
        static let shadow = Color.black.opacity(0.09)
    }

    struct ThemePalette {
        let accent: Color
        let timelineBase: Color
        let timelineBevelTop: Color
        let timelineBevelBottom: Color
        let timelineRuler: Color
    }

    enum Theme {
        static let system = ThemePalette(
            accent: .accentColor,
            timelineBase: ColorRole.surfaceSecondary.opacity(0.85),
            timelineBevelTop: .white.opacity(0.35),
            timelineBevelBottom: .black.opacity(0.16),
            timelineRuler: ColorRole.borderSubtle
        )
        static let light = ThemePalette(
            accent: .blue,
            timelineBase: Color(red: 0.93, green: 0.95, blue: 0.97),
            timelineBevelTop: .white.opacity(0.55),
            timelineBevelBottom: .black.opacity(0.12),
            timelineRuler: Color(red: 0.52, green: 0.58, blue: 0.65).opacity(0.6)
        )
        static let dark = ThemePalette(
            accent: Color(red: 0.35, green: 0.63, blue: 1),
            timelineBase: Color(red: 0.16, green: 0.18, blue: 0.22),
            timelineBevelTop: .white.opacity(0.1),
            timelineBevelBottom: .black.opacity(0.45),
            timelineRuler: Color(red: 0.55, green: 0.63, blue: 0.75).opacity(0.7)
        )
        static let ivorySlate = ThemePalette(
            accent: Color(red: 0.34, green: 0.46, blue: 0.7),
            timelineBase: Color(red: 0.95, green: 0.94, blue: 0.9),
            timelineBevelTop: .white.opacity(0.6),
            timelineBevelBottom: Color(red: 0.58, green: 0.58, blue: 0.62).opacity(0.22),
            timelineRuler: Color(red: 0.48, green: 0.52, blue: 0.6).opacity(0.58)
        )
        static let carbonGlass = ThemePalette(
            accent: Color(red: 0.46, green: 0.7, blue: 0.9),
            timelineBase: Color(red: 0.14, green: 0.17, blue: 0.2),
            timelineBevelTop: .white.opacity(0.13),
            timelineBevelBottom: .black.opacity(0.48),
            timelineRuler: Color(red: 0.56, green: 0.71, blue: 0.78).opacity(0.7)
        )
        static let cobaltPulse = ThemePalette(
            accent: Color(red: 0.27, green: 0.45, blue: 0.94),
            timelineBase: Color(red: 0.18, green: 0.22, blue: 0.34),
            timelineBevelTop: .white.opacity(0.17),
            timelineBevelBottom: .black.opacity(0.42),
            timelineRuler: Color(red: 0.62, green: 0.71, blue: 0.98).opacity(0.72)
        )
        static let sandstone = ThemePalette(
            accent: Color(red: 0.68, green: 0.45, blue: 0.3),
            timelineBase: Color(red: 0.93, green: 0.88, blue: 0.8),
            timelineBevelTop: .white.opacity(0.55),
            timelineBevelBottom: Color(red: 0.54, green: 0.44, blue: 0.32).opacity(0.25),
            timelineRuler: Color(red: 0.54, green: 0.46, blue: 0.38).opacity(0.58)
        )
    }
}
