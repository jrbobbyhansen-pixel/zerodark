import Foundation

// MARK: - LoRa Packet Handling

struct LoraPacket {
    let spreadingFactor: Int
    let bandwidth: Int
    let codingRate: String
    let payload: Data
    
    init(spreadingFactor: Int, bandwidth: Int, codingRate: String, payload: Data) {
        self.spreadingFactor = spreadingFactor
        self.bandwidth = bandwidth
        self.codingRate = codingRate
        self.payload = payload
    }
    
    func encode() -> Data {
        var encodedData = Data()
        encodedData.append(UInt8(spreadingFactor))
        encodedData.append(UInt8(bandwidth))
        encodedData.append(Data(codingRate.utf8))
        encodedData.append(payload)
        return encodedData
    }
    
    static func decode(from data: Data) -> LoraPacket? {
        guard data.count >= 3 else { return nil }
        
        let spreadingFactor = Int(data[0])
        let bandwidth = Int(data[1])
        let codingRateLength = data[2]
        guard data.count >= 3 + codingRateLength else { return nil }
        
        let codingRateData = data[3..<(3 + codingRateLength)]
        guard let codingRate = String(data: codingRateData, encoding: .utf8) else { return nil }
        
        let payload = data[(3 + codingRateLength)...]
        
        return LoraPacket(spreadingFactor: spreadingFactor, bandwidth: bandwidth, codingRate: codingRate, payload: payload)
    }
}

// MARK: - Constants

extension LoraPacket {
    static let defaultSpreadingFactor = 7
    static let defaultBandwidth = 125000
    static let defaultCodingRate = "4/5"
}

// MARK: - Example Usage

struct LoraPacketExample {
    static func createExamplePacket() -> LoraPacket {
        let payload = "Hello, LoRa!".data(using: .utf8)!
        return LoraPacket(spreadingFactor: LoraPacket.defaultSpreadingFactor, bandwidth: LoraPacket.defaultBandwidth, codingRate: LoraPacket.defaultCodingRate, payload: payload)
    }
    
    static func decodeExamplePacket(data: Data) -> LoraPacket? {
        return LoraPacket.decode(from: data)
    }
}