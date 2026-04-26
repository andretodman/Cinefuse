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

    enum Typography {
        static let screenTitle = Font.title2.weight(.semibold)
        static let sectionTitle = Font.title3.weight(.semibold)
        static let cardTitle = Font.headline.weight(.semibold)
        static let body = Font.body
        static let label = Font.subheadline.weight(.medium)
        static let caption = Font.caption
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
        static let borderSubtle = Color.secondary.opacity(0.2)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let accent = Color.accentColor
        static let danger = Color.red
        static let warning = Color.orange
        static let success = Color.green
        static let shadow = Color.black.opacity(0.12)
    }
}
