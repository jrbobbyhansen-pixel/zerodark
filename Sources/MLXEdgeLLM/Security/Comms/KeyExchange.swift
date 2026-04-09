import Foundation
import SwiftUI

// MARK: - KeyExchange

class KeyExchange: ObservableObject {
    @Published var qrCodeData: Data?
    @Published var nfcData: Data?
    @Published var audioData: Data?
    @Published var visualData: Data?
    @Published var verificationCode: String?
    
    func generateQRCode() {
        // Generate QR code data
        let key = "SecureKey\(UUID().uuidString)"
        if let data = key.data(using: .utf8) {
            qrCodeData = data
        }
    }
    
    func generateNFCData() {
        // Generate NFC data
        let key = "SecureKey\(UUID().uuidString)"
        if let data = key.data(using: .utf8) {
            nfcData = data
        }
    }
    
    func generateAudioData() {
        // Generate audio data
        let key = "SecureKey\(UUID().uuidString)"
        if let data = key.data(using: .utf8) {
            audioData = data
        }
    }
    
    func generateVisualData() {
        // Generate visual data
        let key = "SecureKey\(UUID().uuidString)"
        if let data = key.data(using: .utf8) {
            visualData = data
        }
    }
    
    func verifyKeyExchange(code: String) {
        // Verify key exchange with verification code
        verificationCode = code
    }
}

// MARK: - KeyExchangeView

struct KeyExchangeView: View {
    @StateObject private var keyExchange = KeyExchange()
    
    var body: some View {
        VStack {
            Button("Generate QR Code") {
                keyExchange.generateQRCode()
            }
            
            Button("Generate NFC Data") {
                keyExchange.generateNFCData()
            }
            
            Button("Generate Audio Data") {
                keyExchange.generateAudioData()
            }
            
            Button("Generate Visual Data") {
                keyExchange.generateVisualData()
            }
            
            if let qrCodeData = keyExchange.qrCodeData {
                QRCodeView(data: qrCodeData)
            }
            
            if let nfcData = keyExchange.nfcData {
                Text("NFC Data: \(nfcData.base64EncodedString())")
            }
            
            if let audioData = keyExchange.audioData {
                Text("Audio Data: \(audioData.base64EncodedString())")
            }
            
            if let visualData = keyExchange.visualData {
                Text("Visual Data: \(visualData.base64EncodedString())")
            }
            
            TextField("Verification Code", text: $keyExchange.verificationCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Verify Key Exchange") {
                keyExchange.verifyKeyExchange(code: keyExchange.verificationCode ?? "")
            }
        }
        .padding()
    }
}

// MARK: - QRCodeView

struct QRCodeView: View {
    let data: Data
    
    var body: some View {
        Image(uiImage: generateQRCode(from: data))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
    }
    
    private func generateQRCode(from data: Data) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator
        filter.message = data
        if let output = filter.outputImage {
            let scaleX = 10.0
            let scaleY = 10.0
            let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            let scaledOutput = output.transformed(by: transform)
            return UIImage(ciImage: scaledOutput)
        }
        return nil
    }
}

// MARK: - Preview

struct KeyExchangeView_Previews: PreviewProvider {
    static var previews: some View {
        KeyExchangeView()
    }
}