// EvalDebriefSection.swift — Ops > Eval sub-section

import SwiftUI

struct EvalDebriefSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                OpsSectionHeader(icon: "star.fill", title: "EVALUATION", color: ZDDesign.safetyYellow)

                NavigationLink {
                    Text("Evaluator Tools — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "checkmark.rectangle.stack.fill",
                        title: "Evaluator Tools",
                        subtitle: "Checklists, scoring rubrics, real-time notes & summary reports",
                        color: ZDDesign.safetyYellow
                    )
                }

                NavigationLink {
                    Text("Photo/Video Log — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "camera.fill",
                        title: "Photo/Video Log",
                        subtitle: "Capture, record & tag media with location data",
                        color: ZDDesign.cyanAccent
                    )
                }

                OpsSectionHeader(icon: "bubble.left.and.bubble.right.fill", title: "DEBRIEF & SKILLS", color: ZDDesign.forestGreen)

                NavigationLink {
                    Text("Debrief Manager — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "text.bubble.fill",
                        title: "Debrief Manager",
                        subtitle: "Session scheduling, attendance tracking & documentation",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    Text("Team Skills — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "chart.bar.fill",
                        title: "Team Skills",
                        subtitle: "Skill aggregation, gap analysis & training priorities",
                        color: ZDDesign.darkSage
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}
