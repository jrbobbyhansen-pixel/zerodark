// IntelTabView.swift — Intel Brain: Hybrid RAG + Threat Fusion + Verify Pipeline
// ZeroDark Intel Tab v7.0

import SwiftUI
import PhotosUI

// MARK: - Intel Mode

enum IntelMode: String, CaseIterable {
    case dashboard = "Dashboard"
    case knowledge = "Field Manual"
    case vision    = "Vision"
    case library   = "Docs"
    case threats   = "Threats"

    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .knowledge: return "book.fill"
        case .vision:    return "eye.fill"
        case .library:   return "folder.fill"
        case .threats:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - IntelTabView

struct IntelTabView: View {
    @AppStorage("intel_tab_mode") private var intelMode: IntelMode = .knowledge
    @State private var showGeoPackageImport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Icon + label tab row — 5 equal columns, underline accent
                HStack(spacing: 0) {
                    ForEach(IntelMode.allCases, id: \.self) { mode in
                        Button { intelMode = mode } label: {
                            VStack(spacing: 3) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 18, weight: intelMode == mode ? .semibold : .regular))
                                    .foregroundColor(intelMode == mode ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                                    .accessibilityHidden(true)
                                Text(mode.rawValue)
                                    .font(.system(size: 10, weight: intelMode == mode ? .semibold : .regular))
                                    .foregroundColor(intelMode == mode ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                                Rectangle()
                                    .fill(intelMode == mode ? ZDDesign.cyanAccent : Color.clear)
                                    .frame(height: 2)
                                    .cornerRadius(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(mode.rawValue) tab")
                        .accessibilityAddTraits(intelMode == mode ? [.isButton, .isSelected] : [.isButton])
                    }
                }
                .background(ZDDesign.darkBackground)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.3)
                }

                // Section content
                Group {
                    switch intelMode {
                    case .dashboard:
                        IntelDashboardView(navigate: { intelMode = $0 })
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
                .animation(.easeInOut(duration: 0.15), value: intelMode)
            }
            .navigationTitle("Intel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGeoPackageImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                    .accessibilityLabel("Import GeoPackage")
                }
            }
            .background(ZDDesign.darkBackground)
            .sheet(isPresented: $showGeoPackageImport) {
                GeoPackageImportView()
            }
            .task {
                await IntelCorpus.shared.indexAllSources()
            }
        }
    }
}

// MARK: - Intel Dashboard

struct IntelDashboardView: View {
    var navigate: (IntelMode) -> Void = { _ in }
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var analyzer = ThreatAnalyzer.shared
    @ObservedObject private var corpus = IntelCorpus.shared
    @ObservedObject private var embeddingEngine = MLXEmbeddingEngine.shared
    @State private var summaryExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                threatScoreBar

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button { navigate(.library) } label: {
                        statusCard(
                            icon: "brain",
                            title: "Corpus",
                            value: "\(corpus.totalDocuments)",
                            subtitle: corpus.isReady ? "Indexed" : "Building...",
                            color: corpus.isReady ? ZDDesign.successGreen : ZDDesign.safetyYellow
                        )
                    }
                    .buttonStyle(.plain)

                    statusCard(
                        icon: "cpu",
                        title: "Embedding",
                        value: embeddingEngine.isReady ? "On-Device" : "Loading",
                        subtitle: embeddingEngine.modelName,
                        color: embeddingEngine.isReady ? ZDDesign.successGreen : ZDDesign.safetyYellow
                    )

