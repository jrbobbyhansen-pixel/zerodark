// ShareSheet.swift — UIActivityViewController wrapper for SwiftUI

import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Make URL conformant for .sheet(item:) usage
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
