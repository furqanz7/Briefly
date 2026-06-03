import SwiftUI

enum BrieflyTheme {
    static let backgroundBase = Color(hex: 0x050508)
    static let cardBase = Color(hex: 0x111118)
    static let elevatedCard = Color(hex: 0x181824)
    static let primaryText = Color(hex: 0xF7F4FF)
    static let secondaryText = Color(hex: 0xA7A1B8)
    static let accent = Color(hex: 0x7B3CFF)
    static let accentBlue = Color(hex: 0x2F7CFF)
    static let divider = Color(hex: 0x252538)
    static let glowViolet = Color(hex: 0x7B3CFF).opacity(0.25)
    static let glowBlue = Color(hex: 0x2F7CFF).opacity(0.18)
    static let actionFill = accent
    static let actionGradient = LinearGradient(
        colors: [accent, accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Compatibility aliases for older view code. These now point to the Briefly identity.
    static let peach = elevatedCard
    static let orange = accentBlue
    static let backgroundTint = backgroundBase
    static let backgroundLight = backgroundBase
    static let cardLight = cardBase
    static let textLight = primaryText
    static let backgroundDark = backgroundBase
    static let cardDark = cardBase
    static let textDark = primaryText

    static func background(_ scheme: ColorScheme) -> Color {
        backgroundBase
    }

    static func card(_ scheme: ColorScheme) -> Color {
        cardBase
    }

    static func text(_ scheme: ColorScheme) -> Color {
        primaryText
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        secondaryText
    }

    static var premiumBackground: some View {
        ZStack {
            backgroundBase
            RadialGradient(
                colors: [glowViolet, .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [glowBlue, .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
    }
}

extension Color {
    init(hex: UInt64) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
