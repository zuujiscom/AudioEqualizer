// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The app's one visual language: a dark studio surface, with colour reserved
/// for what the audio is doing. Mint means boost or running, amber means cut
/// or bypassed, and the cyan-violet-pink gradient belongs to the live signal.
enum Theme {
    static let backgroundTop = Color(red: 0.070, green: 0.075, blue: 0.115)
    static let backgroundBottom = Color(red: 0.028, green: 0.030, blue: 0.052)
    static let well = Color(red: 0.020, green: 0.022, blue: 0.040)

    static let cardFill = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.07)

    static let cyan = Color(red: 0.24, green: 0.86, blue: 1.00)
    static let violet = Color(red: 0.56, green: 0.44, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.33, blue: 0.64)
    static let mint = Color(red: 0.30, green: 0.94, blue: 0.66)
    static let amber = Color(red: 1.00, green: 0.68, blue: 0.26)
    static let red = Color(red: 1.00, green: 0.33, blue: 0.36)

    static let signalColors = [cyan, violet, pink]

    static let signal = LinearGradient(colors: signalColors, startPoint: .leading, endPoint: .trailing)

    static let background = LinearGradient(
        colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom
    )

    /// Mint for a boost, amber for a cut, neutral at rest.
    static func gainColor(_ gain: Double) -> Color {
        if gain > 0.25 { return mint }
        if gain < -0.25 { return amber }
        return Color.white.opacity(0.75)
    }
}

extension View {
    /// The raised panel every section of the main window sits on.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    /// A small rounded control surface for the header's menus and toggles.
    func pill(active: Bool = false, tint: Color = Theme.cyan) -> some View {
        self
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                Capsule().fill(active ? tint.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(active ? tint.opacity(0.55) : Color.white.opacity(0.10))
            )
            .contentShape(Capsule())
    }
}

/// Section heading used across the cards.
struct SectionTitle: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.signal)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}
