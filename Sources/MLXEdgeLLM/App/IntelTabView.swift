// IntelTabView.swift — Intel Brain: Hybrid RAG + Threat Fusion + Verify Pipeline
// ZeroDark Intel Tab v6.0

import SwiftUI
import PhotosUI

struct IntelTabView: View {
    @State private var intelMode: IntelMode = .knowledge
    @State private var showGeoPackageImport = false

    enum IntelMode: String, CaseIterable {
        case dashboard = "Dashboard"
        case knowledge = "Field Manual"
        case vision = "Visual Intel"
        case library = "Library"
        case threats = "Threats"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $intelMode) {
                    ForEach(IntelMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch intelMode {
                case .dashboard:
                    IntelDashboardView()
                case .knowledge:
                    KnowledgeContentView()
                case .vision:
                    VisionContentView()
                case .library:
                    FastLibraryView()
                case .threats:
                    ThreatFeedView()
                }
            }
            .navigationTitle("Intel")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if intelMode == .knowledge {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(KnowledgeContentView.inferenceStatusColor)
                                .frame(width: 8, height: 8)
                            Text(KnowledgeContentView.inferenceStatusLabel)
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    } else if intelMode == .vision {
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.caption)
                                .foregroundColor(VisionContentView.visionStatusColor)
                            Text(VisionContentView.visionStatusLabel)
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    } else {
                        EmptyView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGeoPackageImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .background(ZDDesign.darkBackground)
            .sheet(isPresented: $showGeoPackageImport) {
                GeoPackageImportView()
            }
        }
    }
}

// MARK: - Intel Dashboard (v6 — Threat Score Gauge + Status)

struct IntelDashboardView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var analyzer = ThreatAnalyzer.shared
    @StateObject private var corpus = IntelCorpus.shared
    @StateObject private var embeddingEngine = MLXEmbeddingEngine.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Threat Score Gauge
                threatScoreGauge

                // Status Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statusCard(
                        icon: "brain",
                        title: "Corpus",
                        value: "\(corpus.totalDocuments)",
                        subtitle: corpus.isReady ? "Indexed" : "Building...",
                        color: corpus.isReady ? ZDDesign.successGreen : ZDDesign.safetyYellow
                    )
                    statusCard(
                        icon: "cpu",
                        title: "MLX Server",
                        value: embeddingEngine.isReady ? "Online" : "Offline",
                        subtitle: "127.0.0.1:8800",
                        color: embeddingEngine.isReady ? ZDDesign.successGreen : ZDDesign.signalRed
                    )
                    statusCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Active Threats",
                        value: "\(appState.activeThreatCount)",
                        subtitle: appState.currentThreatLevel.description,
                        color: threatLevelColor(appState.currentThreatLevel)
                    )
                    statusCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Intel Updates",
                        value: "\(appState.intelUpdateCount)",
                        subtitle: "This session",
                        color: ZDDesign.skyBlue
                    )
                }
                .padding(.horizontal)

                // Threat Breakdown
                if let breakdown = analyzer.threatScoreBreakdown {
                    threatBreakdownView(breakdown)
                }

                // Latest Intel Summary
                if !appState.latestIntelSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest Intel")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ZDDesign.cyanAccent)
                        Text(appState.latestIntelSummary)
                            .font(.caption)
                            .foregroundColor(ZDDesign.pureWhite)
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(ZDDesign.darkSage.opacity(0.2))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private var threatScoreGauge: some View {
        let score = appState.currentThreatScore
        let color = scoreColor(score)

        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ZDDesign.darkSage.opacity(0.3), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(score / 10.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: score)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                    Text("THREAT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }

            Text(appState.currentThreatLevel.description)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func threatBreakdownView(_ breakdown: ThreatAnalyzer.ThreatScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Threat Breakdown")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(ZDDesign.cyanAccent)

            breakdownRow("Environmental", score: breakdown.environmentalScore, color: ZDDesign.darkSage)
            breakdownRow("Structural", score: breakdown.structuralScore, color: ZDDesign.earthBrown)
            breakdownRow("Human", score: breakdown.humanScore, color: ZDDesign.signalRed)
            breakdownRow("Temporal", score: breakdown.temporalScore, color: ZDDesign.skyBlue)
            breakdownRow("Network Intel", score: breakdown.networkIntelScore, color: ZDDesign.cyanAccent)
            breakdownRow("LiDAR Cover", score: breakdown.lidarCoverScore, color: ZDDesign.successGreen)
        }
        .padding()
        .background(ZDDesign.darkSage.opacity(0.2))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func breakdownRow(_ label: String, score: Double, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ZDDesign.darkSage.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score / 10.0), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            Text(String(format: "%.1f", score))
                .font(.caption2)
                .foregroundColor(ZDDesign.pureWhite)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func statusCard(icon: String, title: String, value: String,
                            subtitle: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
                .foregroundColor(ZDDesign.pureWhite)
            Text(title)
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(ZDDesign.darkSage.opacity(0.2))
        .cornerRadius(12)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0..<2:   return ZDDesign.successGreen
        case 2..<4:   return ZDDesign.skyBlue
        case 4..<6:   return ZDDesign.safetyYellow
        case 6..<8:   return ZDDesign.warningOrange
        default:      return ZDDesign.signalRed
        }
    }

    private func threatLevelColor(_ level: ThreatLevel) -> Color {
        switch level {
        case .none:     return ZDDesign.successGreen
        case .low:      return ZDDesign.skyBlue
        case .medium:   return ZDDesign.safetyYellow
        case .high:     return ZDDesign.warningOrange
        case .critical: return ZDDesign.signalRed
        }
    }
}

