import Foundation
import Combine

// MARK: - JsonApiClient

@MainActor
final class JsonApiClient: ObservableObject {
    @Published private(set) var isAuthenticated = false
    private var authenticationToken: String?
    private var offlineQueue: [Request] = []
    private var isOnline = true
    private var retryInterval: TimeInterval = 10
    private var cache = [String: CachedResponse]()
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange)
            .sink { [weak self] _ in
                self?.checkNetworkStatus()
            }
            .store(in: &cancellables)
    }

    func authenticate(token: String) {
        authenticationToken = token
        isAuthenticated = true
    }

    func request<T: Decodable>(endpoint: Endpoint, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = endpoint.url else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }

        if isOnline {
            performRequest(url: url, completion: completion)
        } else {
            offlineQueue.append(Request(url: url, completion: completion))
        }
    }

    private func performRequest<T: Decodable>(url: URL, completion: @escaping (Result<T, Error>) -> Void) {
        if let cachedResponse = cache[url.absoluteString], cachedResponse.isValid {
            completion(.success(cachedResponse.data))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authenticationToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response in
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Invalid response", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: nil)
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    self.handleRequestFailure(url: url, error: error)
                }
            }, receiveValue: { data in
                self.cache[url.absoluteString] = CachedResponse(data: data, timestamp: Date())
                completion(.success(data))
            })
            .store(in: &cancellables)
    }

    private func handleRequestFailure(url: URL, error: Error) {
        if isOnline {
            retryRequest(url: url)
        } else {
            offlineQueue.append(Request(url: url, completion: { _ in }))
        }
    }

    private func retryRequest(url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) {
            if let request = self.offlineQueue.first(where: { $0.url == url }) {
                self.performRequest(url: url, completion: request.completion)
                self.offlineQueue.removeAll { $0.url == url }
            }
        }
    }

    private func checkNetworkStatus() {
        isOnline = NetworkMonitor.shared.isReachable
        if isOnline {
            processOfflineQueue()
        }
    }

    private func processOfflineQueue() {
        offlineQueue.forEach { request in
            performRequest(url: request.url, completion: request.completion)
        }
        offlineQueue.removeAll()
    }
}

// MARK: - Endpoint

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

protocol Endpoint {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem]? { get }
}

extension Endpoint {
    var url: URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems
        return components?.url
    }
}

// MARK: - CachedResponse

struct CachedResponse<T: Codable> {
    let data: T
    let timestamp: Date

    var isValid: Bool {
        // Define your cache validity logic here
        return Date().timeIntervalSince(timestamp) < 3600 // 1 hour
    }
}

// MARK: - Request

struct Request {
    let url: URL
    let completion: (Result<Any, Error>) -> Void
}

// MARK: - NetworkMonitor

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let reachability = Reachability()!

    var isReachable: Bool {
        return reachability.connection != .unavailable
    }

    private init() {
        reachability.whenReachable = { [weak self] reachability in
            self?.isReachable = true
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.isReachable = false
        }
        do {
            try reachability.startNotifier()
        } catch {
            print("Unable to start reachability notifier")
        }
    }
}