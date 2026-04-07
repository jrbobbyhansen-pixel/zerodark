import Foundation

// MARK: - InferenceCache

final class InferenceCache {
    private let cache = NSCache<NSString, CachedInferenceResult>()
    private let ttl: TimeInterval
    private let maxMemoryCost: Int

    init(ttl: TimeInterval, maxMemoryCost: Int) {
        self.ttl = ttl
        self.maxMemoryCost = maxMemoryCost
        cache.totalCostLimit = maxMemoryCost
    }

    func get(forKey key: String) -> CachedInferenceResult? {
        let cachedResult = cache.object(forKey: key as NSString)
        guard let result = cachedResult, !result.isExpired else {
            cache.removeObject(forKey: key as NSString)
            return nil
        }
        return result
    }

    func set(_ result: InferenceResult, forKey key: String) {
        let cachedResult = CachedInferenceResult(result: result, expirationDate: Date().addingTimeInterval(ttl))
        cache.setObject(cachedResult, forKey: key as NSString, cost: cachedResult.memoryCost)
    }

    func invalidateCache() {
        cache.removeAllObjects()
    }
}

// MARK: - CachedInferenceResult

private final class CachedInferenceResult {
    let result: InferenceResult
    let expirationDate: Date
    let memoryCost: Int

    init(result: InferenceResult, expirationDate: Date) {
        self.result = result
        self.expirationDate = expirationDate
        self.memoryCost = result.estimatedMemoryCost
    }

    var isExpired: Bool {
        return Date() > expirationDate
    }
}

// MARK: - InferenceResult

struct InferenceResult {
    let data: Data
    let estimatedMemoryCost: Int
}

// MARK: - InferenceResult + MemoryCost

extension InferenceResult {
    init(data: Data) {
        self.data = data
        self.estimatedMemoryCost = data.count
    }
}