// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import AppKit
import KazumiCore
import SwiftUI

enum KazumiTheme {
    static func accent(_ id: String) -> Color {
        let hex = KazumiCore.accentPalette.first { $0.id == id }?.hex ?? 0x4CAF50
        return Color(hex: hex)
    }

    static func scheme(_ mode: String) -> ColorScheme? {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// System surfaces keep artwork, rather than the accent, in the foreground.
    static func canvas(_ scheme: ColorScheme, oled: Bool = false) -> Color {
        if oled && scheme == .dark { return .black }
        return Color(nsColor: .windowBackgroundColor)
    }

    /// Local panels use a system control surface.
    static func card(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Timeline rows share the same neutral surface.
    static func timelineCard(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// A secondary chip uses a quiet neutral fill.
    static func chip(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(0.06)
    }

    static let cardSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 10
    static let timelineRadius: CGFloat = 16
    static let pagePadding: CGFloat = 24
    static let pageWidth: CGFloat = 1100

    // Pointer press is brief; keyboard navigation never waits for a transition.
    static let pressFeedback = Animation.easeOut(duration: 0.12)
    static let controlsVisibility = Animation.easeOut(duration: 0.18)
    static let posterColumns = [GridItem(.adaptive(minimum: 144, maximum: 184), spacing: cardSpacing)]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(rgb: Int) {
        self.init(hex: UInt32(rgb & 0xFFFFFF))
    }
}
