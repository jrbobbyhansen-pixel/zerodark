import SwiftUI

// MARK: - Marble Polish Components
// Every detail matters. Friction-free. Delightful.

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Animated Button

struct AnimatedButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    
    @State private var isPressed = false
    
    var body: some View {
        label
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
                if pressing { Haptics.light() }
            }, perform: {})
            .simultaneousGesture(TapGesture().onEnded {
                Haptics.light()
                action()
            })
    }
}

// MARK: - Skeleton Loader

struct SkeletonLoader: View {
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radiusSM)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Theme.surface,
                                Theme.surfaceElevated,
                                Theme.surface
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct MessageSkeleton: View {
    let isUser: Bool
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                SkeletonLoader()
                    .frame(width: isUser ? 180 : 220, height: 16)
                SkeletonLoader()
                    .frame(width: isUser ? 120 : 160, height: 16)
            }
            .padding(Theme.spacingMD)
            .background(Theme.surface)
            .cornerRadius(Theme.radiusLG)
            
            if !isUser { Spacer() }
        }
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Get Started"
    
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: CGFloat = 0
    
    var body: some View {
        VStack(spacing: Theme.spacingLG) {
            ZStack {
                Circle()
                    .fill(Theme.accentMuted)
                    .frame(width: 100, height: 100)
                
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .subtleGlow()
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
            }
            
            VStack(spacing: Theme.spacingSM) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingXL)
            }
            
            if let action = action {
                Button(action: {
                    Haptics.medium()
                    action()
                }) {
                    Text(actionLabel)
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, Theme.spacingSM)
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [(icon: String, label: String)]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                TabBarItem(
                    icon: tabs[index].icon,
                    label: tabs[index].label,
                    isSelected: selectedTab == index
                )
                .onTapGesture {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(
            Theme.surface
                .overlay(
                    Rectangle()
                        .fill(Theme.surfaceElevated)
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.accent : Theme.textMuted)
                .subtleGlow(color: isSelected ? Theme.accent : .clear)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? Theme.accent : Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacingXS)
    }
}

// MARK: - Pull to Refresh

struct PullToRefresh: View {
    @Binding var isRefreshing: Bool
    let action: () async -> Void
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.frame(in: .global).minY > 50 {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        if !isRefreshing {
                            isRefreshing = true
                            Haptics.light()
                            Task {
                                await action()
                                isRefreshing = false
                            }
                        }
                    }
            }
        }
        .frame(height: 0)
    }
}

// MARK: - Animated Gradient Background

struct AnimatedGradientBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Theme.background
            
            // Subtle moving gradient orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Theme.accent.opacity(0.08),
                            Theme.accent.opacity(0.02),
                            .clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: animate ? 100 : -100, y: animate ? -50 : 50)
                .blur(radius: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Toast Notification

struct Toast: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success, error, info
        
        var color: Color {
            switch self {
            case .success: return Theme.success
            case .error: return Theme.error
            case .info: return Theme.accent
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: type.icon)
                .font(.system(size: 18))
                .foregroundColor(type.color)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(Theme.surface)
        .cornerRadius(Theme.radiusXL)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

// MARK: - Transition Extensions

extension AnyTransition {
    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }
    
    static var fadeScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }
}

// MARK: - Swipe Actions

struct SwipeAction: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            Haptics.medium()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 60)
                .frame(maxHeight: .infinity)
                .background(color)
        }
    }
}

// MARK: - Shimmer Effect

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Theme.textPrimary.opacity(0.1),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}
