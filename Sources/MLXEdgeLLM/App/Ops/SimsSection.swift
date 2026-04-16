// SimsSection.swift — Ops > Sims sub-section

import SwiftUI

struct SimsSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                OpsSectionHeader(icon: "antenna.radiowaves.left.and.right", title: "COMMUNICATIONS", color: ZDDesign.cyanAccent)

                NavigationLink {
                    ComingSoonView(title: "Comms Simulator", icon: "waveform.badge.mic", description: "Practice radio procedures, protocols & channel management")
                } label: {
                    OpsSectionCard(
                        icon: "waveform.badge.mic",
                        title: "Comms Simulator",
                        subtitle: "Practice radio procedures, protocols & channel management",
                        color: ZDDesign.cyanAccent
                    )
                }

                OpsSectionHeader(icon: "flag.checkered", title: "TEAM CHALLENGES", color: ZDDesign.safetyYellow)

                NavigationLink {
                    ComingSoonView(title: "Team Challenge", icon: "figure.2.arms.open", description: "Scenario-based challenges with tasks, locations & scoring")
                } label: {
                    OpsSectionCard(
                        icon: "figure.2.arms.open",
                        title: "Team Challenge",
                        subtitle: "Scenario-based challenges with tasks, locations & scoring",
                        color: ZDDesign.safetyYellow
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}
