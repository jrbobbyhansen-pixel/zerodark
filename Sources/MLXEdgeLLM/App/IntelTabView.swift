// IntelTabView.swift — Combined Knowledge Base + Vision Analysis (Phase 15)

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
                    TelemetryDashboard()
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
                                .foregroundColor(.secondary)
                        }
                    } else if intelMode == .vision {
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.caption)
                                .foregroundColor(VisionContentView.visionStatusColor)
                            Text(VisionContentView.visionStatusLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
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

// MARK: - Knowledge Content View

struct KnowledgeContentView: View {
    @StateObject private var rag = KnowledgeRAG.shared
    @StateObject private var inference = TextInferenceClient.shared
    @StateObject private var engine = LocalInferenceEngine.shared
    @StateObject private var protocolDB = ProtocolDatabase.shared
    @State private var mode: KnowledgeMode = .ask
    @State private var searchQuery = ""
    @State private var userQuestion = ""
    @State private var messages: [(role: String, content: String)] = []
    @State private var isLoading = false
    @State private var selectedChunk: KnowledgeChunk? = nil
    @State private var selectedCategory: KnowledgeCategory? = nil
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var fontSize: CGFloat = 14
    @State private var matchedProtocol: TacticalProtocol? = nil

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

    // Quick prompts mapped to protocol keywords for instant matching
    let quickPrompts = [
        "Sucking chest wound",           // → Sucking Chest Wound protocol
        "Tourniquet",                     // → Tourniquet Application protocol
        "CPR",                            // → CPR - Adult protocol
        "Severe bleeding",                // → Severe Bleeding Control protocol
        "Observation post setup",         // → Observation Post Setup protocol
        "Find water",                     // → Water Procurement protocol
        "Start fire",                     // → Fire Starting protocol
        "Emergency shelter",              // → Emergency Shelter protocol
        "React to contact",               // → React to Contact protocol
        "Being followed"                  // → Surveillance Detection protocol
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
                                Text("Ask Survival Questions")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Get AI-powered answers from the knowledge base")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                            ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                                HStack(alignment: .top) {
                                    if msg.role == "user" {
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(msg.content)
                                                .font(.body)
                                                .padding(10)
                                                .background(ZDDesign.skyBlue.opacity(0.7))
                                                .cornerRadius(8)
                                        }
                                    } else {
                                        VStack(alignment: .leading) {
                                            Text(msg.content)
                                                .font(.body)
                                                .padding(10)
                                                .background(ZDDesign.darkSage.opacity(0.3))
                                                .cornerRadius(8)
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal)
                                .id(idx)
                            }
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .tint(ZDDesign.skyBlue)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding()
                            }
                        }
                    }
                    .padding(.vertical)
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(messages.count - 1)
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
                    .foregroundColor(.white)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                            .foregroundColor(.white)
                        Text(chunk.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Image(systemName: chunk.category.icon)
                                .font(.caption)
                                .foregroundColor(chunk.category.zdColor)
                            Text(chunk.category.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
                            .foregroundColor(.white)
                        Text(chunk.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    .foregroundColor(.white)
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

    private func askQuestion(_ question: String) {
        messages.append(("user", question))
        
        // LAYER 1: Instant Protocol Match (<100ms) — Life or death needs FAST + ACCURATE
        if let proto = protocolDB.quickMatch(query: question) {
            // Show protocol card immediately
            matchedProtocol = proto
            messages.append(("assistant", "PROTOCOL MATCHED — Tap to view full card"))
            return
        }
        
        // LAYER 2: RAG Search (<500ms) — Knowledge base lookup
        let ragResults = rag.search(query: question, topK: 3)
        if !ragResults.isEmpty {
            let ragAnswer = ragResults.map { chunk in
                "**\(chunk.title)**\n\(chunk.content)"
            }.joined(separator: "\n\n---\n\n")
            messages.append(("assistant", ragAnswer))
            return
        }
        
        // LAYER 3: AI Synthesis (5-10s) — Only if no protocol or RAG match
        isLoading = true
        streamTask = Task {
            do {
                let context = rag.buildContext(for: question)
                let stream = try await inference.ask(question: question, context: context)
                await MainActor.run { messages.append(("assistant", "")) }
                for try await chunk in stream {
                    await MainActor.run {
                        if messages.last?.role == "assistant" {
                            let updated = (messages.last?.content ?? "") + chunk
                            messages[messages.count - 1] = ("assistant", updated)
                        }
                    }
                }
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    messages.append(("assistant", "No information found. Try rephrasing your question."))
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Vision Content View

struct VisionContentView: View {
    @StateObject private var rag = KnowledgeRAG.shared
    @StateObject private var vision = VisionInferenceClient.shared
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
                            .foregroundColor(.secondary)
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
                            .foregroundColor(.white)
                        Divider()
                        Text(answer)
                            .font(.body)
                            .lineSpacing(4)
                        Divider()
                        Text("Related Knowledge")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                                        .foregroundColor(.secondary)
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
                    .foregroundColor(.white)
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
    @Environment(\.dismiss) var dismiss

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
