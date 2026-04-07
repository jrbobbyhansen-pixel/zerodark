import Foundation
import SwiftUI

// MARK: - DTN Bundle Model

struct DTNBundle: Identifiable {
    let id: UUID
    let payload: Data
    let custodyChain: [String]
    let ttl: TimeInterval
    let priority: Int
    var deliveryStatus: DeliveryStatus
}

enum DeliveryStatus {
    case pending
    case delivered
    case failed
}

// MARK: - DTN Bundle Inspector ViewModel

class DTNBundleInspectorViewModel: ObservableObject {
    @Published var bundles: [DTNBundle] = []
    @Published var selectedBundle: DTNBundle? = nil
    
    func inspectBundle(_ bundle: DTNBundle) {
        selectedBundle = bundle
    }
    
    func retryDelivery(for bundle: DTNBundle) {
        // Implement retry logic here
        bundle.deliveryStatus = .pending
    }
    
    func dropBundle(_ bundle: DTNBundle) {
        if let index = bundles.firstIndex(of: bundle) {
            bundles.remove(at: index)
        }
    }
}

// MARK: - DTN Bundle Inspector View

struct DTNBundleInspectorView: View {
    @StateObject private var viewModel = DTNBundleInspectorViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.bundles) { bundle in
                HStack {
                    Text("Bundle \(bundle.id.uuidString.prefix(8))")
                    Spacer()
                    Text("\(bundle.deliveryStatus.rawValue)")
                        .foregroundColor(bundle.deliveryStatus == .failed ? .red : .green)
                }
                .onTapGesture {
                    viewModel.inspectBundle(bundle)
                }
            }
            .navigationTitle("DTN Bundle Inspector")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new bundle logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $viewModel.selectedBundle) { bundle in
                BundleDetailView(bundle: bundle, viewModel: viewModel)
            }
        }
    }
}

struct BundleDetailView: View {
    let bundle: DTNBundle
    let viewModel: DTNBundleInspectorViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Payload:")
                .font(.headline)
            Text(String(data: bundle.payload, encoding: .utf8) ?? "Invalid payload")
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Text("Custody Chain:")
                .font(.headline)
            ForEach(bundle.custodyChain, id: \.self) { node in
                Text(node)
            }
            
            Text("TTL: \(bundle.ttl, specifier: "%.1f") seconds")
                .font(.headline)
            
            Text("Priority: \(bundle.priority)")
                .font(.headline)
            
            HStack {
                Button(action: {
                    viewModel.retryDelivery(for: bundle)
                }) {
                    Text("Retry")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.dropBundle(bundle)
                }) {
                    Text("Drop")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .navigationTitle("Bundle Details")
    }
}

// MARK: - Preview

struct DTNBundleInspectorView_Previews: PreviewProvider {
    static var previews: some View {
        DTNBundleInspectorView()
            .environmentObject(DTNBundleInspectorViewModel())
    }
}