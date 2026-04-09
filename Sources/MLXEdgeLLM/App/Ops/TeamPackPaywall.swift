// TeamPackPaywall.swift — IAP paywall for TeamPacks (unlimited rosters)
// BUILD_SPEC v6.2: IAP TeamPacks check

import SwiftUI
import StoreKit

struct TeamPackPaywall: View {
    @StateObject private var store = TeamPackStore.shared
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 48))
                                .foregroundColor(ZDDesign.cyanAccent)

                            Text("TeamPack")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(ZDDesign.pureWhite)

                            Text("Unlock unlimited team roster size for full operational capability.")
                                .font(.subheadline)
                                .foregroundColor(ZDDesign.mediumGray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Free tier info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(ZDDesign.safetyYellow)
                                Text("Free tier limited to \(TeamPackStore.freeRosterLimit) team members")
                                    .font(.subheadline)
                                    .foregroundColor(ZDDesign.pureWhite)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ZDDesign.darkCard)
                        .cornerRadius(ZDDesign.radiusMedium)

                        // Features
                        VStack(alignment: .leading, spacing: 12) {
                            featureRow(icon: "person.3.fill", text: "Unlimited roster size")
                            featureRow(icon: "antenna.radiowaves.left.and.right", text: "Full mesh peer tracking")
                            featureRow(icon: "location.fill", text: "All peer locations & status")
                            featureRow(icon: "battery.100", text: "Battery monitoring for all peers")
                        }
                        .padding()
                        .background(ZDDesign.darkCard)
                        .cornerRadius(ZDDesign.radiusMedium)

                        // Purchase button
                        if let product = store.products.first {
                            Button {
                                Task {
                                    try? await store.purchase(product)
                                    if store.hasUnlimitedRoster {
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    if store.purchaseInProgress {
                                        ProgressView().tint(.black)
                                    } else {
                                        Text("Upgrade — \(product.displayPrice)")
                                            .fontWeight(.bold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ZDDesign.cyanAccent)
                                .foregroundColor(.black)
                                .cornerRadius(ZDDesign.radiusMedium)
                            }
                            .disabled(store.purchaseInProgress)
                        } else {
                            ProgressView("Loading...")
                                .tint(ZDDesign.cyanAccent)
                        }

                        // Restore
                        Button {
                            Task {
                                await store.restorePurchases()
                                if store.hasUnlimitedRoster {
                                    dismiss()
                                }
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.caption)
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("TeamPack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .task {
                await store.loadProducts()
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(ZDDesign.cyanAccent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(ZDDesign.pureWhite)
        }
    }
}