                    Button { navigate(.threats) } label: {
                        statusCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "Active Threats",
                            value: "\(appState.activeThreatCount)",
                            subtitle: appState.currentThreatLevel.description,
                            color: threatLevelColor(appState.currentThreatLevel)
                        )
                    }
                    .buttonStyle(.plain)

                    statusCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Intel Updates",
                        value: "\(appState.intelUpdateCount)",
                        subtitle: "This session",
                        color: ZDDesign.skyBlue
                    )
                }
                .padding(.horizontal)

                if let breakdown = analyzer.threatScoreBreakdown {
                    threatBreakdownView(breakdown)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No threat data — submit a report or connect to TAK")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZDDesign.darkSage.opacity(0.2))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                if !appState.latestIntelSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest Intel")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ZDDesign.cyanAccent)
                        Text(appState.latestIntelSummary)
                            .font(.footnote)
                            .foregroundColor(ZDDesign.pureWhite)
                            .lineLimit(summaryExpanded ? nil : 3)
                        Button {
                            withAnimation { summaryExpanded.toggle() }
                        } label: {
                            Text(summaryExpanded ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
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
    private var threatScoreBar: some View {
        let score = appState.currentThreatScore
        let color = scoreColor(score)
        VStack(spacing: 8) {
            HStack {
                Text("THREAT LEVEL")
                    .font(.caption2.bold())
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Text(String(format: "%.1f / 10", score))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .animation(.easeInOut(duration: 0.5), value: score)
            }
            Text(appState.currentThreatLevel.description)
                .font(.caption.bold())
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 10)
                    .cornerRadius(5)

                    let x = geo.size.width * CGFloat(min(score / 10.0, 1.0))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ZDDesign.pureWhite)
                        .frame(width: 4, height: 18)
                        .offset(x: max(0, x - 2))
                        .shadow(radius: 2)
                        .animation(.easeInOut(duration: 0.5), value: score)
                }
            }
            .frame(height: 18)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func threatBreakdownView(_ breakdown: ThreatAnalyzer.ThreatScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Threat Breakdown")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(ZDDesign.cyanAccent)

            breakdownRow("Environmental", score: breakdown.environmentalScore, color: ZDDesign.darkSage)
            breakdownRow("Structural",    score: breakdown.structuralScore,    color: ZDDesign.earthBrown)
            breakdownRow("Human",         score: breakdown.humanScore,         color: ZDDesign.signalRed)
            breakdownRow("Temporal",      score: breakdown.temporalScore,      color: ZDDesign.skyBlue)
            breakdownRow("Network Intel", score: breakdown.networkIntelScore,  color: ZDDesign.cyanAccent)
            breakdownRow("LiDAR Cover",   score: breakdown.lidarCoverScore,    color: ZDDesign.successGreen)
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
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ZDDesign.darkSage.opacity(0.3))
                        .frame(height: 10)
                        .cornerRadius(5)
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score / 10.0), height: 10)
                        .cornerRadius(5)
                }
            }
            .frame(height: 10)
            Text(String(format: "%.1f", score))
                .font(.caption)
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

// MARK: - Knowledge Content View

