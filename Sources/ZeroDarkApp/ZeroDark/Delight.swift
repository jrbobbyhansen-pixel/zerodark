import SwiftUI
import CoreHaptics

// MARK: - 12/10 Delight System
// Beyond polish. Surprise. Magic. Personality.

// MARK: - Advanced Haptics Engine

class HapticsEngine {
    static let shared = HapticsEngine()
    private var engine: CHHapticEngine?
    
    init() {
        prepareEngine()
    }
    
    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptics engine error: \(error)")
        }
    }
    
    // Soft tap - for selections
    func softTap() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred(intensity: 0.5)
    }
    
    // Message sent - rising pattern
    func messageSent() {
        guard let engine = engine else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        
        do {
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0.08),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ], relativeTime: 0.15)
            ], parameters: [])
            
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // Response received - gentle double tap
    func responseReceived() {
        guard let engine = engine else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        
        do {
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0.12)
            ], parameters: [])
            
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
    
    // Voice activation - smooth ramp
    func voiceActivated() {
        guard let engine = engine else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        
        do {
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ], relativeTime: 0, duration: 0.3)
            ], parameterCurves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.2),
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0.15, value: 0.8),
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0.3, value: 0.4)
                    ],
                    relativeTime: 0
                )
            ])
            
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - Particle System

struct ParticleEmitter: View {
    let color: Color
    let particleCount: Int
    @Binding var isEmitting: Bool
    
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
        var rotation: Double
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .scaleEffect(particle.scale)
                    .opacity(particle.opacity)
                    .rotationEffect(.degrees(particle.rotation))
                    .offset(x: particle.x, y: particle.y)
            }
        }
        .onChange(of: isEmitting) { emitting in
            if emitting {
                emit()
            }
        }
    }
    
    private func emit() {
        particles = (0..<particleCount).map { _ in
            Particle(
                x: 0,
                y: 0,
                scale: CGFloat.random(in: 0.3...1.0),
                opacity: 1.0,
                rotation: Double.random(in: 0...360)
            )
        }
        
        for i in particles.indices {
            let angle = Double.random(in: 0...2 * .pi)
            let distance = CGFloat.random(in: 30...80)
            
            withAnimation(.easeOut(duration: 0.6)) {
                particles[i].x = cos(angle) * distance
                particles[i].y = sin(angle) * distance
                particles[i].opacity = 0
                particles[i].scale = 0.1
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            particles = []
            isEmitting = false
        }
    }
}

// MARK: - Floating Particles Background

struct FloatingParticles: View {
    @State private var particles: [FloatingParticle] = []
    
    struct FloatingParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var duration: Double
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: particle.size, height: particle.size)
                        .opacity(particle.opacity)
                        .blur(radius: particle.size / 3)
                        .position(x: particle.x, y: particle.y)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
                animateParticles(in: geometry.size)
            }
        }
    }
    
    private func createParticles(in size: CGSize) {
        particles = (0..<8).map { _ in
            FloatingParticle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.02...0.06),
                duration: Double.random(in: 15...25)
            )
        }
    }
    
    private func animateParticles(in size: CGSize) {
        for i in particles.indices {
            animateParticle(at: i, in: size)
        }
    }
    
    private func animateParticle(at index: Int, in size: CGSize) {
        guard index < particles.count else { return }
        
        let newX = CGFloat.random(in: 0...size.width)
        let newY = CGFloat.random(in: 0...size.height)
        let duration = particles[index].duration
        
        withAnimation(.easeInOut(duration: duration)) {
            particles[index].x = newX
            particles[index].y = newY
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            animateParticle(at: index, in: size)
        }
    }
}

// MARK: - Breathing Glow

struct BreathingGlow: ViewModifier {
    let color: Color
    @State private var isBreathing = false
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isBreathing ? 0.3 : 0.1), radius: isBreathing ? 15 : 8, x: 0, y: 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

extension View {
    func breathingGlow(color: Color = Theme.accent) -> some View {
        modifier(BreathingGlow(color: color))
    }
}

// MARK: - Morphing Shape

struct MorphingBlob: View {
    @State private var morph: CGFloat = 0
    let color: Color
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                var path = Path()
                let points = 6
                let radius: CGFloat = min(size.width, size.height) / 2 - 10
                
                for i in 0..<points {
                    let angle = (CGFloat(i) / CGFloat(points)) * 2 * .pi - .pi / 2
                    let wobble = sin(time * 2 + Double(i)) * 0.15 + 1
                    let r = radius * CGFloat(wobble)
                    
                    let x = center.x + cos(angle) * r
                    let y = center.y + sin(angle) * r
                    
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        let prevAngle = (CGFloat(i - 1) / CGFloat(points)) * 2 * .pi - .pi / 2
                        let prevWobble = sin(time * 2 + Double(i - 1)) * 0.15 + 1
                        let prevR = radius * CGFloat(prevWobble)
                        let prevX = center.x + cos(prevAngle) * prevR
                        let prevY = center.y + sin(prevAngle) * prevR
                        
                        let cp1x = prevX + cos(prevAngle + .pi / 2) * 30
                        let cp1y = prevY + sin(prevAngle + .pi / 2) * 30
                        let cp2x = x + cos(angle - .pi / 2) * 30
                        let cp2y = y + sin(angle - .pi / 2) * 30
                        
                        path.addCurve(to: CGPoint(x: x, y: y),
                                     control1: CGPoint(x: cp1x, y: cp1y),
                                     control2: CGPoint(x: cp2x, y: cp2y))
                    }
                }
                path.closeSubpath()
                
                context.fill(path, with: .color(color))
            }
        }
    }
}

