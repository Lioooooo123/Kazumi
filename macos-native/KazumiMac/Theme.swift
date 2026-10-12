// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

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

    /// Content well. Flutter paints this with `colorScheme.primaryContainer`.
    static func canvas(_ scheme: ColorScheme, oled: Bool = false) -> Color {
        if oled && scheme == .dark { return .black }
        return scheme == .dark
            ? Color(red: 0.05, green: 0.09, blue: 0.07)
            : Color(red: 0.82, green: 0.91, blue: 0.84)
    }

    /// Grid cards sit on the green well the way Material `Card` uses `surface`.
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.14, blue: 0.12)
            : Color.white
    }

    /// Timeline cards use `surfaceContainerLow`, a step above the canvas.
    static func timelineCard(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.18, blue: 0.15)
            : Color(red: 0.94, green: 0.97, blue: 0.94)
    }

    /// Rating chip. Flutter uses `secondaryContainer`.
    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.20, green: 0.28, blue: 0.22)
            : Color(red: 0.84, green: 0.91, blue: 0.86)
    }

    static let cardSpacing: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let timelineRadius: CGFloat = 28
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
