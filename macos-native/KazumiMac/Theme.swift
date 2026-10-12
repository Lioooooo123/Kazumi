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

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.09, blue: 0.08)
            : Color(red: 0.91, green: 0.95, blue: 0.91)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.16, blue: 0.14)
            : Color.white
    }

    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.18, green: 0.24, blue: 0.20)
            : Color(red: 0.86, green: 0.93, blue: 0.87)
    }
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
