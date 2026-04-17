// EvalDebriefSection.swift — Ops > Eval sub-section

import SwiftUI

struct EvalDebriefSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                OpsSectionHeader(icon: "star.fill", title: "EVALUATION", color: ZDDesign.safetyYellow)

                NavigationLink {
                    ComingSoonView(title: "Evaluator Tools", icon: "checkmark.rectangle.stack.fill", description: "Checklists, scoring rubrics, real-time notes & summary reports")
                } label: {
                    OpsSectionCard(
                        icon: "checkmark.rectangle.stack.fill",
                        title: "Evaluator Tools",
                        subtitle: "Checklists, scoring rubrics, real-time notes & summary reports",
                        color: ZDDesign.safetyYellow
                    )
                }

                NavigationLink {
                    ComingSoonView(title: "Photo/Video Log", icon: "camera.fill", description: "Capture, record & tag media with location data")
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
                    AARBuilderView()
                } label: {
                    OpsSectionCard(
                        icon: "doc.text.magnifyingglass",
                        title: "After Action Reports",
                        subtitle: "Generate AAR from mission data; timeline, decisions, outcomes, lessons. Export PDF/Markdown.",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    ComingSoonView(title: "Team Skills", icon: "chart.bar.fill", description: "Skill aggregation, gap analysis & training priorities")
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
