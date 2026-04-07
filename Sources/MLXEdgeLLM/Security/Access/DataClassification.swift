import Foundation
import SwiftUI

// MARK: - Data Classification System

enum DataSensitivity: String, Codable, CaseIterable {
    case unclassified
    case sensitive
    case confidential
    case secret
    
    var color: Color {
        switch self {
        case .unclassified: return .green
        case .sensitive: return .yellow
        case .confidential: return .orange
        case .secret: return .red
        }
    }
    
    var accessLevel: AccessLevel {
        switch self {
        case .unclassified: return .publicAccess
        case .sensitive: return .restrictedAccess
        case .confidential: return .controlledAccess
        case .secret: return .topSecretAccess
        }
    }
}

enum AccessLevel: String, Codable {
    case publicAccess
    case restrictedAccess
    case controlledAccess
    case topSecretAccess
}

struct DataItem: Identifiable, Codable {
    let id = UUID()
    let content: String
    let sensitivity: DataSensitivity
}

class DataClassificationService: ObservableObject {
    @Published var dataItems: [DataItem] = []
    
    func classifyData(_ content: String) -> DataItem {
        // Placeholder logic for classification
        let sensitivity: DataSensitivity = .unclassified // Replace with actual classification logic
        return DataItem(content: content, sensitivity: sensitivity)
    }
    
    func addData(_ content: String) {
        let classifiedData = classifyData(content)
        dataItems.append(classifiedData)
    }
}

// MARK: - SwiftUI View

struct DataClassificationView: View {
    @StateObject private var viewModel = DataClassificationService()
    @State private var newContent = ""
    
    var body: some View {
        VStack {
            TextField("Enter data", text: $newContent)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                viewModel.addData(newContent)
                newContent = ""
            }) {
                Text("Classify and Add")
            }
            .padding()
            
            List(viewModel.dataItems) { item in
                HStack {
                    Text(item.content)
                        .foregroundColor(item.sensitivity.color)
                    Spacer()
                    Text(item.sensitivity.rawValue.capitalized)
                        .foregroundColor(item.sensitivity.color)
                }
                .padding()
                .background(item.sensitivity.color.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding()
        .navigationTitle("Data Classification")
    }
}

struct DataClassificationView_Previews: PreviewProvider {
    static var previews: some View {
        DataClassificationView()
    }
}