import SwiftUI

// MARK: - SquadOps Design System
// Deep impact. Elegant. Minimal chrome.

enum Theme {
    // MARK: - Colors
    static let background = Color(hex: "09090f")
    static let surface = Color(hex: "111118")
    static let surfaceElevated = Color(hex: "18181f")
    static let accent = Color(hex: "22d3ee")
    static let accentMuted = Color(hex: "22d3ee").opacity(0.15)
    
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "71717a")
    static let textMuted = Color(hex: "52525b")
    
    static let success = Color(hex: "22c55e")
    static let warning = Color(hex: "f59e0b")
    static let error = Color(hex: "ef4444")
    
    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacing2XL: CGFloat = 48
    
    // MARK: - Corner Radius
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusXL: CGFloat = 24
    
    // MARK: - Typography
    static func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(textPrimary)
    }
    
    static func headline(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(textPrimary)
    }
    
    static func body(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(textSecondary)
    }
    
    static func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(textMuted)
    }
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

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var elevated: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacingMD)
            .background(elevated ? Theme.surfaceElevated : Theme.surface)
            .cornerRadius(Theme.radiusMD)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.background)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.accent)
            .cornerRadius(Theme.radiusMD)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
            .background(Theme.accentMuted)
            .cornerRadius(Theme.radiusMD)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(Theme.textSecondary)
            .frame(width: 44, height: 44)
            .background(Theme.surface)
            .cornerRadius(Theme.radiusSM)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension View {
    func card(elevated: Bool = false) -> some View {
        modifier(CardStyle(elevated: elevated))
    }
}

// MARK: - Glow Effect

struct GlowEffect: ViewModifier {
    var color: Color = Theme.accent
    var radius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.3), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func glow(color: Color = Theme.accent, radius: CGFloat = 20) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}
