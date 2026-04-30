import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Panels presented as sheets on iPhone / compact iPad instead of inline columns or bottom strips.
public enum MobileEditorPresentedPanel: String, Identifiable, Sendable {
    case leftInspector
    case rightInspector
    case audioLanes
    case jobs

    public var id: String { rawValue }

    public var navigationTitle: String {
        navigationTitle(isAudioCreationMode: false)
    }

    public func navigationTitle(isAudioCreationMode: Bool) -> String {
        switch self {
        case .leftInspector:
            return isAudioCreationMode ? "Sound tools" : "Story & Characters"
        case .rightInspector:
            return isAudioCreationMode ? "Sounds & export" : "Shots & Export"
        case .audioLanes:
            return "Audio Lanes"
        case .jobs:
            return "Jobs"
        }
    }
}

/// Layout strategy for the editor: desktop keeps inline split panes; iOS prefers sheets for bottom tools and (on phone) side inspectors.
public struct EditorLayoutTraits: Sendable {
    /// When true, left/right inspector content opens in sheets instead of beside the preview.
    public let useSheetBasedSidePanels: Bool
    /// When false, audio lanes + jobs never consume vertical space below the canvas (use sheets instead).
    public let useInlineBottomRegion: Bool
    /// Prefer compact toolbar / overflow menus for workspace controls.
    public let useCompactWorkspaceChrome: Bool

#if os(iOS)
    /// Traits for iPhone / iPad based on size class and idiom.
    public static func iOS(horizontalSizeClass: UserInterfaceSizeClass?) -> EditorLayoutTraits {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return EditorLayoutTraits(
                useSheetBasedSidePanels: true,
                useInlineBottomRegion: false,
                useCompactWorkspaceChrome: true
            )
        case .pad:
            let compact = horizontalSizeClass == .compact
            return EditorLayoutTraits(
                useSheetBasedSidePanels: compact,
                useInlineBottomRegion: false,
                useCompactWorkspaceChrome: compact
            )
        default:
            return .desktopLike
        }
    }
#endif

    public static let desktopLike = EditorLayoutTraits(
        useSheetBasedSidePanels: false,
        useInlineBottomRegion: true,
        useCompactWorkspaceChrome: false
    )
}

#if os(iOS)
enum EditorMobileDefaultsMigration {
    private static let migrationKey = "cinefuse.editor.defaultsMigration.mobileChromeV1"

    /// One-time: avoid desktop-oriented ``showBottomPane`` default on iOS so sheet-based chrome isn’t fighting persisted true.
    static func applyIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)
        UserDefaults.standard.set(false, forKey: "cinefuse.editor.showBottomPane")
    }
}
#endif
