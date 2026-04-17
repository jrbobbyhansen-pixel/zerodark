// OpSecSection.swift — Ops > OpSec sub-section
// Operational security training modules

import SwiftUI

// MARK: - Training Module Model

struct OpSecModule: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let description: String
    let estimatedMinutes: Int
    let lessons: [OpSecLesson]
}

struct OpSecLesson: Identifiable {
    let id: String
    let title: String
    let content: [String]
    let keyTakeaways: [String]
}

// MARK: - OpSec Section View

struct OpSecSection: View {
    @AppStorage("opsec_completed") private var completedLessonsData: Data = Data()
    @ObservedObject private var relay = MeshRelay.shared
    @ObservedObject private var geofences = GeofenceManager.shared

    private var completedLessonIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: completedLessonsData)) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                // Geofence Deny Status (v6.2)
                geofenceDenyCard

                progressCard

                OpsSectionHeader(icon: "lock.shield.fill", title: "TRAINING MODULES", color: ZDDesign.cyanAccent)

                ForEach(modules) { module in
                    NavigationLink {
                        OpSecModuleDetailView(
                            module: module,
                            completedLessonsData: $completedLessonsData
                        )
                    } label: {
                        moduleCard(module)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Geofence Deny Card (v6.2)

    private var geofenceDenyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(relay.deniedPeerIDs.isEmpty ? ZDDesign.successGreen : ZDDesign.signalRed)
                Text("GEOFENCE ENFORCEMENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Circle()
                    .fill(relay.deniedPeerIDs.isEmpty ? ZDDesign.successGreen : ZDDesign.signalRed)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 20) {
                VStack {
                    Text("\(geofences.geofences.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.pureWhite)
                    Text("Zones")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Divider().frame(height: 30).background(ZDDesign.mediumGray)

                VStack {
                    Text("\(relay.deniedPeerIDs.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(relay.deniedPeerIDs.isEmpty ? ZDDesign.successGreen : ZDDesign.signalRed)
                    Text("Denied")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Divider().frame(height: 30).background(ZDDesign.mediumGray)

                VStack {
                    Text("\(relay.relayedPeers.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("Relayed")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }

            if geofences.geofences.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(ZDDesign.safetyYellow)
                    Text("No geofences configured — all peers allowed")
                        .font(.caption)
                        .foregroundColor(ZDDesign.safetyYellow)
                }
            }

            NavigationLink {
                GeofenceEditorView()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Manage Geofences")
                        .font(.caption)
                }
                .foregroundColor(ZDDesign.cyanAccent)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("OPSEC READINESS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Text("\(completedCount)/\(totalLessons)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.cyanAccent)
            }

            ProgressView(value: Double(completedCount), total: Double(max(totalLessons, 1)))
                .tint(completedCount == totalLessons ? ZDDesign.successGreen : ZDDesign.cyanAccent)

            if completedCount == totalLessons && totalLessons > 0 {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(ZDDesign.successGreen)
                    Text("All modules complete")
                        .font(.caption)
                        .foregroundColor(ZDDesign.successGreen)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Module Card

    private func moduleCard(_ module: OpSecModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.title2)
                .foregroundColor(module.color)
                .frame(width: 40, height: 40)
                .background(module.color.opacity(0.15))
                .cornerRadius(ZDDesign.radiusSmall)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ZDDesign.pureWhite)
                Text(module.description)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(module.estimatedMinutes) min", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                    Label("\(module.lessons.count) lessons", systemImage: "book")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)

                    let done = module.lessons.filter { completedLessonIDs.contains($0.id) }.count
                    if done == module.lessons.count {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(ZDDesign.successGreen)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Computed

    private var completedCount: Int { completedLessonIDs.count }
    private var totalLessons: Int { modules.flatMap(\.lessons).count }

    // MARK: - Module Data (stable IDs)

    private var modules: [OpSecModule] {
        [
            OpSecModule(
                id: "comsec",
                title: "COMSEC Fundamentals",
                icon: "lock.fill",
                color: ZDDesign.cyanAccent,
                description: "Encryption standards, key management & secure channel discipline",
                estimatedMinutes: 15,
                lessons: [
                    OpSecLesson(
                        id: "comsec-encryption",
                        title: "Encryption & Key Management",
                        content: [
                            "All ZeroDark mesh communications use AES-256-GCM encryption with per-session keys generated via ECDH key exchange.",
                            "Key rotation occurs automatically every 4 hours. Manual rotation can be triggered from mesh settings. Never downgrade to weaker encryption.",
                            "If mesh encryption is unavailable, use pre-shared codebooks or one-time pads. Never transmit sensitive information in the clear."
                        ],
                        keyTakeaways: [
                            "AES-256-GCM is the standard — never downgrade",
                            "Session keys auto-rotate every 4 hours",
                            "Assume all RF transmissions can be intercepted"
                        ]
                    ),
                    OpSecLesson(
                        id: "comsec-discipline",
                        title: "Secure Channel Discipline",
                        content: [
                            "Use PTT brevity codes for routine comms. Reserve full voice for urgent traffic only — shorter transmissions mean less intercept exposure.",
                            "DTN (Delay Tolerant Networking) queues messages when peers are temporarily unreachable. Messages are encrypted at rest in the DTN buffer.",
                            "Establish comms windows: pre-arranged time slots for check-ins reduce continuous RF emission and make pattern analysis harder for adversaries."
                        ],
                        keyTakeaways: [
                            "PTT brevity reduces intercept exposure",
                            "DTN messages are encrypted at rest",
                            "Pre-arranged comms windows > continuous broadcasting"
                        ]
                    )
                ]
            ),
            OpSecModule(
                id: "opsec-5step",
                title: "OPSEC 5-Step Process",
                icon: "eye.slash.fill",
                color: ZDDesign.safetyYellow,
                description: "Identify critical info, analyze threats, assess vulnerabilities, apply countermeasures",
                estimatedMinutes: 20,
                lessons: [
                    OpSecLesson(
                        id: "opsec-identify-analyze",
                        title: "Step 1-2: Identify & Analyze",
                        content: [
                            "Step 1 — Identify Critical Information: What data, if exposed, would compromise the mission? Team locations, movement plans, comms frequencies, personnel identities.",
                            "Step 2 — Analyze Threats: Who is collecting against you? What capabilities do they have? RF intercept, visual surveillance, social engineering, cyber intrusion."
                        ],
                        keyTakeaways: [
                            "Critical info = anything that enables adversary action",
                            "Threat analysis drives countermeasure selection",
                            "Assume sophisticated adversary capabilities"
                        ]
                    ),
                    OpSecLesson(
                        id: "opsec-vuln-risk-counter",
                        title: "Step 3-5: Vulnerabilities, Risk, Countermeasures",
                        content: [
                            "Step 3 — Assess Vulnerabilities: Where do your procedures leak critical info? Unencrypted comms, predictable movement patterns, social media exposure.",
                            "Step 4 — Assess Risk: What is the likelihood and impact of each vulnerability being exploited?",
                            "Step 5 — Apply Countermeasures: Encryption, route randomization, communications discipline, device hardening, personnel awareness."
                        ],
                        keyTakeaways: [
                            "Every procedure has potential leaks — find them",
                            "Risk = likelihood x impact",
                            "Countermeasures must be practical and sustainable"
                        ]
                    )
                ]
            ),
            OpSecModule(
                id: "social-engineering",
                title: "Social Engineering Defense",
                icon: "person.badge.shield.checkmark.fill",
                color: ZDDesign.signalRed,
                description: "Recognize manipulation, pretexting, elicitation & phishing attempts",
                estimatedMinutes: 15,
                lessons: [
                    OpSecLesson(
                        id: "soceng-recognition",
                        title: "Recognition & Response",
                        content: [
                            "Social engineering exploits human psychology — authority, urgency, reciprocity, social proof. Recognize these pressure tactics.",
                            "Common vectors: unexpected requests for credentials, urgent 'emergency' scenarios requiring immediate action, strangers seeking operational details through casual conversation.",
                            "Response protocol: Verify identity through a separate channel. Never share credentials, locations, or team details with unverified contacts. Report all suspicious approaches."
                        ],
                        keyTakeaways: [
                            "If it feels urgent and unexpected — pause and verify",
                            "Never share credentials through any channel",
                            "Report all suspicious contacts immediately"
                        ]
                    )
                ]
            ),
            OpSecModule(
                id: "device-hardening",
                title: "Device Hardening",
                icon: "iphone.gen3.radiowaves.left.and.right.circle.fill",
                color: ZDDesign.forestGreen,
                description: "Secure mobile devices, manage permissions, minimize attack surface",
                estimatedMinutes: 15,
                lessons: [
                    OpSecLesson(
                        id: "device-checklist",
                        title: "Mobile Security Checklist",
                        content: [
                            "Enable full-disk encryption (default on iOS). Use a strong alphanumeric passcode — not just a 4-digit PIN.",
                            "Disable unnecessary radios: WiFi auto-join, Bluetooth discovery, AirDrop when not in use. Each active radio is a potential tracking vector.",
                            "Review app permissions regularly. ZeroDark requires camera, location, and local network — deny everything else. Disable location sharing for non-essential apps."
                        ],
                        keyTakeaways: [
                            "Strong passcode + full-disk encryption = baseline",
                            "Every active radio = potential tracking vector",
                            "Minimize app permissions to operational minimum"
                        ]
                    )
                ]
            ),
            OpSecModule(
                id: "rf-mesh-security",
                title: "RF & Mesh Security",
                icon: "antenna.radiowaves.left.and.right",
                color: ZDDesign.darkSage,
                description: "Emissions control, mesh trust verification & rogue node detection",
                estimatedMinutes: 15,
                lessons: [
                    OpSecLesson(
                        id: "rf-emcon",
                        title: "Emissions Control (EMCON)",
                        content: [
                            "Radio frequency emissions can be detected, located, and intercepted. Practice EMCON — minimize transmit time, use directional antennas when possible.",
                            "Haptic codes provide a zero-RF-emission alternative for close-proximity tactical signals. Use them during sensitive phases instead of voice or text.",
                            "Maintain radio silence during movement to objectives. Use pre-arranged time windows for check-ins. Never transmit locations in the clear."
                        ],
                        keyTakeaways: [
                            "All RF emissions are detectable — minimize them",
                            "Haptic codes = invisible to RF intercept",
                            "Radio silence during sensitive phases is non-negotiable"
                        ]
                    ),
                    OpSecLesson(
                        id: "rf-mesh-trust",
                        title: "Mesh Trust & Rogue Detection",
                        content: [
                            "Always verify new peers through a separate channel before sharing sensitive traffic. The mesh encrypts data in transit but cannot verify identity alone.",
                            "Use the trusted devices feature to whitelist known team members. Untrusted peers can relay traffic but should not receive operational data.",
                            "Monitor for unexpected peers joining your network. Use the tactical scanner to detect rogue nodes. An unknown device on your mesh is a threat until verified."
                        ],
                        keyTakeaways: [
                            "Verify new peers through a separate channel",
                            "Trusted device list = your security perimeter",
                            "Unknown peer on mesh = threat until verified"
                        ]
                    )
                ]
            ),
            OpSecModule(
                id: "personnel-security",
                title: "Personnel Security",
                icon: "person.badge.key.fill",
                color: .orange,
                description: "Need-to-know principle, information compartmentalization, team vetting",
                estimatedMinutes: 10,
                lessons: [
                    OpSecLesson(
                        id: "persec-compartment",
                        title: "Information Compartmentalization",
                        content: [
                            "Apply need-to-know: team members should only have access to information required for their specific role and current task.",
                            "Brief personnel on exactly what they need — no more. Debrief after operations to identify any information leakage.",
                            "Establish clear protocols for handling sensitive materials: mission plans, maps with marked positions, frequency lists, personnel rosters."
                        ],
                        keyTakeaways: [
                            "Need-to-know is not optional — it's operational discipline",
                            "Debrief after every operation",
                            "Sensitive materials have handling protocols"
                        ]
                    )
                ]
            )
        ]
    }
}

// MARK: - Module Detail View

struct OpSecModuleDetailView: View {
    let module: OpSecModule
    @Binding var completedLessonsData: Data
    @Environment(\.dismiss) private var dismiss: DismissAction

    private var completedLessonIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: completedLessonsData)) ?? []
    }

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: ZDDesign.spacing16) {
                    HStack {
                        Image(systemName: module.icon)
                            .font(.title)
                            .foregroundColor(module.color)
                        VStack(alignment: .leading) {
                            Text(module.title)
                                .font(.headline)
                                .foregroundColor(ZDDesign.pureWhite)
                            Text("\(module.estimatedMinutes) min \u{00B7} \(module.lessons.count) lessons")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(ZDDesign.radiusMedium)

                    ForEach(module.lessons) { lesson in
                        lessonCard(lesson)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lessonCard(_ lesson: OpSecLesson) -> some View {
        let isCompleted = completedLessonIDs.contains(lesson.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lesson.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ZDDesign.pureWhite)
                Spacer()
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ZDDesign.successGreen)
                }
            }

            ForEach(lesson.content, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("KEY TAKEAWAYS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ZDDesign.cyanAccent)

                ForEach(lesson.keyTakeaways, id: \.self) { takeaway in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ZDDesign.cyanAccent)
                        Text(takeaway)
                            .font(.caption)
                            .foregroundColor(ZDDesign.pureWhite.opacity(0.9))
                    }
                }
            }
            .padding(10)
            .background(ZDDesign.cyanAccent.opacity(0.08))
            .cornerRadius(8)

            if !isCompleted {
                Button {
                    markCompleted(lesson.id)
                } label: {
                    Text("Mark Complete")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(ZDDesign.cyanAccent)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    private func markCompleted(_ lessonID: String) {
        var ids = completedLessonIDs
        ids.insert(lessonID)
        completedLessonsData = (try? JSONEncoder().encode(ids)) ?? Data()
    }
}