struct KnowledgeContentView: View {
    @ObservedObject private var rag = KnowledgeRAG.shared
    @ObservedObject private var corpus = IntelCorpus.shared
    @ObservedObject private var inference = TextInferenceClient.shared
    @ObservedObject private var engine = LocalInferenceEngine.shared
    @ObservedObject private var protocolDB = ProtocolDatabase.shared
    private let verifyPipeline = VerifyPipeline.shared
    @State private var mode: KnowledgeMode = .ask
    @State private var searchQuery = ""
    @State private var userQuestion = ""
    @State private var messages: [IntelMessage] = []
    @State private var isLoading = false
    @State private var loadingStage = ""
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var fontSize: CGFloat = 14
    @State private var matchedProtocol: TacticalProtocol? = nil
    @State private var selectedPromptCategory = "Medical"

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
        case .ready:     return ZDDesign.successGreen
        case .loading:   return ZDDesign.safetyYellow
        case .notLoaded: return TextInferenceClient.shared.isConnected ? ZDDesign.skyBlue : ZDDesign.mediumGray
        case .error:     return ZDDesign.signalRed
        }
    }

    static var inferenceStatusLabel: String {
        let engine = LocalInferenceEngine.shared
        switch engine.modelState {
        case .ready:     return "On-Device"
        case .loading:   return "Loading..."
        case .notLoaded: return TextInferenceClient.shared.isConnected ? "Server" : "Search Only"
        case .error:     return "Model Error"
        }
    }

    private let promptCategories: [(label: String, icon: String, prompts: [String])] = [
        ("Medical",  "cross.fill",    ["Sucking chest wound", "Tourniquet", "CPR", "Severe bleeding"]),
        ("Survival", "flame.fill",    ["Find water", "Start fire", "Emergency shelter"]),
        ("Tactical", "scope",         ["Observation post setup", "React to contact", "Being followed"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Inline Ask / Browse picker
            Picker("Mode", selection: $mode) {
                Text("Ask").tag(KnowledgeMode.ask)
                Text("Browse").tag(KnowledgeMode.browse)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ZStack {
                switch mode {
                case .ask:   askModeView
                case .browse: browseModeView
                }
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
                        Button("Done") { matchedProtocol = nil }
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
                            emptyAskState
                        } else {
                            ForEach(messages) { msg in
                                MessageBubbleView(message: msg)
                                    .id(msg.id)
                            }
                            if isLoading {
                                HStack {
                                    ProgressView().tint(ZDDesign.skyBlue)
                                    Text(loadingStage.isEmpty ? "Thinking..." : loadingStage)
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

            // Inline inference status
            HStack(spacing: 4) {
                Circle()
                    .fill(KnowledgeContentView.inferenceStatusColor)
                    .frame(width: 6, height: 6)
                Text(KnowledgeContentView.inferenceStatusLabel)
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 2)

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
                .accessibilityLabel("Send Question")
                if isLoading {
                    Button(action: { streamTask?.cancel(); isLoading = false; loadingStage = "" }) {
                        Image(systemName: "stop.fill")
                            .font(.body)
                            .foregroundColor(ZDDesign.signalRed)
                    }
                    .accessibilityLabel("Cancel")
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var emptyAskState: some View {
        VStack(spacing: 16) {
            Text("Intel Search")
                .font(.headline)
                .foregroundColor(ZDDesign.pureWhite)
            Text("Hybrid AI search across all intelligence sources")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)

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
                    ProgressView().tint(ZDDesign.safetyYellow).scaleEffect(0.7)
                    Text("Indexing corpus...")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.safetyYellow)
                }
            }

            Divider()

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(promptCategories, id: \.label) { cat in
                        Button { selectedPromptCategory = cat.label } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                    .font(.caption2)
                                Text(cat.label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedPromptCategory == cat.label ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                            .foregroundColor(selectedPromptCategory == cat.label ? .black : ZDDesign.pureWhite)
                            .cornerRadius(16)
                        }
                    }
                }
            }

            // Filtered prompts — 2-column grid
            if let category = promptCategories.first(where: { $0.label == selectedPromptCategory }) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(category.prompts, id: \.self) { prompt in
                        Button(action: { askQuestion(prompt) }) {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.cyanAccent)
                                Text(prompt)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(ZDDesign.darkSage.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(ZDDesign.pureWhite)
                        }
                    }
                }
            }
        }
        .padding()
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
                    .textSelection(.enabled)
                Spacer()
            }
            .padding()
        }
        .navigationTitle(chunk.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { fontSize = max(10, fontSize - 2) }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(ZDDesign.skyBlue)
                    }
                    .a11yIcon("Decrease font size")
                    Button(action: { fontSize = min(20, fontSize + 2) }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.skyBlue)
                    }
                    .a11yIcon("Increase font size")
                }
            }
        }
    }

    // MARK: - Ask Question

    private func askQuestion(_ question: String) {
        messages.append(IntelMessage(role: "user", content: question))

        // Layer 1: Instant Protocol Match
        loadingStage = "Matching protocol..."
        if let proto = protocolDB.quickMatch(query: question) {
            matchedProtocol = proto
            messages.append(IntelMessage(role: "assistant", content: "PROTOCOL MATCHED — Tap to view full card"))
            loadingStage = ""
            return
        }

        // Layer 2: Hybrid Multi-Modal RAG Search
        isLoading = true
        loadingStage = "Searching corpus..."
        streamTask = Task {
            let results = await corpus.search(query: question, topK: 5)

            if !results.isEmpty {
                let answer = results.map { result in
                    "**\(result.title)** _(\(result.sourceLabel))_\n\(result.content)"
                }.joined(separator: "\n\n---\n\n")

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
                    loadingStage = ""
                    AppState.shared.postIntelEvent(.newSearchResult(query: question, resultCount: results.count))
                    AppState.shared.updateIntelSummary(String(answer.prefix(200)))
                }
                return
            }

            // Layer 3: AI Synthesis
            await MainActor.run { loadingStage = "Asking AI..." }
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
                            messages[lastIndex] = IntelMessage(role: "assistant", content: fullResponse)
                        }
                    }
                }

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
                    loadingStage = ""
                }
            } catch {
                await MainActor.run {
                    messages.append(IntelMessage(
                        role: "assistant",
                        content: "No information found. Try rephrasing your question."
                    ))
                    isLoading = false
                    loadingStage = ""
                }
            }
        }
    }
}

// MARK: - Message Bubble with Verification Badge

struct MessageBubbleView: View {
    let message: KnowledgeContentView.IntelMessage
    @State private var showVerifyInfo = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer()
                Text(message.content)
                    .font(.body)
                    .padding(10)
                    .background(ZDDesign.cyanAccent.opacity(0.4))
                    .cornerRadius(8)
                    .foregroundColor(ZDDesign.pureWhite)
                    .textSelection(.enabled)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .font(.body)
                        .padding(10)
                        .background(ZDDesign.darkSage.opacity(0.3))
                        .cornerRadius(8)
                        .foregroundColor(ZDDesign.pureWhite)
                        .textSelection(.enabled)

