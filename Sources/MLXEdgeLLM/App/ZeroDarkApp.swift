//
//  ZeroDarkApp.swift
//  ZeroDark
//
//  Tactical recon and emergency response platform
//

import SwiftUI

// MARK: - Design System

/// ZeroDark Design Tokens - Premium Outdoor Aesthetic
public struct ZDDesign {
    // Primary Colors
    static let forestGreen = Color(red: 0.176, green: 0.314, blue: 0.086)  // #2D5016
    static let darkSage = Color(red: 0.529, green: 0.663, blue: 0.420)     // #87A96B
    static let warmGray = Color(red: 0.545, green: 0.525, blue: 0.502)     // #8B8680

    // Secondary Colors
    static let skyBlue = Color(red: 0.290, green: 0.565, blue: 0.643)      // #4A90A4
    static let sunsetOrange = Color(red: 0.824, green: 0.412, blue: 0.118) // #D2691E
    static let earthBrown = Color(red: 0.545, green: 0.271, blue: 0.075)   // #8B4513

    // Accent Colors
    static let safetyYellow = Color(red: 1.0, green: 0.843, blue: 0.0)     // #FFD700
    static let signalRed = Color(red: 1.0, green: 0.267, blue: 0.267)      // #FF4444
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.0)     // #FF9900
    static let successGreen = Color(red: 0.157, green: 0.655, blue: 0.271) // #28A745

    // Neutral Palette
    static let pureWhite = Color.white
    static let lightGray = Color(red: 0.973, green: 0.976, blue: 0.980)    // #F8F9FA
    static let mediumGray = Color(red: 0.424, green: 0.459, blue: 0.490)   // #6C757D
    static let charcoal = Color(red: 0.204, green: 0.227, blue: 0.251)     // #343A40

    // Dark Mode
    static let darkBackground = Color(red: 0.035, green: 0.035, blue: 0.059) // #09090f
    static let darkCard = Color(red: 0.067, green: 0.067, blue: 0.090)
    static let cyanAccent = Color(red: 0.133, green: 0.827, blue: 0.933)   // #22d3ee

    // Spacing
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24

    // Corner Radius
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusXL: CGFloat = 24
}

// MARK: - App Entry Point

@main
struct ZeroDarkApp: App {
    init() {
        // Auto-connect to saved mesh network
        Task { @MainActor in
            MeshService.shared.autoStart()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if LocalInferenceEngine.shared.modelFileExists {
                        await LocalInferenceEngine.shared.loadModel()
                    }
                }
        }
    }
}
