import SwiftUI

// MARK: - Design System
// Inspired by: Linear, Vercel, Arc, Apple Notes
// Rule: If it looks "designed", it's wrong.

enum Theme {
    // MARK: - Colors
    // Near-black with subtle warmth, not pure #000
    static let background = Color(hex: "0a0a0b")
    static let surface = Color(hex: "141415")
    static let surfaceHover = Color(hex: "1a1a1c")
    static let border = Color(hex: "232326")
    
    // Accent: Use SPARINGLY. One element per screen max.
    static let accent = Color(hex: "3b82f6") // Blue, not cyan
    static let accentSubtle = Color(hex: "3b82f6").opacity(0.08)
    
    // Text hierarchy
    static let text = Color(hex: "fafafa")
    static let textSecondary = Color(hex: "a1a1aa")
    static let textTertiary = Color(hex: "52525b")
    
    // Semantic
    static let success = Color(hex: "10b981")
    static let destructive = Color(hex: "ef4444")
    
    // MARK: - Typography
    // SF Pro is already perfect. Don't fight it.
    
    static let titleFont = Font.system(size: 32, weight: .semibold, design: .default)
    static let headlineFont = Font.system(size: 17, weight: .semibold)
    static let bodyFont = Font.system(size: 15, weight: .regular)
    static let captionFont = Font.system(size: 13, weight: .medium)
    static let monoFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    
    // MARK: - Spacing
    // 4px base grid
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space10: CGFloat = 40
    static let space12: CGFloat = 48
    
    // MARK: - Radius
    // Subtle, not bubbly
    static let radius1: CGFloat = 4
    static let radius2: CGFloat = 8
    static let radius3: CGFloat = 12
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Minimal Modifiers
// Less is more. Stop adding shadows to everything.

extension View {
    func surfaceStyle() -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous))
    }
    
    func borderStyle() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Button Styles

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.captionFont)
            .foregroundColor(.white)
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space2 + 2)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius1 + 2, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.captionFont)
            .foregroundColor(Theme.text)
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space2 + 2)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius1 + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius1 + 2, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.captionFont)
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space2)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

// MARK: - Haptics (Subtle)

enum Haptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }
    
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