                    if let verification = message.verification {
                        Button {
                            showVerifyInfo = true
                        } label: {
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
                        }
                        .padding(.horizontal, 4)
                        .alert("Verification Score", isPresented: $showVerifyInfo) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text("Confidence \(Int(verification.confidence * 100))% — this score reflects how closely the answer matches indexed source documents. Higher scores indicate stronger source backing.")
                        }
                    }

                    if let sources = message.sources, !sources.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sources) { result in
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.text").font(.system(size: 9))
                                        Text(result.sourceLabel).font(.system(size: 9))
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

// MARK: - Vision Content View

struct VisionContentView: View {
    @ObservedObject private var rag = KnowledgeRAG.shared
    @ObservedObject private var vision = OnDeviceVisionEngine.shared
    @ObservedObject private var corpus = IntelCorpus.shared
    @State private var selectedImage: UIImage? = nil
    @State private var selectedMode: OnDeviceVisionMode = .plantId
    @State private var showCameraPicker = false
    @State private var showLibraryPicker = false
    @State private var answer = ""
    @State private var isAnalyzing = false
    @State private var customQuestion = ""
    @State private var analysisTimestamp = Date()

    static var visionStatusColor: Color { ZDDesign.successGreen }
    static var visionStatusLabel: String { OnDeviceVisionEngine.shared.visionStatusLabel }

    var body: some View {
        VStack(spacing: 16) {
            // Mode selector — segmented control
            Picker("Mode", selection: $selectedMode) {
                ForEach(OnDeviceVisionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedMode) { _, _ in answer = "" }

            // Image area
            if let image = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .cornerRadius(8)
                        .clipped()
                }
                .padding(.horizontal)
            } else {
                // Split camera / library buttons
                HStack(spacing: 12) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCameraPicker = true } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundColor(ZDDesign.skyBlue)
                                Text("Camera")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(ZDDesign.darkCard)
                            .cornerRadius(10)
                        }
                    }
                    Button { showLibraryPicker = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundColor(ZDDesign.skyBlue)
                            Text("Library")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(ZDDesign.darkCard)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }

            if selectedMode == .ask {
                TextField("Describe what to look for...", text: $customQuestion)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
            }

            // Inline vision status
            HStack(spacing: 4) {
                Circle()
                    .fill(VisionContentView.visionStatusColor)
                    .frame(width: 6, height: 6)
                Text(VisionContentView.visionStatusLabel)
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
            }
            .padding(.horizontal)

            Button(action: analyzeImage) {
                HStack {
                    if isAnalyzing {
                        ProgressView().tint(ZDDesign.safetyYellow)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isAnalyzing ? "Analyzing..." : "Analyze")
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(selectedImage != nil ? ZDDesign.safetyYellow : ZDDesign.warmGray.opacity(0.5))
                .foregroundColor(.black)
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .disabled(selectedImage == nil || isAnalyzing)

            if !answer.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Metadata header
                        HStack {
                            Label(selectedMode.rawValue, systemImage: selectedMode.icon)
                                .font(.caption.bold())
                                .foregroundColor(ZDDesign.cyanAccent)
                            Spacer()
                            Text(analysisTimestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Divider()
                        Text(answer)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
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
        .sheet(isPresented: $showCameraPicker) {
            ImagePickerView(selectedImage: $selectedImage, sourceType: .camera)
        }
        .sheet(isPresented: $showLibraryPicker) {
            ImagePickerView(selectedImage: $selectedImage, sourceType: .photoLibrary)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedImage != nil {
                    Button(action: { selectedImage = nil; answer = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                    .a11yIcon("Clear selected image")
                }
            }
        }
    }

    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        answer = ""
        let question = selectedMode == .ask && !customQuestion.isEmpty
            ? customQuestion
            : selectedMode.defaultQuestion
        Task {
            do {
                let result = try await vision.query(image: image, question: question, mode: selectedMode)
                await MainActor.run {
                    answer = result
                    analysisTimestamp = Date()
                    isAnalyzing = false
                }
                await corpus.ingestPhotoAnalysis(
                    photoId: UUID(),
                    analysisText: result,
                    metadata: ["mode": selectedMode.rawValue, "question": question]
                )
            } catch {
                await MainActor.run {
                    answer = "Error: \(error.localizedDescription)"
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
                    .textSelection(.enabled)
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
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Environment(\.dismiss) var dismiss: DismissAction

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
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
