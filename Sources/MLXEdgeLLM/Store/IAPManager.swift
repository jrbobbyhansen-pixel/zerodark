// IAPManager.swift — StoreKit 2 In-App Purchase manager for DronePacks and NavDEMs
// Products: com.zerodark.dronepack, com.zerodark.navdem

import StoreKit
import Foundation

@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    @Published var dronePack: Product?
    @Published var navDEMPack: Product?
    @Published var isDronePackPurchased = false
    @Published var isNavDEMPurchased = false
    @Published var isLoading = false

    private let productIDs: Set<String> = [
        "com.zerodark.dronepack",
        "com.zerodark.navdem"
    ]

    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = listenForUpdates()
        Task { await checkEntitlements() }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: productIDs)
            for product in products {
                switch product.id {
                case "com.zerodark.dronepack":
                    dronePack = product
                case "com.zerodark.navdem":
                    navDEMPack = product
                default:
                    break
                }
            }
        } catch {
            // Products unavailable (e.g. sandbox, no network)
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchaseState(transaction)
            await transaction.finish()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            await updatePurchaseState(transaction)
        }
    }

    // MARK: - Transaction Updates

    private func listenForUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let transaction = try? self?.checkVerified(result) else { continue }
                await self?.updatePurchaseState(transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func updatePurchaseState(_ transaction: Transaction) async {
        switch transaction.productID {
        case "com.zerodark.dronepack":
            isDronePackPurchased = transaction.revocationDate == nil
        case "com.zerodark.navdem":
            isNavDEMPurchased = transaction.revocationDate == nil
        default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }
}
