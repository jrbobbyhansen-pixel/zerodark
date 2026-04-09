// MedicalSection.swift — Medical tools hub within Ops tab
// NavigationLinks to all medical features

import SwiftUI

struct MedicalSection: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                MedicalCard(
                    title: "START Triage",
                    subtitle: "Interactive triage algorithm with casualty tracking",
                    icon: "stethoscope",
                    color: .red,
                    destination: TriageView()
                )

                MedicalCard(
                    title: "9-Line MEDEVAC",
                    subtitle: "NATO MEDEVAC request — auto-fills location and callsign",
                    icon: "cross.circle.fill",
                    color: .red,
                    destination: MedevacView()
                )

                MedicalCard(
                    title: "Vital Signs Logger",
                    subtitle: "Track vitals with deterioration alerts",
                    icon: "heart.text.square.fill",
                    color: ZDDesign.cyanAccent,
                    destination: VitalSignsLoggerView()
                )

                MedicalCard(
                    title: "Medication Tracker",
                    subtitle: "Drug interactions and allergy checks",
                    icon: "pills.fill",
                    color: .orange,
                    destination: MedicationTrackerView()
                )

                MedicalCard(
                    title: "Burn Calculator",
                    subtitle: "Rule of Nines / Lund-Browder + Parkland formula",
                    icon: "flame.fill",
                    color: .orange,
                    destination: BurnCalculatorView()
                )

                MedicalCard(
                    title: "Tourniquet Timer",
                    subtitle: "Multi-tourniquet tracking with 2hr alerts",
                    icon: "bandage.fill",
                    color: ZDDesign.signalRed,
                    destination: TourniquetTimerView()
                )

                MedicalCard(
                    title: "Patient Handoff (SBAR)",
                    subtitle: "Situation-Background-Assessment-Recommendation",
                    icon: "person.text.rectangle.fill",
                    color: .blue,
                    destination: PatientHandoffView()
                )

                MedicalCard(
                    title: "Hypothermia Calculator",
                    subtitle: "Swiss staging + wind chill assessment",
                    icon: "thermometer.snowflake",
                    color: .cyan,
                    destination: Text("Hypothermia Calculator — Coming Soon").padding()
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// MARK: - Medical Card

private struct MedicalCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(12)
        }
    }
}

#Preview {
    NavigationStack { MedicalSection() }
}
