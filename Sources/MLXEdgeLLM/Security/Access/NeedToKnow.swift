import Foundation
import SwiftUI

// MARK: - NeedToKnow

class NeedToKnow: ObservableObject {
    @Published var accessRequests: [AccessRequest] = []
    @Published var approvedAccess: [AccessRequest] = []
    
    func requestAccess(for user: User, to data: Data) {
        let request = AccessRequest(user: user, data: data)
        accessRequests.append(request)
        // Notify relevant authorities or workflow for approval
    }
    
    func approveAccess(_ request: AccessRequest) {
        if let index = accessRequests.firstIndex(of: request) {
            accessRequests.remove(at: index)
            approvedAccess.append(request)
        }
    }
    
    func denyAccess(_ request: AccessRequest) {
        if let index = accessRequests.firstIndex(of: request) {
            accessRequests.remove(at: index)
        }
    }
}

// MARK: - AccessRequest

struct AccessRequest: Identifiable, Equatable {
    let id = UUID()
    let user: User
    let data: Data
}

// MARK: - User

struct User: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let role: String
}

// MARK: - Data

struct Data: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let content: String
    let sensitivityLevel: SensitivityLevel
}

// MARK: - SensitivityLevel

enum SensitivityLevel: String, Equatable {
    case publicData
    case confidential
    case secret
    case topSecret
}

// MARK: - SwiftUI View

struct AccessRequestView: View {
    @StateObject private var viewModel = NeedToKnow()
    
    var body: some View {
        VStack {
            List(viewModel.accessRequests) { request in
                HStack {
                    Text(request.user.name)
                    Spacer()
                    Text(request.data.title)
                }
                .onTapGesture {
                    viewModel.approveAccess(request)
                }
            }
            .listStyle(PlainListStyle())
            
            List(viewModel.approvedAccess) { request in
                HStack {
                    Text(request.user.name)
                    Spacer()
                    Text(request.data.title)
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("Access Requests")
    }
}

// MARK: - Preview

struct AccessRequestView_Previews: PreviewProvider {
    static var previews: some View {
        AccessRequestView()
    }
}