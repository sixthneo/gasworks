import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The G-1 is a physical object, so it has one fixed look in light and dark mode.
enum Theme {
    // Case
    static let bodyHi = Color(hex: 0xC3CAB6)
    static let body = Color(hex: 0xAEB6A0)
    static let bodyLo = Color(hex: 0x949D86)
    static let bodyRing = Color(hex: 0x8C957F)
    static let well = Color.black.opacity(0.08)

    // Silkscreen print
    static let print = Color(hex: 0x2C3127)
    static let printSoft = Color(hex: 0x3C4336)
    static let printFaint = Color(hex: 0x5B6352)

    // Rubber pads and caps
    static let rubber = Color(hex: 0xECE6D6)
    static let rubberLo = Color(hex: 0xCFC7B3)
    static let rubberLip = Color(hex: 0x9C947F)
    static let rubberLit = Color(hex: 0xFFF7E6)
    static let rubberLitLo = Color(hex: 0xE9DCC0)
    static let cap = Color(hex: 0x2D2F2A)
    static let capHi = Color(hex: 0x45483F)
    static let capLip = Color(hex: 0x151613)

    // Screen
    static let lcdBg = Color(hex: 0x20160A)
    static let lcdDim = Color(hex: 0x5B3C16)
    static let lcdMid = Color(hex: 0xB47426)
    static let lcd = Color(hex: 0xFFB547)
    static let lcdBody = Color(hex: 0x3A2610)

    // Accent
    static let led = Color(hex: 0xFF9A2E)
    static let ledLip = Color(hex: 0xA85D0D)
    static let red = Color(hex: 0xD9533D)
    static let redLip = Color(hex: 0x8B3324)

    // Steps
    static let stepOff = Color(hex: 0xC3CAB6)
    static let stepBeat = Color(hex: 0xD3D9C7)
    static let stepMuted = Color(hex: 0x9AA38C)

    static func family(_ f: SoundFamily) -> Color {
        switch f {
        case .short: return Color(hex: 0xE8901F)
        case .classic: return Color(hex: 0xD9533D)
        case .big: return Color(hex: 0x2F8A7E)
        case .wet: return Color(hex: 0x7B5CA3)
        }
    }

    static func color(forPreset id: Int) -> Color { family(Presets.all[id].family) }
}

/// Fonts are fixed-size on purpose: the panel is laid out like hardware and must not reflow with Dynamic Type.
enum GFont {
    static func pixel(_ size: CGFloat) -> Font { .custom("VT323-Regular", fixedSize: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Bold", fixedSize: size) }
    static func semi(_ size: CGFloat) -> Font { .custom("BarlowCondensed-SemiBold", fixedSize: size) }
}

/// A raised key that sinks when pressed.
struct HardButtonStyle: ButtonStyle {
    var fill: Color = Theme.cap
    var lip: Color = Theme.capLip
    var foreground: Color = Theme.rubber
    var radius: CGFloat = 12
    var depth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .offset(y: configuration.isPressed ? depth - 1 : 0)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(lip).offset(y: depth))
            .contentShape(Rectangle())
    }
}

/// A flat printed button with an outline, for secondary actions.
struct OutlineButtonStyle: ButtonStyle {
    var radius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.print)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.printFaint, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct CaseBackground: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Theme.bodyHi, location: 0),
            .init(color: Theme.body, location: 0.2),
            .init(color: Theme.body, location: 0.84),
            .init(color: Theme.bodyLo, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// A recessed panel area (sequencer, mixer).
struct WellBackground: View {
    var radius: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.well)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
    }
}