// MARK: - Knowledge Content View (v6 — Hybrid Search + Verify)

struct KnowledgeContentView: View {
    @StateObject private var rag = KnowledgeRAG.shared
    @StateObject private var corpus = IntelCorpus.shared
    @StateObject private var inference = TextInferenceClient.shared
    @StateObject private var engine = LocalInferenceEngine.shared
    @StateObject private var protocolDB = ProtocolDatabase.shared
    private let verifyPipeline = VerifyPipeline.shared
    @State private var mode: KnowledgeMode = .ask
    @State private var searchQuery = ""
    @State private var userQuestion = ""
    @State private var messages: [IntelMessage] = []
    @State private var isLoading = false
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var fontSize: CGFloat = 14
    @State private var matchedProtocol: TacticalProtocol? = nil

    struct IntelMessage: Identifiable {
        let id = UUID()
        let role: String
        let content: String
        var verification: IntelVerificationResult?
        var sources: [IntelSearchResult]?
    }

    enum KnowledgeMode { case ask, browse }

    static var inferenceStatusColor: Color {
        let engine = LocalInferenceEngine.shared
        switch engine.modelState {
        case .ready:    return ZDDesign.successGreen
        case .loading:  return ZDDesign.safetyYellow
        case .notLoaded: return TextInferenceClient.shared.isConnected ? ZDDesign.skyBlue : ZDDesign.mediumGray
        case .error:    return ZDDesign.signalRed
        }
    }

    static var inferenceStatusLabel: String {
        let engine = LocalInferenceEngine.shared
        switch engine.modelState {
        case .ready:    return "On-Device"
        case .loading:  return "Loading..."
        case .notLoaded: return TextInferenceClient.shared.isConnected ? "Server" : "Search Only"
        case .error:    return "Model Error"
        }
    }

    let quickPrompts = [
        "Sucking chest wound",
        "Tourniquet",
        "CPR",
        "Severe bleeding",
        "Observation post setup",
        "Find water",
        "Start fire",
        "Emergency shelter",
        "React to contact",
        "Being followed"
    ]

