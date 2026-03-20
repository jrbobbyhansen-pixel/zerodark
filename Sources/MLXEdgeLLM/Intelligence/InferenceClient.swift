import Foundation
import UIKit

// MARK: - Text Inference (BitNet-2B via llama.cpp server, port 8080)

@MainActor
final class TextInferenceClient: ObservableObject {
    static let shared = TextInferenceClient()

    @Published var isConnected = false
    @Published var isGenerating = false

    var isLocalEngineReady: Bool { LocalInferenceEngine.shared.modelState == .ready }
    var isAvailable: Bool { isLocalEngineReady || isConnected }

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "textServerURL") ?? "http://192.168.1.100:8080" }
        set { UserDefaults.standard.set(newValue, forKey: "textServerURL") }
    }

    private var streamTask: URLSessionDataTask?
    private init() { Task { await checkConnection() } }

    func checkConnection() async {
        guard let url = URL(string: "\(serverURL)/health") else { isConnected = false; return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isConnected = false
            print("[ZeroDark] TextInferenceClient unreachable: \(error)")
        }
    }

    func ask(question: String, context: String) async throws -> AsyncStream<String> {
        // Priority 1: on-device inference
        if isLocalEngineReady {
            isGenerating = true
            return AsyncStream { continuation in
                Task {
                    defer { Task { @MainActor in self.isGenerating = false } }
                    let onToken: @MainActor (String) -> Void = { token in
                        continuation.yield(token)
                    }
                    let onComplete: @MainActor () -> Void = {
                        continuation.finish()
                    }
                    let rawPrompt: String
                    if context.isEmpty {
                        rawPrompt = question
                    } else {
                        rawPrompt = "Use the following field manual extracts to answer the question.\n\nFIELD MANUAL EXTRACTS:\n\(context)\n\nQUESTION: \(question)"
                    }
                    await LocalInferenceEngine.shared.generate(
                        prompt: rawPrompt,
                        maxTokens: 512,
                        onToken: onToken,
                        onComplete: onComplete
                    )
                }
            }
        }

        // Priority 2: remote server (existing SSE streaming)
        guard let url = URL(string: "\(serverURL)/v1/chat/completions") else {
            throw InferenceError.invalidURL
        }
        let systemPrompt = "You are a survival and tactical expert. Answer based ONLY on the provided knowledge base content. Be direct, specific, include exact measurements and timing. If information is not in the knowledge base, say so clearly."
        let userContent = context.isEmpty ? question : "\(context)\n\nQUESTION: \(question)"
        let body: [String: Any] = [
            "model": "bitnet",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 512, "temperature": 0.1, "stream": true
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        isGenerating = true
        return AsyncStream { [weak self] continuation in
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                defer {
                    Task { @MainActor in self?.isGenerating = false }
                    continuation.finish()
                }
                guard let data, error == nil else {
                    print("[ZeroDark] TextInferenceClient error: \(String(describing: error))")
                    return
                }
                String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { $0.hasPrefix("data: ") && $0 != "data: [DONE]" }
                    .compactMap { line -> String? in
                        guard let d = line.dropFirst(6).data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { return nil }
                        return content
                    }
                    .forEach { continuation.yield($0) }
            }
            task.resume()
            self?.streamTask = task
        }
    }

    func cancel() {
        if LocalInferenceEngine.shared.isGenerating {
            LocalInferenceEngine.shared.cancel()
        }
        streamTask?.cancel()
        isGenerating = false
    }

    // MARK: - Private

    private func buildPrompt(systemContext: String, userQuery: String) -> String {
        let systemPrompt = """
        You are a tactical field advisor. You have been given relevant extracts from a field manual. \
        Answer the operator's question directly and concisely using only the provided context. \
        Prioritize actionable steps. If the answer requires immediate action, lead with the most \
        critical step first. Do not add information not present in the context.

        FIELD MANUAL EXTRACTS:
        """

        return """
        <|system|>
        \(systemPrompt)
        \(systemContext)<|end|>
        <|user|>
        \(userQuery)<|end|>
        <|assistant|>

        """
    }
}

// MARK: - Vision Inference (moondream2 via Python/Flask server, port 8081)

@MainActor
final class VisionInferenceClient: ObservableObject {
    static let shared = VisionInferenceClient()

    @Published var isConnected = false
    @Published var isProcessing = false

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "visionServerURL") ?? "http://192.168.1.100:8081" }
        set { UserDefaults.standard.set(newValue, forKey: "visionServerURL") }
    }

    private init() { Task { await checkConnection() } }

    func checkConnection() async {
        guard let url = URL(string: "\(serverURL)/health") else { isConnected = false; return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isConnected = false
            print("[ZeroDark] VisionInferenceClient unreachable: \(error)")
        }
    }

    func query(image: UIImage, question: String) async throws -> String {
        guard let url = URL(string: "\(serverURL)/query") else { throw InferenceError.invalidURL }
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { throw InferenceError.imageEncodingFailed }
        let boundary = "ZDMultipart\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"question\"\r\n\r\n".data(using: .utf8)!)
        body.append(question.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 45
        isProcessing = true
        defer { isProcessing = false }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = json["answer"] as? String else {
            throw InferenceError.invalidResponse
        }
        return answer
    }
}

enum InferenceError: Error {
    case invalidURL
    case imageEncodingFailed
    case invalidResponse
    case serverUnavailable
    // Phase 8b
    case modelNotLoaded
    case modelLoadFailed(String)
    case tokenizationFailed
    case decodeFailed
    case samplerFailed
}
