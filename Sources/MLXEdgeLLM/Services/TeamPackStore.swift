// TeamPackStore.swift — StoreKit 2 IAP for TeamPacks (unlimited rosters)
// BUILD_SPEC v6.2: IAP TeamPacks check

import Foundation
import StoreKit

@MainActor
final class TeamPackStore: ObservableObject {
    static let shared = TeamPackStore()

    static let freeRosterLimit = 5

    @Published var hasUnlimitedRoster = false
    @Published var products: [Product] = []
    @Published var purchaseInProgress = false

    private let productIds: Set<String> = ["com.zerodark.teampack.unlimited"]
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await checkEntitlements() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
        } catch {
            products = []
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            hasUnlimitedRoster = true
            await transaction.finish()

        case .userCancelled:
            break

        case .pending:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               productIds.contains(transaction.productID) {
                hasUnlimitedRoster = true
                return
            }
        }
        hasUnlimitedRoster = false
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await MainActor.run {
                        self?.hasUnlimitedRoster = true
                    }
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