    var body: some View {
        ZStack {
            switch mode {
            case .ask:
                askModeView
            case .browse:
                browseModeView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $mode) {
                    Text("Ask").tag(KnowledgeMode.ask)
                    Text("Browse").tag(KnowledgeMode.browse)
                }
                .pickerStyle(.segmented)
            }
        }
        .sheet(item: $matchedProtocol) { proto in
            NavigationStack {
                ScrollView {
                    ProtocolCardView(proto: proto)
                        .padding()
                }
                .navigationTitle(proto.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            matchedProtocol = nil
                        }
                    }
                }
                .background(ZDDesign.darkBackground)
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var askModeView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 16) {
                                Text("Intel Search")
                                    .font(.headline)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Text("Hybrid AI search across all intelligence sources")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.mediumGray)

                                // Index status
                                if corpus.isReady {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(ZDDesign.successGreen)
                                        Text("\(corpus.totalDocuments) documents indexed")
                                            .font(.caption2)
                                            .foregroundColor(ZDDesign.mediumGray)
                                    }
                                } else if corpus.isIndexing {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .tint(ZDDesign.safetyYellow)
                                            .scaleEffect(0.7)
                                        Text("Indexing corpus...")
                                            .font(.caption2)
                                            .foregroundColor(ZDDesign.safetyYellow)
                                    }
                                }

                                Divider()
                                VStack(spacing: 8) {
                                    ForEach(quickPrompts, id: \.self) { prompt in
                                        Button(action: { askQuestion(prompt) }) {
                                            Text(prompt)
                                                .font(.caption)
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(ZDDesign.darkSage.opacity(0.3))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .padding()
                        } else {
                            ForEach(messages) { msg in
                                MessageBubbleView(message: msg)
                                    .id(msg.id)
                            }
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .tint(ZDDesign.skyBlue)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.mediumGray)
                                    Spacer()
                                }
                                .padding()
                            }
                        }
                    }
                    .padding(.vertical)
                    .onChange(of: messages.count) {
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId)
                            }
                        }
                    }
                }
                if case .loading = engine.modelState {
                    ProgressView(value: engine.loadProgress)
                        .tint(ZDDesign.safetyYellow)
                        .padding(.horizontal)
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask a question...", text: $userQuestion)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)
                Button(action: {
                    if !userQuestion.isEmpty { askQuestion(userQuestion); userQuestion = "" }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .foregroundColor(ZDDesign.successGreen)
                }
                .disabled(isLoading || userQuestion.isEmpty)
                if isLoading {
                    Button(action: { streamTask?.cancel(); isLoading = false }) {
                        Image(systemName: "stop.fill")
                            .font(.body)
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var browseModeView: some View {
        VStack(spacing: 12) {
            TextField("Search knowledge...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding()

            if searchQuery.isEmpty {
                browseCategories
            } else {
                browseSearchResults
            }
        }
    }

    @ViewBuilder
    private var browseCategories: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                ForEach(KnowledgeCategory.allCases) { category in
                    browseCategoryCard(category)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func browseCategoryCard(_ category: KnowledgeCategory) -> some View {
        let count = rag.chunks(for: category).count
        NavigationLink(destination: categoryDetailView(category)) {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundColor(category.zdColor)
                Text(category.rawValue)
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(ZDDesign.darkSage.opacity(0.3))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var browseSearchResults: some View {
        let results = rag.search(query: searchQuery, topK: 10)
        List {
            ForEach(results) { chunk in
                NavigationLink(destination: chunkDetailView(chunk)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chunk.title)
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)
                        Text(chunk.summary)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Image(systemName: chunk.category.icon)
                                .font(.caption)
                                .foregroundColor(chunk.category.zdColor)
                            Text(chunk.category.rawValue)
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func categoryDetailView(_ category: KnowledgeCategory) -> some View {
        let categoryChunks = rag.chunks(for: category)
        List {
            ForEach(categoryChunks) { chunk in
                NavigationLink(destination: chunkDetailView(chunk)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chunk.title)
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)
                        Text(chunk.summary)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                            .lineLimit(2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.rawValue)
    }

    @ViewBuilder
    private func chunkDetailView(_ chunk: KnowledgeChunk) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(chunk.title)
                    .font(.headline)
                    .foregroundColor(ZDDesign.pureWhite)
                Divider()
                Text(chunk.content)
                    .font(.system(size: fontSize))
                    .lineSpacing(4)
                Spacer()
            }
            .padding()
        }
        .navigationTitle(chunk.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { fontSize = max(10, fontSize - 2) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(ZDDesign.skyBlue)
                    }
                    Button(action: { fontSize = min(20, fontSize + 2) }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(ZDDesign.skyBlue)
                    }
                }
            }
        }
    }

    // MARK: - Ask Question (v6 — Hybrid Search + Verify Pipeline)

    private func askQuestion(_ question: String) {
        messages.append(IntelMessage(role: "user", content: question))

        // LAYER 1: Instant Protocol Match (<100ms)
        if let proto = protocolDB.quickMatch(query: question) {
            matchedProtocol = proto
            messages.append(IntelMessage(role: "assistant", content: "PROTOCOL MATCHED — Tap to view full card"))
            return
        }

        // LAYER 2: Hybrid Multi-Modal RAG Search (<500ms)
        isLoading = true
        streamTask = Task {
            let results = await corpus.search(query: question, topK: 5)

            if !results.isEmpty {
                let answer = results.map { result in
                    "**\(result.title)** _(\(result.sourceLabel))_\n\(result.content)"
                }.joined(separator: "\n\n---\n\n")

                // Verify the answer
                let verification = verifyPipeline.verify(
                    response: answer, query: question, sourceResults: results
                )

                await MainActor.run {
                    messages.append(IntelMessage(
                        role: "assistant",
                        content: answer,
                        verification: verification,
                        sources: results
                    ))
                    isLoading = false

                    // Post intel event
                    AppState.shared.postIntelEvent(.newSearchResult(query: question, resultCount: results.count))
                    AppState.shared.updateIntelSummary(String(answer.prefix(200)))
                }
                return
            }

            // LAYER 3: AI Synthesis (5-10s) — Only if no RAG match
            do {
                let context = await corpus.buildContext(for: question)
                let stream = try await inference.ask(question: question, context: context)
                await MainActor.run {
                    messages.append(IntelMessage(role: "assistant", content: ""))
                }
                var fullResponse = ""
                for try await chunk in stream {
                    fullResponse += chunk
                    await MainActor.run {
                        if let lastIndex = messages.indices.last,
                           messages[lastIndex].role == "assistant" {
                            messages[lastIndex] = IntelMessage(
                                role: "assistant",
                                content: fullResponse
                            )
                        }
                    }
                }

                // Post-stream verify
                let ragResults = await corpus.search(query: question, topK: 3)
                let verification = verifyPipeline.verify(
                    response: fullResponse, query: question, sourceResults: ragResults
                )
                await MainActor.run {
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex] = IntelMessage(
                            role: "assistant",
                            content: fullResponse,
                            verification: verification,
                            sources: ragResults
                        )
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(IntelMessage(
                        role: "assistant",
                        content: "No information found. Try rephrasing your question."
                    ))
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Message Bubble with Verification Badge

struct MessageBubbleView: View {
    let message: KnowledgeContentView.IntelMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(message.content)
                        .font(.body)
                        .padding(10)
                        .background(ZDDesign.skyBlue.opacity(0.7))
                        .cornerRadius(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .font(.body)
                        .padding(10)
                        .background(ZDDesign.darkSage.opacity(0.3))
                        .cornerRadius(8)

                    // Verification badge
                    if let verification = message.verification {
                        HStack(spacing: 4) {
                            Image(systemName: verificationIcon(verification))
                                .font(.caption2)
                                .foregroundColor(verificationColor(verification))
                            Text(verificationLabel(verification))
                                .font(.caption2)
                                .foregroundColor(verificationColor(verification))

                            if let disclaimer = verification.suggestedDisclaimer {
                                Text("— \(disclaimer)")
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    // Source attribution badges
                    if let sources = message.sources, !sources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sources) { result in
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 9))
                                        Text(result.sourceLabel)
                                            .font(.system(size: 9))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(ZDDesign.cyanAccent.opacity(0.2))
                                    .foregroundColor(ZDDesign.cyanAccent)
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private func verificationIcon(_ v: IntelVerificationResult) -> String {
        if v.isVerified && v.confidence > 0.8 { return "checkmark.shield.fill" }
        if v.confidence > 0.5 { return "exclamationmark.shield.fill" }
        return "xmark.shield.fill"
    }

    private func verificationColor(_ v: IntelVerificationResult) -> Color {
        if v.isVerified && v.confidence > 0.8 { return ZDDesign.successGreen }
        if v.confidence > 0.5 { return ZDDesign.safetyYellow }
        return ZDDesign.signalRed
    }

    private func verificationLabel(_ v: IntelVerificationResult) -> String {
        if v.isVerified && v.confidence > 0.8 { return "Verified (\(Int(v.confidence * 100))%)" }
        if v.confidence > 0.5 { return "Partial (\(Int(v.confidence * 100))%)" }
        return "Unverified"
    }
}

// MARK: - Vision Content View (v6 — Auto-ingest to IntelCorpus)

struct VisionContentView: View {
    @StateObject private var rag = KnowledgeRAG.shared
    @StateObject private var vision = VisionInferenceClient.shared
    @StateObject private var corpus = IntelCorpus.shared
    @State private var selectedImage: UIImage? = nil
    @State private var selectedMode: VisionMode = .plantId
    @State private var showImagePicker = false
    @State private var answer = ""
    @State private var isAnalyzing = false
    @State private var customQuestion = ""

    enum VisionMode: String, CaseIterable {
        case plantId = "Plant ID"
        case wound = "Wound"
        case terrain = "Terrain"
        case map = "Map"
        case ask = "Ask"

        var question: String {
            switch self {
            case .plantId:
                return "Identify this plant. Is it edible or toxic? What are the identifying features and any lookalikes?"
            case .wound:
                return "Assess this wound. What type is it? What immediate field treatment is required? What are warning signs of complications?"
            case .terrain:
                return "Analyze this terrain. Where is cover, concealment, high ground, and likely avenues of approach or escape?"
            case .map:
                return "Analyze this map or document. What key information does it contain?"
            case .ask:
                return "Describe what you see and analyze it."
            }
        }
    }

    static var visionStatusColor: Color {
        VisionInferenceClient.shared.isConnected ? ZDDesign.successGreen : ZDDesign.warmGray
    }

    static var visionStatusLabel: String {
        VisionInferenceClient.shared.isConnected ? "moondream2" : "Offline"
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisionMode.allCases, id: \.self) { mode in
                        Button(action: { selectedMode = mode; answer = "" }) {
                            Text(mode.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedMode == mode ? ZDDesign.skyBlue : ZDDesign.darkSage.opacity(0.5))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal)
            }

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .cornerRadius(8)
                    .clipped()
                    .padding(.horizontal)
            } else {
                Button(action: { showImagePicker = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.title)
                            .foregroundColor(ZDDesign.skyBlue)
                        Text("Tap to capture or select image")
                            .font(.body)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(ZDDesign.darkSage.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }

            if selectedMode == .ask {
                TextField("Describe what to look for...", text: $customQuestion)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
            }

            Button(action: analyzeImage) {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .tint(ZDDesign.safetyYellow)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Analyzing..." : "Analyze")
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(
                    vision.isConnected && selectedImage != nil
                        ? ZDDesign.safetyYellow
                        : ZDDesign.warmGray.opacity(0.5)
                )
                .foregroundColor(.black)
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .disabled(!vision.isConnected || selectedImage == nil || isAnalyzing)

            if !vision.isConnected && selectedImage != nil {
                Text("Vision server not available at \(vision.serverURL)")
                    .font(.caption)
                    .foregroundColor(ZDDesign.signalRed)
                    .padding(.horizontal)
            }

            if !answer.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Analysis")
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)
                        Divider()
                        Text(answer)
                            .font(.body)
                            .lineSpacing(4)
                        Divider()
                        Text("Related Knowledge")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                        let ragChunks = rag.search(query: answer, topK: 3)
                        ForEach(ragChunks) { chunk in
                            NavigationLink(destination: knowledgeDetailView(chunk)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chunk.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(chunk.category.zdColor)
                                    Text(chunk.summary)
                                        .font(.caption2)
                                        .foregroundColor(ZDDesign.mediumGray)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkSage.opacity(0.2))
                    .cornerRadius(8)
                    .padding()
                }
            }

            Spacer()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(selectedImage: $selectedImage)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedImage != nil {
                    Button(action: { selectedImage = nil; answer = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }
            }
        }
    }

    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        answer = ""
        let question = selectedMode == .ask && !customQuestion.isEmpty ? customQuestion : selectedMode.question
        Task {
            do {
                let result = try await vision.query(image: image, question: question)
                await MainActor.run {
                    answer = result
                    isAnalyzing = false
                }
                // v6: Auto-ingest analysis into IntelCorpus
                await corpus.ingestPhotoAnalysis(
                    photoId: UUID(),
                    analysisText: result,
                    metadata: [
                        "mode": selectedMode.rawValue,
                        "question": question
                    ]
                )
            } catch {
                await MainActor.run {
                    answer = "Error analyzing image: \(error.localizedDescription)"
                    isAnalyzing = false
                }
            }
        }
    }

    @ViewBuilder
    private func knowledgeDetailView(_ chunk: KnowledgeChunk) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(chunk.title)
                    .font(.headline)
                    .foregroundColor(ZDDesign.pureWhite)
                Divider()
                Text(chunk.content)
                    .font(.body)
                    .lineSpacing(4)
                Spacer()
            }
            .padding()
        }
        .navigationTitle(chunk.title)
    }
}

// MARK: - Image Picker

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss: DismissAction

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    IntelTabView()
}
