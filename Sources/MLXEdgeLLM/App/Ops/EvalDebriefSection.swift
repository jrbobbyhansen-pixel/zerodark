// EvalDebriefSection.swift — Ops > Eval sub-section

import SwiftUI

struct EvalDebriefSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {

                OpsSectionHeader(icon: "brain", title: "AI TOOLS", color: ZDDesign.cyanAccent)

                NavigationLink { SitrepView() } label: {
                    OpsSectionCard(icon: "doc.text.fill", title: "SITREP Generator",
                                   subtitle: "Auto-generate situation report from live system state. Export & send.",
                                   color: ZDDesign.cyanAccent)
                }
                NavigationLink { RiskAssessorView() } label: {
                    OpsSectionCard(icon: "exclamationmark.triangle.fill", title: "Risk Assessor",
                                   subtitle: "Mission risk by domain: weather, altitude, team, comms, environment.",
                                   color: ZDDesign.signalRed)
                }
                NavigationLink { TacticalQueryParserView() } label: {
                    OpsSectionCard(icon: "text.magnifyingglass", title: "Query Parser",
                                   subtitle: "Natural language → structured action intent. Maps to ZeroDark tools.",
                                   color: .purple)
                }
                NavigationLink { DecisionLogView() } label: {
                    OpsSectionCard(icon: "brain", title: "Decision Log",
                                   subtitle: "AI decision audit trail — reasoning, inputs, confidence, outcomes.",
                                   color: ZDDesign.mediumGray)
                }
                NavigationLink { ModelPerformanceView() } label: {
                    OpsSectionCard(icon: "gauge.with.dots.needle.50percent", title: "Model Monitor",
                                   subtitle: "On-device inference latency, memory, throughput. Tradeoff advisor.",
                                   color: .orange)
                }
                NavigationLink { KnowledgeBaseView() } label: {
                    OpsSectionCard(icon: "text.book.closed.fill", title: "Knowledge Base",
                                   subtitle: "BM25 search across field manuals: first aid, navigation, shelter, water.",
                                   color: ZDDesign.forestGreen)
                }

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