// MARK: - Typewriter Text

struct TypewriterText: View {
    let text: String
    let speed: Double
    
    @State private var displayedText = ""
    @State private var currentIndex = 0
    
    var body: some View {
        Text(displayedText)
            .onAppear {
                typeNextCharacter()
            }
    }
    
    private func typeNextCharacter() {
        guard currentIndex < text.count else { return }
        
        let index = text.index(text.startIndex, offsetBy: currentIndex)
        displayedText += String(text[index])
        currentIndex += 1
        
        let delay = text[index] == " " ? speed * 0.5 : speed
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            typeNextCharacter()
        }
    }
}

// MARK: - Elastic Button

struct ElasticButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    
    @State private var scale: CGFloat = 1.0
    @State private var isPressed = false
    
    var body: some View {
        label
            .scaleEffect(scale)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    scale = pressing ? 0.92 : 1.0
                    isPressed = pressing
                }
                if pressing {
                    HapticsEngine.shared.softTap()
                }
            }, perform: {})
            .simultaneousGesture(TapGesture().onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                    scale = 1.08
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                }
                HapticsEngine.shared.softTap()
                action()
            })
    }
}

// MARK: - Pull to Refresh with Bounce

struct BouncyRefresh: View {
    @Binding var isRefreshing: Bool
    let action: () async -> Void
    
    @State private var pullProgress: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let progress = min(1, max(0, geometry.frame(in: .global).minY / 100))
            
            ZStack {
                Circle()
                    .stroke(Theme.surfaceElevated, lineWidth: 3)
                    .frame(width: 30, height: 30)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                
                if isRefreshing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(progress > 0.1 ? 1 : 0)
            .scaleEffect(0.8 + progress * 0.4)
            .onChange(of: progress) { newValue in
                pullProgress = newValue
                if newValue >= 1 && !isRefreshing {
                    triggerRefresh()
                }
            }
        }
        .frame(height: 0)
    }
    
    private func triggerRefresh() {
        isRefreshing = true
        HapticsEngine.shared.softTap()
        
        Task {
            await action()
            isRefreshing = false
        }
    }
}

// MARK: - Contextual Long Press Menu

struct ContextMenu<Content: View, MenuContent: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let menu: MenuContent
    
    @State private var showMenu = false
    @State private var menuScale: CGFloat = 0.8
    @State private var menuOpacity: Double = 0
    
    var body: some View {
        content
            .onLongPressGesture(minimumDuration: 0.5) {
                HapticsEngine.shared.softTap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showMenu = true
                    menuScale = 1.0
                    menuOpacity = 1.0
                }
            }
            .overlay(
                Group {
                    if showMenu {
                        menu
                            .scaleEffect(menuScale)
                            .opacity(menuOpacity)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            )
            .onTapGesture {
                if showMenu {
                    withAnimation(.spring(response: 0.2)) {
                        showMenu = false
                        menuScale = 0.8
                        menuOpacity = 0
                    }
                }
            }
    }
}

// MARK: - Success Checkmark Animation

struct SuccessCheckmark: View {
    @Binding var show: Bool
    
    @State private var circleScale: CGFloat = 0
    @State private var checkmarkTrim: CGFloat = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.success.opacity(0.2))
                .frame(width: 60, height: 60)
                .scaleEffect(circleScale)
            
            Circle()
                .stroke(Theme.success, lineWidth: 3)
                .frame(width: 50, height: 50)
                .scaleEffect(circleScale)
            
            Path { path in
                path.move(to: CGPoint(x: 15, y: 27))
                path.addLine(to: CGPoint(x: 23, y: 35))
                path.addLine(to: CGPoint(x: 37, y: 18))
            }
            .trim(from: 0, to: checkmarkTrim)
            .stroke(Theme.success, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 50, height: 50)
        }
        .opacity(show ? 1 : 0)
        .onChange(of: show) { visible in
            if visible {
                animate()
            } else {
                reset()
            }
        }
    }
    
    private func animate() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            circleScale = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            checkmarkTrim = 1.0
        }
        
        HapticsEngine.shared.responseReceived()
    }
    
    private func reset() {
        circleScale = 0
        checkmarkTrim = 0
    }
}

// MARK: - Ripple Effect

struct RippleEffect: ViewModifier {
    let color: Color
    @Binding var trigger: Bool
    
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
            )
            .onChange(of: trigger) { triggered in
                if triggered {
                    withAnimation(.easeOut(duration: 0.5)) {
                        rippleScale = 2.5
                        rippleOpacity = 0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        rippleScale = 0.5
                        rippleOpacity = 0.5
                        trigger = false
                    }
                }
            }
    }
}

extension View {
    func ripple(color: Color = Theme.accent, trigger: Binding<Bool>) -> some View {
        modifier(RippleEffect(color: color, trigger: trigger))
    }
}

// MARK: - Scroll Velocity Tracker

class ScrollVelocityTracker: ObservableObject {
    @Published var velocity: CGFloat = 0
    private var lastOffset: CGFloat = 0
    private var lastTime: Date = Date()
    
    func update(offset: CGFloat) {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastTime)
        
        if timeDelta > 0 {
            velocity = (offset - lastOffset) / CGFloat(timeDelta)
        }
        
        lastOffset = offset
        lastTime = now
    }
}
