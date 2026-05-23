import AppKit
import SwiftUI

enum SymbolColor {
    static func nsColor(hex: String) -> NSColor {
        let normalized = UsageKeyConfiguration.normalizedSymbolColorHex(hex)
        let value = String(normalized.dropFirst())
        guard let integer = Int(value, radix: 16) else {
            return .white
        }
        return NSColor(
            calibratedRed: CGFloat((integer >> 16) & 0xFF) / 255,
            green: CGFloat((integer >> 8) & 0xFF) / 255,
            blue: CGFloat(integer & 0xFF) / 255,
            alpha: 1
        )
    }

    static func swiftUIColor(hex: String) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }

    static func hexString(from color: Color) -> String {
        let nsColor = NSColor(color)
        let resolved = nsColor.usingColorSpace(.sRGB)
            ?? nsColor.usingColorSpace(.deviceRGB)
            ?? .white

        return String(
            format: "#%02X%02X%02X",
            clampedColorComponent(resolved.redComponent),
            clampedColorComponent(resolved.greenComponent),
            clampedColorComponent(resolved.blueComponent)
        )
    }

    private static func clampedColorComponent(_ value: CGFloat) -> Int {
        min(255, max(0, Int(round(value * 255))))
    }
}
