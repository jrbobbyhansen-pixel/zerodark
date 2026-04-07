import Foundation

// AX.25 Frame Handler
// This file contains the implementation for encoding and decoding AX.25 frames
// for packet radio communication.

// Constants for AX.25 frame structure
private let AX25_ADDRESS_SIZE = 7
private let AX25_CONTROL_FIELD = 0x03
private let AX25_PID = 0xF0  // Uncompressed No Layer 3 Protocol ID

// AX25Address struct
struct AX25Address {
    var callsign: String
    var ssid: Int
    
    init(callsign: String, ssid: Int) {
        self.callsign = callsign
        self.ssid = ssid
    }
    
    func toBytes() -> [UInt8] {
        var bytes = [UInt8]()
        for char in callsign.uppercased().prefix(6) {
            bytes.append(UInt8(char.asciiValue ?? 0) << 1)
        }
        bytes.append(UInt8(ssid & 0x0F) << 1 | 0x60)
        return bytes
    }
}

// AX25Frame struct
struct AX25Frame {
    var source: AX25Address
    var destination: AX25Address
    var digipeaters: [AX25Address]
    var information: [UInt8]
    
    init(source: AX25Address, destination: AX25Address, digipeaters: [AX25Address], information: [UInt8]) {
        self.source = source
        self.destination = destination
        self.digipeaters = digipeaters
        self.information = information
    }
    
    func encode() -> [UInt8] {
        var frame = [UInt8]()
        
        // Destination Address
        frame.append(contentsOf: destination.toBytes())
        
        // Source Address
        frame.append(contentsOf: source.toBytes())
        
        // Digipeaters
        for digi in digipeaters {
            frame.append(contentsOf: digi.toBytes())
        }
        
        // Control Field
        frame.append(AX25_CONTROL_FIELD)
        
        // Protocol Identifier
        frame.append(AX25_PID)
        
        // Information Field
        frame.append(contentsOf: information)
        
        // FCS (Frame Check Sequence) - Placeholder, actual implementation needed
        frame.append(0x00)
        frame.append(0x00)
        
        return frame
    }
}

// AX25Decoder class
class AX25Decoder {
    func decode(_ data: [UInt8]) -> AX25Frame? {
        guard data.count >= 16 else { return nil }
        
        var index = 0
        
        // Destination Address
        let destinationBytes = Array(data[index..<(index + AX25_ADDRESS_SIZE)])
        index += AX25_ADDRESS_SIZE
        
        // Source Address
        let sourceBytes = Array(data[index..<(index + AX25_ADDRESS_SIZE)])
        index += AX25_ADDRESS_SIZE
        
        // Digipeaters
        var digipeaters: [AX25Address] = []
        while index < data.count && data[index] != AX25_CONTROL_FIELD {
            let digiBytes = Array(data[index..<(index + AX25_ADDRESS_SIZE)])
            index += AX25_ADDRESS_SIZE
            if let digiAddress = AX25Address.fromBytes(digiBytes) {
                digipeaters.append(digiAddress)
            }
        }
        
        // Control Field
        guard data[index] == AX25_CONTROL_FIELD else { return nil }
        index += 1
        
        // Protocol Identifier
        guard data[index] == AX25_PID else { return nil }
        index += 1
        
        // Information Field
        let information = Array(data[index..<(data.count - 2)])
        
        // FCS (Frame Check Sequence) - Placeholder, actual implementation needed
        
        return AX25Frame(source: AX25Address.fromBytes(sourceBytes)!, destination: AX25Address.fromBytes(destinationBytes)!, digipeaters: digipeaters, information: information)
    }
}

// AX25Address extension for decoding
extension AX25Address {
    static func fromBytes(_ bytes: [UInt8]) -> AX25Address? {
        guard bytes.count == AX25_ADDRESS_SIZE else { return nil }
        
        var callsign = ""
        for byte in bytes[0..<6] {
            callsign.append(Character(UnicodeScalar((byte >> 1) & 0x7F) ?? " "))
        }
        
        let ssid = (bytes[6] >> 1) & 0x0F
        
        return AX25Address(callsign: callsign, ssid: ssid)
    }
}

// KISSFramer class
class KISSFramer {
    func encode(_ ax25Frame: AX25Frame) -> [UInt8] {
        var frame = [UInt8]()
        
        // FEND
        frame.append(0xC0)
        
        // Data
        for byte in ax25Frame.encode() {
            if byte == 0xC0 {
                frame.append(0xDB)
                frame.append(0xDC)
            } else if byte == 0xDB {
                frame.append(0xDB)
                frame.append(0xDD)
            } else {
                frame.append(byte)
            }
        }
        
        // FEND
        frame.append(0xC0)
        
        return frame
    }
    
    func decode(_ data: [UInt8]) -> AX25Frame? {
        var decodedData = [UInt8]()
        var escape = false
        
        for byte in data {
            if byte == 0xDB {
                escape = true
            } else if escape {
                if byte == 0xDC {
                    decodedData.append(0xC0)
                } else if byte == 0xDD {
                    decodedData.append(0xDB)
                }
                escape = false
            } else {
                decodedData.append(byte)
            }
        }
        
        // Remove FEND markers
        if decodedData.first == 0xC0 {
            decodedData.removeFirst()
        }
        if decodedData.last == 0xC0 {
            decodedData.removeLast()
        }
        
        return AX25Decoder().decode(decodedData)
    }
}